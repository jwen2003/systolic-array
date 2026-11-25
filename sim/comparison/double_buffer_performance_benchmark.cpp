#include "verilated.h"
#ifdef C_BURST_READ
#include "Vsystolic_axi_dual_bank_burst_read_top.h"
#include "Vsystolic_axi_dual_bank_burst_read_top___024root.h"
using Dut = Vsystolic_axi_dual_bank_burst_read_top;
#elif defined(DUAL_BANK)
#include "Vsystolic_axi_dual_bank_top.h"
#include "Vsystolic_axi_dual_bank_top___024root.h"
using Dut = Vsystolic_axi_dual_bank_top;
#else
#include "Vsystolic_axi_burst_top.h"
#include "Vsystolic_axi_burst_top___024root.h"
using Dut = Vsystolic_axi_burst_top;
#endif

#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef BENCH_N
#define BENCH_N 2
#endif
#ifndef BENCH_K
#define BENCH_K 2
#endif

namespace {
constexpr unsigned N=BENCH_N,K=BENCH_K,OPS=20,MAX_BURST=16;
constexpr std::uint32_t COMMAND=4,STATUS=8,ACK=12,C_BASE=0x3000;
constexpr std::array<std::uint32_t,2> PA{0x4000,0x8000},PB{0x5000,0x9000};
enum class Phase {EMPTY,LOADING,READY,STARTING,RUNNING,READING,ACKING,COMPLETE};
struct Op {
    unsigned id=0,bank=0; Phase phase=Phase::EMPTY;
    std::uint64_t first_aw=0,first_commit=0,input_complete=0,start=0,busy=0,core_done=0,device_done=0;
    std::uint64_t host_done=0,first_result=0,last_result=0,ack=0;
    std::uint64_t overlap_busy=0,overlap_done=0,overlap_result=0;
    unsigned polls=0,results=0;
};
struct BurstTxn { unsigned op,bank; std::uint32_t addr; std::vector<std::uint32_t> data; std::vector<std::uint8_t> strb; };
struct ReadReq { unsigned op; std::uint32_t addr; bool status; unsigned result_index; };
struct WriteReq { unsigned op; std::uint32_t addr,data; bool start,ack; };
struct CReadTxn { unsigned op,first,count; std::uint32_t addr; };

std::int32_t sx8(std::uint32_t x){return std::int8_t(x&255);}
std::int32_t wrap18(std::int64_t x){std::uint32_t v=std::uint32_t(x)&0x3ffffu;return (v&0x20000)?std::int32_t(v)-0x40000:std::int32_t(v);}
std::vector<std::uint32_t> make_data(unsigned salt){
    std::vector<std::uint32_t> v(N*K);
    for(unsigned i=0;i<v.size();++i)v[i]=std::uint8_t(int((i*37+salt*17+11)%251)-125);
    return v;
}
std::vector<std::int32_t> golden(const std::vector<std::uint32_t>&a,const std::vector<std::uint32_t>&b){
    std::vector<std::int32_t> c(N*N);
    for(unsigned r=0;r<N;r++)for(unsigned col=0;col<N;col++){
        std::int64_t sum=0;for(unsigned k=0;k<K;k++)sum+=sx8(a[r*K+k])*sx8(b[k*N+col]);c[r*N+col]=wrap18(sum);
    }return c;
}
std::vector<BurstTxn> packed_txns(unsigned op,unsigned bank,std::uint32_t base,const std::vector<std::uint32_t>&v){
    std::vector<std::uint32_t> words;std::vector<std::uint8_t> strobes;
    for(unsigned p=0;p<v.size();p+=4){std::uint32_t w=0;std::uint8_t s=0;for(unsigned l=0;l<4&&p+l<v.size();l++){w|=(v[p+l]&255)<<(8*l);s|=1u<<l;}words.push_back(w);strobes.push_back(s);}
    std::vector<BurstTxn> out;
    for(unsigned p=0;p<words.size();p+=MAX_BURST){unsigned count=std::min<unsigned>(MAX_BURST,words.size()-p);
        out.push_back({op,bank,base+4*p,{words.begin()+p,words.begin()+p+count},{strobes.begin()+p,strobes.begin()+p+count}});
    }return out;
}

class Bench {
public:
    Bench(Dut& d,bool dual):d(d),dual(dual),ops(OPS){for(unsigned i=0;i<OPS;i++){ops[i].id=i;ops[i].bank=dual?(i&1):0;}}
    int run(){reset(); enqueue_load(0); for(unsigned guard=0;guard<20000000&&completed<OPS;guard++)step();
        if(completed!=OPS)throw std::runtime_error("benchmark timeout");write_outputs();return 0;}
private:
    Dut& d;bool dual;std::uint64_t cycle=0;std::vector<Op> ops;unsigned current=0,completed=0;
    std::vector<std::uint32_t>a=make_data(3),b=make_data(9);std::vector<std::int32_t>expect=golden(a,b);
    std::deque<BurstTxn>bq;std::deque<ReadReq>rq;std::deque<WriteReq>wq;
    std::deque<CReadTxn>cq;
    enum class BS{IDLE,AW,W,B}bs=BS::IDLE;BurstTxn bt{};unsigned bi=0;
    enum class RS{IDLE,AR,R}rs=RS::IDLE;ReadReq rr{};
    enum class WS{IDLE,SEND,B}ws=WS::IDLE;WriteReq ww{};bool waw=false,www=false;
#ifdef C_BURST_READ
    enum class CS{IDLE,AR,R}cs=CS::IDLE;CReadTxn ct{};unsigned ci=0;
    std::ofstream c_events{"c_burst_events.csv"};
#endif
    std::vector<std::array<bool,2>> seen{OPS};unsigned seen_count[OPS]{};
    std::ofstream events{"events.csv"};
    bool control_pending()const{return ws!=WS::IDLE||!wq.empty();}
    void event(unsigned op,const char*name,int bank=-1,std::uint32_t addr=0){events<<cycle<<','<<op<<','<<(bank<0?ops[op].bank:unsigned(bank))<<','<<name<<",0x"<<std::hex<<addr<<std::dec<<'\n';}
    void reset(){events<<"cycle,operation_id,bank,event,address\n";d.clk=0;d.rst_n=0;clear_ports();for(int i=0;i<3;i++)raw_step();d.rst_n=1;raw_step();}
    void clear_ports(){d.s_axi_awvalid=0;d.s_axi_wvalid=0;d.s_axi_bready=0;d.s_axi_arvalid=0;d.s_axi_rready=0;
        d.s_burst_awvalid=0;d.s_burst_wvalid=0;d.s_burst_bready=0;d.s_axi_awprot=0;d.s_axi_arprot=0;
        d.s_burst_awsize=2;d.s_burst_awburst=1;
#ifdef C_BURST_READ
        d.s_c_arvalid=0;d.s_c_rready=0;d.s_c_arsize=2;d.s_c_arburst=1;
        c_events<<"cycle,operation_id,event,address,burst_beats,beat_index\n";
#endif
    }
    void raw_step(){d.clk=0;d.eval();d.contextp()->timeInc(1);d.clk=1;d.eval();d.contextp()->timeInc(1);d.clk=0;d.eval();cycle++;}
    void enqueue_load(unsigned id){auto&op=ops[id];op.phase=Phase::LOADING;
        auto aa=packed_txns(id,op.bank,PA[op.bank],a),bb=packed_txns(id,op.bank,PB[op.bank],b);
        bq.insert(bq.end(),aa.begin(),aa.end());bq.insert(bq.end(),bb.begin(),bb.end());}
    void queue_start(unsigned id){if(ops[id].phase!=Phase::READY)return;ops[id].phase=Phase::STARTING;wq.push_back({id,COMMAND,dual?(1u<<ops[id].bank):1u,true,false});}
    void queue_ack(unsigned id){ops[id].phase=Phase::ACKING;wq.push_back({id,ACK,1,false,true});}
    void start_poll(unsigned id){if(rs==RS::IDLE&&rq.empty())rq.push_back({id,STATUS,true,0});}
    void start_results(unsigned id){ops[id].phase=Phase::READING;
#ifdef C_BURST_READ
        for(unsigned x=0;x<N*N;x+=MAX_BURST){unsigned count=std::min<unsigned>(MAX_BURST,N*N-x);cq.push_back({id,x,count,C_BASE+4*x});}
#else
        for(unsigned x=0;x<N*N;x++)rq.push_back({id,C_BASE+4*x,false,x});
#endif
    }
    void prepare(){
        if(bs==BS::IDLE&&!bq.empty()&&!control_pending()){bt=std::move(bq.front());bq.pop_front();bi=0;bs=BS::AW;if(!ops[bt.op].first_aw)ops[bt.op].first_aw=cycle+1;}
        if(ws==WS::IDLE&&!wq.empty()){ww=wq.front();wq.pop_front();waw=www=false;ws=WS::SEND;}
        if(rs==RS::IDLE&&!rq.empty()){rr=rq.front();rq.pop_front();rs=RS::AR;}
#ifdef C_BURST_READ
        if(cs==CS::IDLE&&!cq.empty()){ct=cq.front();cq.pop_front();ci=0;cs=CS::AR;}
#endif
        if(current<OPS&&ops[current].phase==Phase::READY&&ws==WS::IDLE&&wq.empty()&&(current==0||ops[current-1].phase==Phase::COMPLETE))queue_start(current);
        if(current<OPS&&ops[current].phase==Phase::RUNNING&&rs==RS::IDLE&&rq.empty())start_poll(current);
    }
    void drive(){
        d.s_burst_awvalid=bs==BS::AW;d.s_burst_awaddr=bt.addr;d.s_burst_awlen=bt.data.empty()?0:bt.data.size()-1;
        d.s_burst_wvalid=bs==BS::W;d.s_burst_wdata=bt.data.empty()?0:bt.data[bi];d.s_burst_wstrb=bt.strb.empty()?0:bt.strb[bi];d.s_burst_wlast=bs==BS::W&&bi+1==bt.data.size();d.s_burst_bready=bs==BS::B;
        d.s_axi_awvalid=ws==WS::SEND&&!waw;d.s_axi_awaddr=ww.addr;d.s_axi_wvalid=ws==WS::SEND&&!www;d.s_axi_wdata=ww.data;d.s_axi_wstrb=1;d.s_axi_bready=ws==WS::B;
        d.s_axi_arvalid=rs==RS::AR;d.s_axi_araddr=rr.addr;d.s_axi_rready=rs==RS::R;
#ifdef C_BURST_READ
        d.s_c_arvalid=cs==CS::AR;d.s_c_araddr=ct.addr;d.s_c_arlen=ct.count-1;d.s_c_arsize=2;d.s_c_arburst=1;d.s_c_rready=cs==CS::R;
#endif
    }
    void step(){prepare();drive();d.clk=0;d.eval();
        bool baw=d.s_burst_awvalid&&d.s_burst_awready,bw=d.s_burst_wvalid&&d.s_burst_wready,bb=d.s_burst_bvalid&&d.s_burst_bready;
        bool law=d.s_axi_awvalid&&d.s_axi_awready,lw=d.s_axi_wvalid&&d.s_axi_wready,lb=d.s_axi_bvalid&&d.s_axi_bready;
        bool lar=d.s_axi_arvalid&&d.s_axi_arready,lr=d.s_axi_rvalid&&d.s_axi_rready;auto rdata=d.s_axi_rdata;auto lrresp=d.s_axi_rresp;auto lbresp=d.s_axi_bresp;auto bbresp=d.s_burst_bresp;
#ifdef C_BURST_READ
        bool car=d.s_c_arvalid&&d.s_c_arready,cr=d.s_c_rvalid&&d.s_c_rready;auto crdata=d.s_c_rdata;auto crresp=d.s_c_rresp;auto crlast=d.s_c_rlast;
#else
        bool cr=false;
#endif
        bool pre_busy=core_busy(),pre_done=device_done(),ack_accept=device_write_accepts_ack();
        d.contextp()->timeInc(1);d.clk=1;d.eval();d.contextp()->timeInc(1);d.clk=0;d.eval();cycle++;
        if(baw){event(bt.op,"BURST_AW_ACCEPT",bt.bank,bt.addr);bs=BS::W;}
        if(bw){on_commit(bt.op,bt.bank,bt.addr+4*bi,bt.strb[bi],pre_busy,pre_done,lr&&rr.addr>=C_BASE);if(++bi==bt.data.size())bs=BS::B;}
        if(bb){if(bbresp)throw std::runtime_error("Burst BRESP error");event(bt.op,"BURST_B_CONSUME",bt.bank);bs=BS::IDLE;}
        if(law)waw=true;if(lw)www=true;if(ws==WS::SEND&&waw&&www)ws=WS::B;
        if(lb){if(lbresp)throw std::runtime_error("Lite BRESP error");on_write_response();ws=WS::IDLE;}
        if(lar)rs=RS::R;if(lr){if(lrresp)throw std::runtime_error("Lite RRESP error");on_read_response(rdata);rs=RS::IDLE;}
#ifdef C_BURST_READ
        if(car){c_events<<cycle<<','<<ct.op<<",AR,0x"<<std::hex<<ct.addr<<std::dec<<','<<ct.count<<",0\n";cs=CS::R;}
        if(cr){if(crresp)throw std::runtime_error("C Burst RRESP error");if(crlast!=(ci+1==ct.count))throw std::runtime_error("C Burst RLAST error");
            c_events<<cycle<<','<<ct.op<<(ci==0?",R_FIRST,":(crlast?",R_LAST,":",R,"))<<"0x"<<std::hex<<(ct.addr+4*ci)<<std::dec<<','<<ct.count<<','<<ci<<'\n';
            on_c_read_response(crdata,ct.first+ci);if(++ci==ct.count)cs=CS::IDLE;}
#endif
        monitor_post();
        if(ack_accept)on_ack_accept();
    }
    bool core_busy()const{
#ifdef C_BURST_READ
        return d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__core_busy;
#elif defined(DUAL_BANK)
        return d.rootp->systolic_axi_dual_bank_top__DOT__core_busy;
#else
        return d.rootp->systolic_axi_burst_top__DOT__core_busy;
#endif
    }
    bool core_start()const{
#ifdef C_BURST_READ
        return d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__core_start;
#elif defined(DUAL_BANK)
        return d.rootp->systolic_axi_dual_bank_top__DOT__core_start;
#else
        return d.rootp->systolic_axi_burst_top__DOT__core_start;
#endif
    }
    bool core_done()const{
#ifdef C_BURST_READ
        return d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__core_done;
#elif defined(DUAL_BANK)
        return d.rootp->systolic_axi_dual_bank_top__DOT__core_done;
#else
        return d.rootp->systolic_axi_burst_top__DOT__core_done;
#endif
    }
    bool device_done()const{
#ifdef C_BURST_READ
        return d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__u_device__DOT__state==2;
#elif defined(DUAL_BANK)
        return d.rootp->systolic_axi_dual_bank_top__DOT__u_device__DOT__state==2;
#else
        return d.rootp->systolic_axi_burst_top__DOT__u_device__DOT__state==2;
#endif
    }
    bool device_write_accepts_ack()const{
#ifdef C_BURST_READ
        return d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__l_wr_en &&
               d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__l_addr==ACK &&
               !d.rootp->systolic_axi_dual_bank_burst_read_top__DOT__wr_error;
#elif defined(DUAL_BANK)
        return d.rootp->systolic_axi_dual_bank_top__DOT__l_wr_en &&
               d.rootp->systolic_axi_dual_bank_top__DOT__l_addr==ACK &&
               !d.rootp->systolic_axi_dual_bank_top__DOT__wr_error;
#else
        return d.rootp->systolic_axi_burst_top__DOT__l_wr_en &&
               d.rootp->systolic_axi_burst_top__DOT__l_addr==ACK &&
               !d.rootp->systolic_axi_burst_top__DOT__wr_error;
#endif
    }
    void on_commit(unsigned id,unsigned bank,std::uint32_t addr,std::uint8_t strb,bool busy,bool done,bool same_result){
        auto&op=ops[id];if(!op.first_commit){op.first_commit=cycle;event(id,"INPUT_FIRST_COMMIT",bank,addr);}
        unsigned base=(addr>=PB[bank])?PB[bank]:PA[bank];unsigned word=(addr-base)/4;
        for(unsigned l=0;l<4;l++)if(strb&(1u<<l)){unsigned p=word*4+l;if(p<N*K){unsigned side=base==PB[bank];unsigned key=side*(N*K)+p;
            unsigned idx=key/64,bit=key%64; // N*K may exceed 64; count unique with a flat vector below.
            (void)idx;(void)bit;commit_seen(id,key);}}
        if(busy){op.overlap_busy++;event(id,"LOAD_DURING_CORE_BUSY",bank,addr);}if(done)op.overlap_done++;if(same_result)op.overlap_result++;
    }
    std::vector<std::vector<bool>> committed=std::vector<std::vector<bool>>(OPS,std::vector<bool>(2*N*K,false));
    void commit_seen(unsigned id,unsigned key){if(!committed[id][key]){committed[id][key]=true;if(++seen_count[id]==2*N*K){ops[id].input_complete=cycle;ops[id].phase=Phase::READY;event(id,"INPUT_COMPLETE");}}}
    void on_write_response(){auto&op=ops[ww.op];if(ww.start){if(op.phase!=Phase::RUNNING)throw std::runtime_error("START not accepted");if(dual&&ww.op+1<OPS&&ops[ww.op+1].phase==Phase::EMPTY)enqueue_load(ww.op+1);}}
    void on_ack_accept(){auto&op=ops[current];if(op.phase!=Phase::ACKING)throw std::runtime_error("unexpected ACK acceptance");
        op.ack=cycle;op.phase=Phase::COMPLETE;event(current,"ACK_ACCEPT");completed++;current++;if(!dual&&current<OPS)enqueue_load(current);}
    void on_read_response(std::uint32_t value){auto&op=ops[rr.op];if(rr.status){op.polls++;if(value&2){op.host_done=cycle;event(rr.op,"HOST_DONE_OBSERVED");start_results(rr.op);}else if(op.phase==Phase::RUNNING)rq.push_back(rr);}
        else {auto actual=wrap18(value);if(actual!=expect[rr.result_index])throw std::runtime_error("golden mismatch");op.results++;if(op.results==1){op.first_result=cycle;event(rr.op,"RESULT_FIRST_RESPONSE",-1,rr.addr);}if(op.results==N*N){op.last_result=cycle;event(rr.op,"RESULT_LAST_RESPONSE",-1,rr.addr);queue_ack(rr.op);}}}
    void on_c_read_response(std::uint32_t value,unsigned result_index){auto&op=ops[current];auto actual=wrap18(value);
        if(result_index>=expect.size()||actual!=expect[result_index])throw std::runtime_error("C Burst golden mismatch");op.results++;
        if(op.results==1){op.first_result=cycle;event(current,"RESULT_FIRST_RESPONSE",-1,C_BASE);}
        if(op.results==N*N){op.last_result=cycle;event(current,"RESULT_LAST_RESPONSE",-1,C_BASE+4*(N*N-1));queue_ack(current);}}
    void monitor_post(){if(current<OPS){auto&op=ops[current];if(core_start()&&!op.start){op.start=cycle;op.phase=Phase::RUNNING;event(current,"START_ACCEPT");}
        if(core_busy()&&!op.busy){op.busy=cycle;event(current,"CORE_BUSY_BEGIN");}if(core_done()&&!op.core_done){op.core_done=cycle;event(current,"CORE_DONE");}
        if(device_done()&&!op.device_done){op.device_done=cycle;event(current,"DEVICE_DONE");}}}
    void write_outputs(){
#ifdef C_BURST_READ
        c_events.flush();
#endif
        std::ofstream tasks("tasks.csv");tasks<<"mode,N,K,operation,bank,first_aw,first_commit,input_complete,start,busy_begin,core_done,device_done,host_done,first_result,last_result,ack,polls,load_during_core_busy,load_during_device_done,burst_and_result_same_cycle\n";
        const char*mode=
#ifdef C_BURST_READ
            "dual_c_burst";
#else
            dual?"dual":"single";
#endif
        for(auto&o:ops)tasks<<mode<<','<<N<<','<<K<<','<<o.id<<','<<o.bank<<','<<o.first_aw<<','<<o.first_commit<<','<<o.input_complete<<','<<o.start<<','<<o.busy<<','<<o.core_done<<','<<o.device_done<<','<<o.host_done<<','<<o.first_result<<','<<o.last_result<<','<<o.ack<<','<<o.polls<<','<<o.overlap_busy<<','<<o.overlap_done<<','<<o.overlap_result<<'\n';
        double avg_interval=0;for(unsigned i=1;i<OPS;i++)avg_interval+=ops[i].start-ops[i-1].start;avg_interval/=OPS-1;
        auto avg=[&](auto fn){double s=0;for(auto&o:ops)s+=fn(o);return s/OPS;};
        std::ofstream sum("summary.csv");sum<<"mode,N,K,operations,first_aw_to_last_ack,first_commit_to_last_ack,average_start_interval,avg_start_to_device_done,avg_device_done_to_host_done,avg_host_done_to_first_result,avg_first_to_last_result,avg_last_result_to_ack,avg_ack_to_next_start,load_during_core_busy,load_during_device_done,burst_and_result_same_cycle\n";
        std::uint64_t busy=0,done=0,same=0;for(auto&o:ops){busy+=o.overlap_busy;done+=o.overlap_done;same+=o.overlap_result;}
        double acknext=0;for(unsigned i=0;i+1<OPS;i++)acknext+=ops[i+1].start-ops[i].ack;acknext/=OPS-1;
        sum<<mode<<','<<N<<','<<K<<','<<OPS<<','<<ops.back().ack-ops.front().first_aw+1<<','<<ops.back().ack-ops.front().first_commit+1<<','<<avg_interval<<','
           <<avg([](auto&o){return o.device_done-o.start;})<<','<<avg([](auto&o){return o.host_done-o.device_done;})<<','<<avg([](auto&o){return o.first_result-o.host_done;})<<','<<avg([](auto&o){return o.last_result-o.first_result;})<<','<<avg([](auto&o){return o.ack-o.last_result;})<<','<<acknext<<','<<busy<<','<<done<<','<<same<<'\n';
        std::cout<<"PASS "<<(dual?"dual":"single")
#ifdef C_BURST_READ
                 <<"_c_burst"
#endif
                 <<" N="<<N<<" K="<<K<<" cycles="<<(ops.back().ack-ops.front().first_aw+1)<<"\n";
    }
};
}

int main(int argc,char**argv){VerilatedContext context;context.commandArgs(argc,argv);Dut dut{&context};
    try{Bench bench(dut,
#ifdef DUAL_BANK
        true
#else
        false
#endif
    );return bench.run();}catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<'\n';dut.final();return 1;}}
