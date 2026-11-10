#pragma once
#include <cstdint>
#include <functional>
#include <utility>
#include <vector>

class Vsystolic_axi_burst_top;

struct BurstSample {
    bool law, lw, lb, lar, lr, baw, bw, bb;
    bool wvalid, wready;
    std::uint8_t lbre, lrre, bbre;
    std::uint32_t rdata;
};
struct BurstMetrics {
    // Absolute cycle of the last accepted data beat (before B response).
    std::uint64_t last_transfer_cycle=0;
    std::uint64_t cycles=0, transfer=0, master_only=0, slave_only=0, both=0;
    std::uint64_t data_cycles() const { return transfer+master_only+slave_only+both; }
};

// One shared clock/context for BOTH ports. Never instantiate two independently
// clocking BFMs on this DUT. Blocking methods consume one complete response.
// step() is exposed for directed simultaneous-port tests; caller must keep
// stalled VALID/payload stable and must not interleave another clock driver.
class AxiBurstBfm {
public:
    explicit AxiBurstBfm(Vsystolic_axi_burst_top& dut, std::uint64_t timeout=10000);
    AxiBurstBfm(const AxiBurstBfm&)=delete;
    AxiBurstBfm& operator=(const AxiBurstBfm&)=delete;
    void reset();
    std::uint64_t cycles() const { return cycles_; }
    BurstSample step();
    void axi_write(std::uint32_t addr, std::uint32_t data, std::uint8_t strb=1,
                   unsigned response_hold=0);
    std::uint32_t axi_read(std::uint32_t addr, unsigned response_hold=0);
    BurstMetrics burst_write(std::uint32_t addr, const std::vector<std::uint32_t>& words,
                             unsigned master_gap=0, unsigned response_hold=0,
                             const std::vector<std::uint8_t>& strobes={});
    void set_cycle_observer(std::function<void(std::uint64_t)> observer) {
        observer_ = std::move(observer);
    }
private:
    Vsystolic_axi_burst_top& d_;
    std::uint64_t cycles_=0, timeout_;
    bool usable_=false;
    std::function<void(std::uint64_t)> observer_;
    void require_usable() const;
    void deadline(std::uint64_t begin, const char* phase);
    static void response(std::uint8_t value, const char* channel);
};
