#include "matmul_runtime.hpp"
#include <sstream>
#include <stdexcept>
#include <string>

namespace {
constexpr std::uint32_t COMMAND = 0x0004, STATUS = 0x0008;
constexpr std::uint32_t ACK = 0x000c, ERROR_STATUS = 0x0010;
constexpr std::uint32_t A_BASE = 0x1000, B_BASE = 0x2000, C_BASE = 0x3000;
constexpr std::uint32_t BUSY = 1u, DONE = 2u, INPUTS_READY = 4u, ERROR = 8u;
}

MatmulRuntime::MatmulRuntime(AxiLiteBfm& bfm, std::uint64_t poll_timeout_cycles)
    : bfm_(bfm), poll_timeout_cycles_(poll_timeout_cycles) {
    if (poll_timeout_cycles_ == 0)
        throw std::invalid_argument("Runtime poll timeout must be nonzero");
    // Capability reads are construction-time setup, deliberately outside each
    // invocation's cycle accounting and never inferred from software defaults.
    config_ = {bfm_.axi_read(0x0020), bfm_.axi_read(0x0024),
               bfm_.axi_read(0x0028), bfm_.axi_read(0x002c)};
    const auto nk = std::uint64_t{config_.n} * config_.k;
    const auto nn = std::uint64_t{config_.n} * config_.n;
    if (config_.n == 0 || config_.k == 0 || nk > 1024 || nn > 1024 ||
        config_.data_w != 8 || config_.acc_w != 18)
        throw std::runtime_error("Unsupported hardware shape or dtype contract");
}

void MatmulRuntime::validate_matrix(const InputMatrix& matrix, std::size_t rows,
                                    std::size_t cols, const char* name) {
    if (matrix.rows != rows || matrix.cols != cols || matrix.data.size() != rows*cols)
        throw std::invalid_argument(std::string(name) + ": shape or storage size mismatch");
}

void MatmulRuntime::check_device_error(std::uint32_t status) {
    if (!(status & ERROR)) return;
    const auto errors = bfm_.axi_read(ERROR_STATUS);
    std::ostringstream message;
    message << "Device sticky error 0x" << std::hex << errors
            << "; not cleared automatically";
    throw std::runtime_error(message.str());
}

MatmulResult MatmulRuntime::matmul(const InputMatrix& a, const InputMatrix& b) {
    // Validate before any transaction; malformed inputs cannot touch hardware.
    validate_matrix(a, config_.n, config_.k, "A");
    validate_matrix(b, config_.k, config_.n, "B");
    MatmulResult result{{config_.n, config_.n,
                         std::vector<std::int32_t>(std::size_t{config_.n}*config_.n)}, {}};
    auto& timing = result.cycles;
    const auto begin = bfm_.cycles();
    auto phase = begin;
    auto status = bfm_.axi_read(STATUS);
    // Runtime owns one non-overlapped operation. It does not clear sticky
    // errors or ACK an older result on the caller's behalf because either
    // action would destroy diagnostic state or another owner's result.
    check_device_error(status);
    if (status & (BUSY | DONE))
        throw std::runtime_error("Device is busy or has an unacknowledged result");
    timing.preflight = bfm_.cycles() - phase;

    phase = bfm_.cycles();
    // Row-major software order matches the Device's fixed-coordinate address
    // contract. This Runtime uses the normal one-INT8-per-word windows; packed
    // transport remains an experimental driver responsibility.
    for (std::size_t x = 0; x < a.data.size(); ++x)
        bfm_.axi_write(A_BASE + 4u*static_cast<std::uint32_t>(x),
                        static_cast<std::uint8_t>(a.data[x]), 0x1);
    for (std::size_t x = 0; x < b.data.size(); ++x)
        bfm_.axi_write(B_BASE + 4u*static_cast<std::uint32_t>(x),
                        static_cast<std::uint8_t>(b.data[x]), 0x1);
    status = bfm_.axi_read(STATUS);
    check_device_error(status);
    if ((status & (BUSY | DONE | INPUTS_READY)) != INPUTS_READY)
        throw std::runtime_error("Device not ready after complete A/B load");
    timing.load = bfm_.cycles() - phase;

    phase = bfm_.cycles();
    bfm_.axi_write(COMMAND, 1);
    const auto poll_begin = bfm_.cycles();
    while (true) {
        // Poll budget starts after the START response. No artificial idle delay.
        // Finish the current bus read before checking time; observation may
        // overshoot the budget by at most one blocking read transaction.
        if (bfm_.cycles() - poll_begin >= poll_timeout_cycles_)
            throw std::runtime_error("Runtime completion timeout; device not ACKed/reset");
        status = bfm_.axi_read(STATUS);
        ++timing.poll_reads;
        check_device_error(status);
        if (status & DONE) {
            if (status & BUSY) throw std::runtime_error("Device reports BUSY and DONE together");
            break;
        }
    }
    timing.start_poll = bfm_.cycles() - phase;

    phase = bfm_.cycles();
    // Results are copied before ACK because ACK returns Device to LOAD and
    // releases the sticky DONE snapshot for the next operation.
    for (std::size_t x = 0; x < result.c.data.size(); ++x) {
        const auto raw = bfm_.axi_read(C_BASE + 4u*static_cast<std::uint32_t>(x));
        const auto low = static_cast<std::int32_t>(raw & 0x3ffffu);
        result.c.data[x] = (low & 0x20000) ? low - 0x40000 : low;
    }
    timing.readback = bfm_.cycles() - phase;

    phase = bfm_.cycles();
    bfm_.axi_write(ACK, 1); // Only after ALL results have been copied to host memory.
    timing.ack = bfm_.cycles() - phase;
    timing.total = bfm_.cycles() - begin;
    return result;
}
