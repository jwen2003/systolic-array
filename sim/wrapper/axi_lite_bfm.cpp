#include "axi_lite_bfm.hpp"
#include "Vsystolic_axi_lite_top.h"
#include "verilated.h"

#include <iomanip>
#include <sstream>
#include <stdexcept>

AxiLiteBfm::AxiLiteBfm(Vsystolic_axi_lite_top& dut,
                       std::uint64_t timeout_cycles)
    : dut_(dut), timeout_cycles_(timeout_cycles) {
    if (timeout_cycles_ == 0)
        throw std::invalid_argument("BFM timeout must be nonzero");
    dut_.clk = 0;
    dut_.rst_n = 0;
    idle_master();
}

void AxiLiteBfm::idle_master() {
    dut_.s_axi_awaddr = 0;
    dut_.s_axi_awprot = 0;
    dut_.s_axi_awvalid = 0;
    dut_.s_axi_wdata = 0;
    dut_.s_axi_wstrb = 0;
    dut_.s_axi_wvalid = 0;
    dut_.s_axi_bready = 0;
    dut_.s_axi_araddr = 0;
    dut_.s_axi_arprot = 0;
    dut_.s_axi_arvalid = 0;
    dut_.s_axi_rready = 0;
}

CycleSample AxiLiteBfm::tick() {
    // Settle combinational READY/data BEFORE sampling the next edge.
    dut_.clk = 0;
    dut_.eval();
    CycleSample s;
    s.aw_fire = dut_.s_axi_awvalid && dut_.s_axi_awready;
    s.w_fire  = dut_.s_axi_wvalid && dut_.s_axi_wready;
    s.b_fire  = dut_.s_axi_bvalid && dut_.s_axi_bready;
    s.ar_fire = dut_.s_axi_arvalid && dut_.s_axi_arready;
    s.r_fire  = dut_.s_axi_rvalid && dut_.s_axi_rready;
    s.bresp = dut_.s_axi_bresp;
    s.rresp = dut_.s_axi_rresp;
    s.rdata = dut_.s_axi_rdata;

    // Each half cycle advances one Verilator time-precision unit. Performance
    // measurements use cycles(), not these arbitrary units or host wall time.
    dut_.contextp()->timeInc(1);
    dut_.clk = 1;
    dut_.eval();
    dut_.contextp()->timeInc(1);
    dut_.clk = 0;
    dut_.eval();
    ++cycles_;
    return s;
}

void AxiLiteBfm::reset() {
    initialized_ = false;
    idle_master();
    dut_.rst_n = 0;
    for (unsigned i = 0; i < 3; ++i) (void)tick();
    dut_.rst_n = 1;
    (void)tick();
    timed_out_ = false;
    initialized_ = true;
}

void AxiLiteBfm::require_usable() const {
    if (!initialized_ || timed_out_)
        throw std::logic_error("BFM requires reset before access (or after timeout)");
}

void AxiLiteBfm::check_timeout(std::uint64_t begin, const char* phase,
                              std::uint32_t addr) {
    if (cycles_ - begin < timeout_cycles_) return;
    // Do not silently withdraw an unaccepted VALID or attempt another request.
    // Main terminates on this exception. Explicit shared reset is the only
    // supported recovery if a caller elects to catch it and continue.
    timed_out_ = true;
    std::ostringstream message;
    message << "AXI timeout waiting for " << phase << " at address 0x"
            << std::hex << addr << std::dec << " after " << cycles_ - begin
            << " cycles";
    throw std::runtime_error(message.str());
}

void AxiLiteBfm::check_response(std::uint8_t resp, const char* channel,
                               std::uint32_t addr) {
    if (resp == 0) return; // AXI OKAY
    std::ostringstream message;
    message << channel << " error at address 0x" << std::hex << addr
            << ": response=" << std::dec << static_cast<unsigned>(resp);
    throw std::runtime_error(message.str());
}

void AxiLiteBfm::axi_write(std::uint32_t addr, std::uint32_t data,
                          std::uint8_t strb) {
    require_usable();
    if (strb > 0xF) throw std::invalid_argument("WSTRB must fit four bits");
    const auto begin = cycles_;
    dut_.s_axi_awaddr = addr;
    dut_.s_axi_wdata = data;
    dut_.s_axi_wstrb = strb;
    dut_.s_axi_bready = 0;
    bool aw_done = false;
    bool w_done = false;
    while (!aw_done || !w_done) {
        check_timeout(begin, "AW/W handshake", addr);
        dut_.s_axi_awvalid = !aw_done;
        dut_.s_axi_wvalid = !w_done;
        const auto s = tick();
        aw_done = aw_done || s.aw_fire;
        w_done = w_done || s.w_fire;
    }
    dut_.s_axi_awvalid = 0;
    dut_.s_axi_wvalid = 0;
    dut_.s_axi_bready = 1;
    while (true) {
        check_timeout(begin, "B response", addr);
        const auto s = tick();
        if (s.b_fire) {
            dut_.s_axi_bready = 0;
            check_response(s.bresp, "BRESP", addr);
            return;
        }
    }
}

std::uint32_t AxiLiteBfm::axi_read(std::uint32_t addr) {
    require_usable();
    const auto begin = cycles_;
    dut_.s_axi_araddr = addr;
    dut_.s_axi_arvalid = 1;
    dut_.s_axi_rready = 0;
    while (true) {
        check_timeout(begin, "AR handshake", addr);
        if (tick().ar_fire) break;
    }
    dut_.s_axi_arvalid = 0;
    dut_.s_axi_rready = 1;
    while (true) {
        check_timeout(begin, "R response", addr);
        const auto s = tick();
        if (s.r_fire) {
            dut_.s_axi_rready = 0;
            check_response(s.rresp, "RRESP", addr);
            return s.rdata;
        }
    }
}
