#include "axi_lite_bfm.hpp"
#include "matmul_runtime.hpp"
#include "Vsystolic_axi_lite_top.h"
#include "verilated.h"

#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>

// BFM smoke checks followed by two real end-to-end accelerator invocations.
int main(int argc, char** argv) {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    Vsystolic_axi_lite_top dut{&context};
    try {
        AxiLiteBfm bfm{dut};
        unsigned checks = 0;
        auto check = [&](bool condition, const char* description) {
            ++checks;
            if (!condition) throw std::runtime_error(description);
        };
        constexpr std::uint32_t STATUS = 0x0008;
        constexpr std::uint32_t ERROR_STATUS = 0x0010;
        constexpr std::uint32_t A_BASE = 0x1000;
        bfm.reset();
        const auto n = bfm.axi_read(0x0020);
        const auto k = bfm.axi_read(0x0024);
        check(n > 0 && k > 0, "invalid hardware shape");
        check(bfm.axi_read(0x0028) == 8, "expected INT8 input");
        check(bfm.axi_read(0x002c) == 18, "expected INT18 result");
        check(bfm.axi_read(STATUS) == 0, "reset STATUS must be zero");
        check(bfm.axi_read(A_BASE) == 0, "unwritten A must read zero");

        const auto begin = bfm.cycles();
        bfm.axi_write(A_BASE, 0x7F);
        const auto write_cycles = bfm.cycles() - begin;
        check(bfm.axi_read(A_BASE) == 127, "positive A readback mismatch");
        bfm.axi_write(A_BASE, 0x80, 0xE);
        check(bfm.axi_read(A_BASE) == 127, "upper strobes changed INT8 element");
        bfm.axi_write(A_BASE, 0x80, 0x1);
        check(bfm.axi_read(A_BASE) == 0xFFFF'FF80u, "INT8 sign extension mismatch");
        bfm.axi_write(A_BASE, 0);
        check(bfm.axi_read(A_BASE) == 0, "zero A readback mismatch");
        check(bfm.axi_read(STATUS) == 0, "one A entry cannot complete A/B load");

        // Device error response is consumed before the exception, so the next
        // transaction is legal. A timeout is different: it requires reset.
        bool read_error = false;
        try { (void)bfm.axi_read(0x0040); }
        catch (const std::runtime_error& e) {
            read_error = std::string(e.what()).find("RRESP error") != std::string::npos;
            if (!read_error) throw;
        }
        check(read_error, "invalid read did not report RRESP error");
        bool write_error = false;
        try { bfm.axi_write(STATUS, 1); }
        catch (const std::runtime_error& e) {
            write_error = std::string(e.what()).find("BRESP error") != std::string::npos;
            if (!write_error) throw;
        }
        check(write_error, "read-only write did not report BRESP error");
        check(bfm.axi_read(ERROR_STATUS) == 0x44, "sticky read/write errors mismatch");
        bfm.axi_write(ERROR_STATUS, 0xFF);
        check(bfm.axi_read(ERROR_STATUS) == 0, "W1C failed");

        const auto before_reset = bfm.cycles();
        bfm.reset();
        check(bfm.cycles() == before_reset + 4, "reset cycle accounting mismatch");
        check(bfm.axi_read(STATUS) == 0, "reset did not clear state/maps");
        check(bfm.axi_read(A_BASE) == 0, "reset input visibility mismatch");
        std::cout << "PASS AXI-Lite C++ BFM: " << checks << " checks, HW_N=" << n
                  << " HW_K=" << k << ", write_cycles=" << write_cycles
                  << ", total_cycles=" << bfm.cycles() << '\n';

        MatmulRuntime runtime{bfm};
        InputMatrix a{n, k, std::vector<std::int8_t>(std::size_t{n}*k)};
        InputMatrix b{k, n, std::vector<std::int8_t>(std::size_t{k}*n)};
        // A wrong shape must fail before touching the device.
        auto invalid = a;
        invalid.cols = k + 1;
        const auto before_invalid = bfm.cycles();
        bool rejected = false;
        try { (void)runtime.matmul(invalid, b); }
        catch (const std::invalid_argument&) { rejected = true; }
        check(rejected && bfm.cycles() == before_invalid,
              "invalid shape touched hardware or was accepted");

        for (unsigned operation = 0; operation < 2; ++operation) {
            for (std::size_t i = 0; i < n; ++i)
                for (std::size_t x = 0; x < k; ++x)
                    a.data[i*k+x] = static_cast<std::int8_t>(operation == 0
                        ? static_cast<int>((i+2*x)%11)-5
                        : ((i+x)%2 == 0 ? -128 : 127));
            for (std::size_t x = 0; x < k; ++x)
                for (std::size_t j = 0; j < n; ++j)
                    b.data[x*n+j] = static_cast<std::int8_t>(operation == 0
                        ? static_cast<int>((3*x+j)%13)-6
                        : ((x+j)%2 == 0 ? -128 : 127));
            const auto output = runtime.matmul(a, b);
            check(output.c.rows == n && output.c.cols == n && output.c.data.size() == n*n,
                  "output shape mismatch");
            for (std::size_t i = 0; i < n; ++i)
                for (std::size_t j = 0; j < n; ++j) {
                    // Independent mathematical dot product + signed modulo.
                    // Modulo at the end equals wrapping each INT18 accumulation.
                    std::int64_t sum = 0;
                    for (std::size_t x = 0; x < k; ++x)
                        sum += std::int64_t{a.data[i*k+x]} * b.data[x*n+j];
                    constexpr std::int64_t modulus = 262144;
                    auto expected = ((sum + 131072) % modulus + modulus) % modulus - 131072;
                    check(output.c.data[i*n+j] == expected, "matrix result mismatch");
                }
            const auto& t = output.cycles;
            check(t.total == t.preflight+t.load+t.start_poll+t.readback+t.ack,
                  "invocation phases do not sum to total");
            check(t.poll_reads > 0, "no completion poll performed");
            check(bfm.axi_read(STATUS) == 0, "ACK did not release result/invalidate inputs");
            check(bfm.axi_read(ERROR_STATUS) == 0, "unexpected end-to-end error");
            std::cout << "PASS matmul operation=" << operation
                      << " preflight=" << t.preflight << " load=" << t.load
                      << " start_poll=" << t.start_poll << " readback=" << t.readback
                      << " ack=" << t.ack << " total=" << t.total
                      << " polls=" << t.poll_reads << '\n';
        }
        std::cout << "PASS Runtime end-to-end: " << checks << " cumulative checks\n";
        dut.final();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL AXI-Lite C++ BFM: " << e.what() << '\n';
        dut.final();
        return 1;
    }
}
