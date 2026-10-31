#pragma once

#include "axi_lite_bfm.hpp"
#include <cstddef>
#include <cstdint>
#include <vector>

struct InputMatrix {
    std::size_t rows;
    std::size_t cols;
    std::vector<std::int8_t> data; // row-major; full hardware shape only
};

struct OutputMatrix {
    std::size_t rows;
    std::size_t cols;
    std::vector<std::int32_t> data; // signed INT18 values carried in int32_t
};

struct HardwareConfig {
    std::uint32_t n, k, data_w, acc_w;
};

struct InvocationCycles {
    std::uint64_t preflight = 0;
    std::uint64_t load = 0;       // A/B writes AND INPUTS_READY verification
    std::uint64_t start_poll = 0; // START transaction + polling; NOT core latency
    std::uint64_t readback = 0;
    std::uint64_t ack = 0;
    std::uint64_t total = 0;
    std::uint64_t poll_reads = 0;
};

struct MatmulResult {
    OutputMatrix c;
    InvocationCycles cycles;
};

// Exclusive, blocking owner of one accelerator. Reset BFM before construction.
// No implicit reset, ACK, error clearing, padding, or task retry.
// Operational failures leave device state intact for diagnosis. The caller
// must explicitly recover/reset before retrying; the sample program terminates.
// Cached capabilities are read once; that setup cost is outside invocation stats.
class MatmulRuntime {
public:
    explicit MatmulRuntime(AxiLiteBfm& bfm, std::uint64_t poll_timeout_cycles = 100000);
    const HardwareConfig& config() const noexcept { return config_; }
    MatmulResult matmul(const InputMatrix& a, const InputMatrix& b);

private:
    AxiLiteBfm& bfm_;
    HardwareConfig config_{};
    std::uint64_t poll_timeout_cycles_;
    static void validate_matrix(const InputMatrix& matrix, std::size_t rows,
                                std::size_t cols, const char* name);
    void check_device_error(std::uint32_t status);
};
