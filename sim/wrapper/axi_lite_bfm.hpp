#pragma once

#include <cstdint>

class Vsystolic_axi_lite_top;

// Snapshot of the signals sampled at a rising edge, BEFORE sequential updates.
struct CycleSample {
    bool aw_fire = false;
    bool w_fire = false;
    bool b_fire = false;
    bool ar_fire = false;
    bool r_fire = false;
    std::uint8_t bresp = 0;
    std::uint8_t rresp = 0;
    std::uint32_t rdata = 0;
};

// Blocking, single-threaded AXI4-Lite master for the Verilated wrapper.
// One transaction at a time; AW/W are tracked independently. No matrix/CSR
// knowledge here. Call reset() before the first access. The DUT must outlive BFM.
// BFM exclusively owns the clock and master-side pins while it is in use.
class AxiLiteBfm {
public:
    explicit AxiLiteBfm(Vsystolic_axi_lite_top& dut,
                        std::uint64_t timeout_cycles = 1000);
    AxiLiteBfm(const AxiLiteBfm&) = delete;
    AxiLiteBfm& operator=(const AxiLiteBfm&) = delete;

    // Three synchronous reset edges, followed by one released idle edge.
    // Cycle count is monotonic across resets and includes reset cycles.
    void reset();
    void axi_write(std::uint32_t addr, std::uint32_t data,
                   std::uint8_t strb = 0xF);
    std::uint32_t axi_read(std::uint32_t addr);
    std::uint64_t cycles() const noexcept { return cycles_; }

private:
    Vsystolic_axi_lite_top& dut_;
    std::uint64_t cycles_ = 0;
    std::uint64_t timeout_cycles_;
    bool initialized_ = false;
    bool timed_out_ = false;

    CycleSample tick();
    void idle_master();
    void require_usable() const;
    void check_timeout(std::uint64_t begin, const char* phase, std::uint32_t addr);
    static void check_response(std::uint8_t resp, const char* channel,
                               std::uint32_t addr);
};
