#include "axi_lite_bfm.hpp"
#include "Vsystolic_axi_lite_top.h"
#include "Vsystolic_axi_lite_top___024root.h"
#include "verilated.h"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

// AXI-Lite reference for the transport comparison. Timing boundaries and
// matrices match the Burst benchmark so differences reflect the interface
// transaction schedule rather than Core work or golden-model changes.
namespace {
constexpr std::uint32_t STATUS=0x0008, COMMAND=0x0004, ACK=0x000c;
constexpr std::uint32_t A_BASE=0x1000, B_BASE=0x2000, C_BASE=0x3000;
std::uint32_t prng(std::uint32_t& s) { s^=s<<13; s^=s>>17; s^=s<<5; return s; }
std::int32_t sx18(std::uint32_t v) { v&=0x3ffff; return v&0x20000 ? std::int32_t(v)-0x40000 : std::int32_t(v); }
std::int64_t golden(const std::vector<std::uint32_t>& a,const std::vector<std::uint32_t>& b,
                    unsigned n,unsigned k,unsigned i,unsigned j) {
    std::int64_t sum=0;
    auto sx8=[](std::uint32_t v){ return std::int64_t(std::int8_t(v)); };
    for (unsigned x=0;x<k;++x) sum+=sx8(a[i*k+x])*sx8(b[x*n+j]);
    return ((sum+131072)%262144+262144)%262144-131072;
}
}

int main(int argc,char** argv) {
    VerilatedContext context; context.commandArgs(argc,argv);
    Vsystolic_axi_lite_top d{&context}; AxiLiteBfm b{d,100000}; b.reset();
    const unsigned n=2,k=17,words=n*k;
    std::vector<std::uint32_t> a(words),bb(words);
    for (unsigned x=0;x<words;++x) { a[x]=std::uint8_t(int(x%11)-5); bb[x]=std::uint8_t(int((x*3)%13)-6); }
    std::uint64_t start_edge=0,done_edge=0;
    b.set_cycle_observer([&](std::uint64_t c){
        if (d.rootp->systolic_axi_lite_top__DOT__core_start) start_edge=c;
        if (d.rootp->systolic_axi_lite_top__DOT__core_done) done_edge=c;
    });
    const auto first=b.cycles();
    auto phase=b.cycles(); for(unsigned x=0;x<words;++x) b.axi_write(A_BASE+4*x,a[x],1); const auto load_a=b.cycles()-phase;
    phase=b.cycles(); for(unsigned x=0;x<words;++x) b.axi_write(B_BASE+4*x,bb[x],1); const auto load_b=b.cycles()-phase;
    phase=b.cycles(); if (b.axi_read(STATUS)!=4) throw std::runtime_error("inputs not ready"); const auto ready=b.cycles()-phase;
    const auto load=b.cycles()-first;
    phase=b.cycles(); b.axi_write(COMMAND,1,1); const auto start_access=b.cycles()-phase;
    phase=b.cycles(); unsigned polls=0; while(!(b.axi_read(STATUS)&2)) ++polls; ++polls; const auto done_poll=b.cycles()-phase;
    phase=b.cycles();
    for(unsigned i=0;i<n;++i) for(unsigned j=0;j<n;++j)
        if (sx18(b.axi_read(C_BASE+4*(i*n+j)))!=golden(a,bb,n,k,i,j)) throw std::runtime_error("golden mismatch");
    const auto readback=b.cycles()-phase, end_to_end=b.cycles()-first;
    phase=b.cycles(); b.axi_write(ACK,1,1); const auto ack=b.cycles()-phase, repeat=b.cycles()-first;
    if (!start_edge || !done_edge || done_edge<=start_edge) throw std::runtime_error("missing core event");

    std::ofstream csv("performance.csv");
    csv << "config,load_a,load_b,ready_check,total_load,start_access,core_start_cycle,core_done_cycle,compute_cycles,done_poll,poll_reads,readback,ack,end_to_end,repeat,write_transactions,write_beats,read_transactions,input_useful_B_per_cycle,input_slot_B_per_cycle,total_useful_B_per_cycle,total_slot_B_per_cycle,burst_lengths\n";
    csv << "AXI_LITE,"<<load_a<<','<<load_b<<','<<ready<<','<<load<<','<<start_access<<','<<start_edge<<','<<done_edge<<','<<(done_edge-start_edge)<<','<<done_poll<<','<<polls<<','<<readback<<','<<ack<<','<<end_to_end<<','<<repeat<<",70,70,"<<(1+polls+n*n)<<','<<(68.0/load)<<','<<(272.0/load)<<','<<(77.0/end_to_end)<<','<<(288.0/end_to_end)<<",1x68\n";

    // Fixed-seed response backpressure robustness run; it is not a performance row.
    b.reset(); std::uint32_t seed=0x5a17c0de;
    for(unsigned x=0;x<words;++x) b.axi_write(A_BASE+4*x,a[x],1,prng(seed)%4);
    for(unsigned x=0;x<words;++x) b.axi_write(B_BASE+4*x,bb[x],1,prng(seed)%4);
    if (b.axi_read(STATUS,prng(seed)%4)!=4) throw std::runtime_error("backpressure ready mismatch");
    b.axi_write(COMMAND,1,1,prng(seed)%4);
    while(!(b.axi_read(STATUS,prng(seed)%4)&2)) {}
    for(unsigned i=0;i<n;++i) for(unsigned j=0;j<n;++j)
        if (sx18(b.axi_read(C_BASE+4*(i*n+j),prng(seed)%4))!=golden(a,bb,n,k,i,j)) throw std::runtime_error("backpressure golden mismatch");
    b.axi_write(ACK,1,1,prng(seed)%4);
    std::ofstream bp("backpressure.csv"); bp << "config,seed,result\nAXI_LITE,0x5a17c0de,PASS\n";
    std::cout << "PASS AXI-Lite controlled transport and fixed-seed backpressure\n";
    d.final(); return 0;
}
