#include "axi_burst_bfm.hpp"
#include "Vsystolic_axi_burst_top.h"
#include "Vsystolic_axi_burst_top___024root.h"
#include "verilated.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr std::uint32_t STATUS=0x0008, COMMAND=0x0004, ACK=0x000c;
constexpr std::uint32_t A_BASE=0x1000, B_BASE=0x2000, C_BASE=0x3000;
std::uint32_t prng(std::uint32_t& s) { s^=s<<13; s^=s>>17; s^=s<<5; return s; }
std::int32_t sx18(std::uint32_t v) { v&=0x3ffff; return v&0x20000 ? std::int32_t(v)-0x40000 : std::int32_t(v); }
std::int64_t golden(const std::vector<std::uint32_t>& a,const std::vector<std::uint32_t>& b,unsigned n,unsigned k,unsigned i,unsigned j) {
    std::int64_t sum=0; auto sx8=[](std::uint32_t v){ return std::int64_t(std::int8_t(v)); };
    for(unsigned x=0;x<k;++x) sum+=sx8(a[i*k+x])*sx8(b[x*n+j]);
    return ((sum+131072)%262144+262144)%262144-131072;
}
struct Result { std::string name,lengths; unsigned max_length; std::uint64_t la,lb,ready,load,start,start_edge,done_edge,poll,polls,readback,ack,e2e,repeat,tx,beats; };
Result run(AxiBurstBfm& b,Vsystolic_axi_burst_top& d,unsigned length,const std::vector<std::uint32_t>& a,const std::vector<std::uint32_t>& bb,
           bool reset_before,std::ofstream& events,unsigned repetition) {
    const unsigned n=2,k=17,words=n*k; b.set_cycle_observer({});
    if(reset_before) b.reset(); else if(b.axi_read(STATUS)!=0) throw std::runtime_error("ACK did not restore LOAD state");
    std::uint64_t se=0,de=0;
    b.set_cycle_observer([&](std::uint64_t c){ if(d.rootp->systolic_axi_burst_top__DOT__core_start) se=c; if(d.rootp->systolic_axi_burst_top__DOT__core_done) de=c; });
    Result r; r.name="BURST_L"+std::to_string(length); r.max_length=length; r.tx=0; r.beats=0;
    const auto first=b.cycles(); auto phase=b.cycles();
    auto load_words=[&](const char* matrix,std::uint32_t base,const std::vector<std::uint32_t>& v){
        for(unsigned x=0;x<v.size();x+=length) { const auto stop=std::min<unsigned>(x+length,v.size());
            const auto begin=b.cycles();
            const auto m=b.burst_write(base+4*x,std::vector<std::uint32_t>(v.begin()+x,v.begin()+stop));
            events<<length<<','<<repetition<<','<<matrix<<','<<r.tx<<",0x"<<std::hex<<(base+4*x)<<std::dec<<','<<(stop-x)<<','<<(stop-x-1)<<','<<(begin+1)<<','<<(begin+2)<<','<<m.last_transfer_cycle<<','<<b.cycles()<<",OKAY\n";
            ++r.tx; r.beats+=stop-x;
            if(!r.lengths.empty()) r.lengths+=';'; r.lengths+=std::to_string(stop-x); }
    };
    load_words("A",A_BASE,a); r.la=b.cycles()-phase; phase=b.cycles(); load_words("B",B_BASE,bb); r.lb=b.cycles()-phase;
    phase=b.cycles(); if(b.axi_read(STATUS)!=4) throw std::runtime_error("inputs not ready"); r.ready=b.cycles()-phase; r.load=b.cycles()-first;
    phase=b.cycles(); b.axi_write(COMMAND,1,1); r.start=b.cycles()-phase;
    phase=b.cycles(); r.polls=0; do { ++r.polls; } while(!(b.axi_read(STATUS)&2)); r.poll=b.cycles()-phase;
    phase=b.cycles(); for(unsigned i=0;i<n;++i) for(unsigned j=0;j<n;++j)
        if(sx18(b.axi_read(C_BASE+4*(i*n+j)))!=golden(a,bb,n,k,i,j)) throw std::runtime_error("golden mismatch");
    r.readback=b.cycles()-phase; r.e2e=b.cycles()-first; phase=b.cycles(); b.axi_write(ACK,1,1); r.ack=b.cycles()-phase; r.repeat=b.cycles()-first;
    r.start_edge=se; r.done_edge=de; if(!se||!de||de<=se) throw std::runtime_error("missing core event");
    b.set_cycle_observer({}); return r;
}
}
int main(int argc,char** argv) {
    VerilatedContext context; context.commandArgs(argc,argv); Vsystolic_axi_burst_top d{&context}; AxiBurstBfm b{d};
    const unsigned words=34; std::vector<std::uint32_t> a(words),bb(words);
    for(unsigned x=0;x<words;++x){a[x]=std::uint8_t(int(x%11)-5);bb[x]=std::uint8_t(int((x*3)%13)-6);}
    std::ofstream events("handshake_events.csv");
    events<<"max_length,repetition,matrix,transaction_index,address,beats,AxLEN,aw_cycle,first_w_cycle,last_w_cycle,b_cycle,response\n";
    std::vector<Result> results;
    for(unsigned length:{1u,2u,4u,8u,16u}) {
        results.push_back(run(b,d,length,a,bb,true,events,0));
        (void)run(b,d,length,a,bb,false,events,1); // ACK/reload without reset.
    }
    std::ofstream csv("performance.csv");
    csv << "config,load_a,load_b,ready_check,total_load,start_access,core_start_cycle,core_done_cycle,compute_cycles,done_poll,poll_reads,readback,ack,end_to_end,repeat,write_transactions,write_beats,read_transactions,input_useful_B_per_cycle,input_slot_B_per_cycle,total_useful_B_per_cycle,total_slot_B_per_cycle,burst_lengths\n";
    for(const auto& r:results) csv<<r.name<<','<<r.la<<','<<r.lb<<','<<r.ready<<','<<r.load<<','<<r.start<<','<<r.start_edge<<','<<r.done_edge<<','<<(r.done_edge-r.start_edge)<<','<<r.poll<<','<<r.polls<<','<<r.readback<<','<<r.ack<<','<<r.e2e<<','<<r.repeat<<','<<(r.tx+2)<<','<<r.beats+2<<','<<(1+r.polls+4)<<','<<(68.0/r.load)<<','<<(272.0/r.load)<<','<<(77.0/r.e2e)<<','<<(288.0/r.e2e)<<','<<r.lengths<<"\n";
    std::ofstream prediction("prediction_vs_measurement.csv");
    prediction<<"max_length,input_transactions,predicted_write_cycles,measured_write_cycles,measured_load_with_ready,delta\n";
    for(const auto& r:results) {
        const auto measured=r.la+r.lb, predicted=68+2*r.tx;
        prediction<<r.max_length<<','<<r.tx<<','<<predicted<<','<<measured<<','<<r.load<<','<<(std::int64_t(measured)-std::int64_t(predicted))<<"\n";
    }

    // Fixed-seed BREADY/RREADY backpressure; payload and protocol results must remain stable.
    std::ofstream bp("backpressure.csv"); bp<<"config,seed,result\n";
    for(unsigned length:{1u,2u,4u,8u,16u}) {
        b.reset(); std::uint32_t seed=0x5a17c0de;
        auto bp_load=[&](std::uint32_t base,const std::vector<std::uint32_t>& v){ for(unsigned x=0;x<v.size();x+=length){auto stop=std::min<unsigned>(x+length,v.size()); b.burst_write(base+4*x,std::vector<std::uint32_t>(v.begin()+x,v.begin()+stop),0,prng(seed)%4);} };
        bp_load(A_BASE,a); bp_load(B_BASE,bb); if(b.axi_read(STATUS,prng(seed)%4)!=4) throw std::runtime_error("backpressure ready mismatch");
        b.axi_write(COMMAND,1,1,prng(seed)%4); while(!(b.axi_read(STATUS,prng(seed)%4)&2)){}
        for(unsigned i=0;i<2;++i) for(unsigned j=0;j<2;++j) if(sx18(b.axi_read(C_BASE+4*(i*2+j),prng(seed)%4))!=golden(a,bb,2,17,i,j)) throw std::runtime_error("backpressure golden mismatch");
        b.axi_write(ACK,1,1,prng(seed)%4);
        bp<<"BURST_L"<<length<<",0x5a17c0de,PASS\n";
    }
    std::cout<<"PASS Burst single/multi transport and fixed-seed backpressure\n"; d.final(); return 0;
}
