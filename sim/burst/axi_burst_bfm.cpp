#include "axi_burst_bfm.hpp"
#include "Vsystolic_axi_burst_top.h"
#include "verilated.h"
#include <stdexcept>
#include <string>

AxiBurstBfm::AxiBurstBfm(Vsystolic_axi_burst_top& d, std::uint64_t timeout)
    : d_(d), timeout_(timeout) {
    if (!timeout) throw std::invalid_argument("nonzero BFM timeout required");
}
BurstSample AxiBurstBfm::step() {
    // Sample combinational handshakes while clock is low, then execute the
    // corresponding rising edge. Returned fields describe what that edge
    // accepted; the observer runs afterward and sees post-edge DUT state.
    d_.clk=0; d_.eval();
    BurstSample s{
        bool(d_.s_axi_awvalid && d_.s_axi_awready),
        bool(d_.s_axi_wvalid && d_.s_axi_wready),
        bool(d_.s_axi_bvalid && d_.s_axi_bready),
        bool(d_.s_axi_arvalid && d_.s_axi_arready),
        bool(d_.s_axi_rvalid && d_.s_axi_rready),
        bool(d_.s_burst_awvalid && d_.s_burst_awready),
        bool(d_.s_burst_wvalid && d_.s_burst_wready),
        bool(d_.s_burst_bvalid && d_.s_burst_bready),
        bool(d_.s_burst_wvalid), bool(d_.s_burst_wready),
        d_.s_axi_bresp, d_.s_axi_rresp, d_.s_burst_bresp, d_.s_axi_rdata};
    d_.contextp()->timeInc(1); d_.clk=1; d_.eval();
    d_.contextp()->timeInc(1); d_.clk=0; d_.eval();
    ++cycles_;
    if (observer_) observer_(cycles_);
    return s;
}
void AxiBurstBfm::reset() {
    // reset() is the sole recovery boundary after timeout: withdrawing VALID
    // from an outstanding AXI request would violate the protocol contract.
    usable_=false;
    d_.clk=0; d_.rst_n=0;
    d_.s_axi_awaddr=0; d_.s_axi_awprot=0; d_.s_axi_awvalid=0;
    d_.s_axi_wdata=0; d_.s_axi_wstrb=0; d_.s_axi_wvalid=0; d_.s_axi_bready=0;
    d_.s_axi_araddr=0; d_.s_axi_arprot=0; d_.s_axi_arvalid=0; d_.s_axi_rready=0;
    d_.s_burst_awaddr=0; d_.s_burst_awlen=0; d_.s_burst_awsize=2;
    d_.s_burst_awburst=1; d_.s_burst_awvalid=0;
    d_.s_burst_wdata=0; d_.s_burst_wstrb=1; d_.s_burst_wlast=0;
    d_.s_burst_wvalid=0; d_.s_burst_bready=0;
    for (unsigned i=0;i<3;++i) step();
    d_.rst_n=1; step(); usable_=true;
}
void AxiBurstBfm::require_usable() const {
    if (!usable_) throw std::logic_error("BFM reset required before access/after timeout");
}
void AxiBurstBfm::deadline(std::uint64_t begin, const char* phase) {
    if (cycles_-begin<timeout_) return;
    usable_=false; // Do not withdraw an outstanding request; reset to recover.
    throw std::runtime_error(std::string("BFM timeout: ")+phase);
}
void AxiBurstBfm::response(std::uint8_t value, const char* channel) {
    if (value) throw std::runtime_error(std::string(channel)+" response="+std::to_string(value));
}
void AxiBurstBfm::axi_write(std::uint32_t addr, std::uint32_t data, std::uint8_t strb,
                            unsigned response_hold) {
    require_usable();
    if (strb>15) throw std::invalid_argument("WSTRB must fit four bits");
    const auto begin=cycles_;
    d_.s_axi_awaddr=addr; d_.s_axi_wdata=data; d_.s_axi_wstrb=strb;
    d_.s_axi_bready=0;
    bool aw=false,w=false;
    while (!aw || !w) {
        // AW and W are independent. Once either handshakes its VALID drops on
        // the next iteration while the other channel remains stable/asserted.
        deadline(begin,"Lite AW/W");
        d_.s_axi_awvalid=!aw; d_.s_axi_wvalid=!w;
        const auto s=step(); aw=aw || s.law; w=w || s.lw;
    }
    d_.s_axi_awvalid=0; d_.s_axi_wvalid=0; d_.s_axi_bready=1;
    for (unsigned i=0;i<response_hold;++i) {
        d_.s_axi_bready=0; deadline(begin,"Held Lite B"); step();
        if (!d_.s_axi_bvalid) throw std::runtime_error("Lite BVALID lost under backpressure");
    }
    d_.s_axi_bready=1;
    while (true) {
        deadline(begin,"Lite B"); const auto s=step();
        if (s.lb) { d_.s_axi_bready=0; response(s.lbre,"Lite B"); return; }
    }
}
std::uint32_t AxiBurstBfm::axi_read(std::uint32_t addr, unsigned response_hold) {
    require_usable(); const auto begin=cycles_;
    d_.s_axi_araddr=addr; d_.s_axi_arvalid=1; d_.s_axi_rready=0;
    while (true) { deadline(begin,"Lite AR"); if (step().lar) break; }
    d_.s_axi_arvalid=0;
    for (unsigned i=0;i<response_hold;++i) {
        d_.s_axi_rready=0; deadline(begin,"Held Lite R"); step();
        if (!d_.s_axi_rvalid) throw std::runtime_error("Lite RVALID lost under backpressure");
    }
    d_.s_axi_rready=1;
    while (true) {
        deadline(begin,"Lite R"); const auto s=step();
        if (s.lr) { d_.s_axi_rready=0; response(s.lrre,"Lite R"); return s.rdata; }
    }
}
BurstMetrics AxiBurstBfm::burst_write(std::uint32_t addr,
    const std::vector<std::uint32_t>& words, unsigned master_gap, unsigned response_hold,
    const std::vector<std::uint8_t>& strobes) {
    require_usable();
    if (words.empty() || words.size()>16 || (addr & 3u))
        throw std::invalid_argument("Burst requires 1..16 aligned words");
    if (!strobes.empty() && strobes.size()!=words.size())
        throw std::invalid_argument("one strobe required per beat");
    for (auto strobe : strobes) if (strobe>15)
        throw std::invalid_argument("WSTRB must fit four bits");
    const auto begin=cycles_;
    d_.s_burst_awaddr=addr;
    d_.s_burst_awlen=static_cast<std::uint8_t>(words.size()-1);
    d_.s_burst_awsize=2; d_.s_burst_awburst=1;
    d_.s_burst_awvalid=1; d_.s_burst_bready=0;
    while (true) { deadline(begin,"Burst AW"); if (step().baw) break; }
    d_.s_burst_awvalid=0;
    BurstMetrics m;
    // No extra cycle between AW acceptance and the first W attempt.
    for (std::size_t x=0;x<words.size();++x) {
        // master_gap is an intentional post-handshake stimulus gap used by the
        // legacy sensitivity test. It is not an upstream readiness schedule.
        if (x) for (unsigned gap=0;gap<master_gap;++gap) {
            d_.s_burst_wvalid=0;
            deadline(begin,"Master data gap"); const auto s=step();
            if (s.wready) ++m.master_only; else ++m.both;
        }
        d_.s_burst_wdata=words[x]; d_.s_burst_wstrb=strobes.empty() ? 1 : strobes[x];
        d_.s_burst_wlast=x+1==words.size(); d_.s_burst_wvalid=1;
        while (true) {
            deadline(begin,"Burst W"); const auto s=step();
            if (s.bw) { ++m.transfer; m.last_transfer_cycle=cycles_; break; }
            ++m.slave_only; // VALID and payload remain asserted and stable.
        }
    }
    d_.s_burst_wvalid=0;
    for (unsigned i=0;i<response_hold;++i) {
        deadline(begin,"Held B"); step();
        if (!d_.s_burst_bvalid) throw std::runtime_error("Burst B response disappeared");
    }
    d_.s_burst_bready=1;
    while (true) {
        deadline(begin,"Burst B"); const auto s=step();
        if (s.bb) {
            d_.s_burst_bready=0; m.cycles=cycles_-begin;
            response(s.bbre,"Burst B"); return m;
        }
    }
}
