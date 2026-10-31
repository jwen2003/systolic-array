#include "axi_burst_bfm.hpp"
#include "Vsystolic_axi_burst_top.h"
#include "verilated.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
unsigned checks=0;
void check(bool value, const char* what) {
    ++checks;
    if (!value) throw std::runtime_error(what);
}

// All directed concurrency checks use PUBLIC pins; no internal memory access.
void arbitration_test(AxiBurstBfm& b, Vsystolic_axi_burst_top& d) {
    b.reset();
    // Lite W-only reservation must block Burst until Lite AW and B finish.
    d.s_axi_wdata=0x55; d.s_axi_wstrb=1; d.s_axi_wvalid=1;
    d.s_burst_awaddr=0x2000; d.s_burst_awlen=0; d.s_burst_awvalid=1;
    auto s=b.step(); check(s.lw && !s.baw,"Lite W priority");
    d.s_axi_wvalid=0;
    for (unsigned i=0;i<3;++i) check(!b.step().baw,"partial Lite transaction reserves port");
    d.s_axi_awaddr=0x1000; d.s_axi_awvalid=1;
    s=b.step(); check(s.law && !s.baw,"Lite AW joins saved W");
    d.s_axi_awvalid=0;
    for (unsigned i=0;i<3;++i) check(!b.step().baw,"Lite held B reserves port");
    d.s_axi_bready=1; s=b.step(); check(s.lb && !s.baw,"Lite B completes before Burst");
    d.s_axi_bready=0;
    check(b.step().baw,"pending Burst accepted after Lite response");
    d.s_burst_awvalid=0;
    d.s_burst_wdata=0x33; d.s_burst_wstrb=1;
    d.s_burst_wlast=1; d.s_burst_wvalid=1;
    check(b.step().bw,"pending Burst data accepted");
    d.s_burst_wvalid=0; d.s_burst_bready=1;
    check(b.step().bb,"pending Burst response"); d.s_burst_bready=0;
    check(b.axi_read(0x1000)==0x55 && b.axi_read(0x2000)==0x33,"both writes preserved");

    // Symmetric AW-only reservation: never preempt the saved address with Burst.
    b.reset();
    d.s_axi_awaddr=0x1000; d.s_axi_awvalid=1;
    check(b.step().law,"Lite AW first"); d.s_axi_awvalid=0;
    d.s_burst_awaddr=0x2000; d.s_burst_awlen=0; d.s_burst_awvalid=1;
    for (unsigned i=0;i<2;++i) check(!b.step().baw,"AW-only owner blocks Burst");
    d.s_axi_wdata=0x12; d.s_axi_wstrb=1; d.s_axi_wvalid=1;
    s=b.step(); check(s.lw && !s.baw,"saved AW gets its W"); d.s_axi_wvalid=0;
    b.step(); d.s_axi_bready=1;
    check(b.step().lb,"AW-first Lite B"); d.s_axi_bready=0;
    check(b.step().baw,"Burst released after AW-first Lite"); d.s_burst_awvalid=0;
    d.s_burst_wdata=0x34; d.s_burst_wlast=1; d.s_burst_wvalid=1;
    check(b.step().bw,"Burst after AW-only reservation"); d.s_burst_wvalid=0;
    d.s_burst_bready=1; check(b.step().bb,"Burst B after AW-only"); d.s_burst_bready=0;
    check(b.axi_read(0x1000)==0x12,"saved Lite address/data match");

    b.reset();
    d.s_burst_awaddr=0x2000; d.s_burst_awlen=1; d.s_burst_awvalid=1;
    check(b.step().baw,"Burst acquires idle port"); d.s_burst_awvalid=0;
    d.s_axi_awaddr=0x1000; d.s_axi_awvalid=1;
    d.s_axi_wdata=0x66; d.s_axi_wstrb=1; d.s_axi_wvalid=1;
    for (unsigned i=0;i<2;++i) {
        s=b.step(); check(!s.law && !s.lw,"Lite waits for active Burst");
    }
    d.s_burst_wstrb=1; d.s_burst_wvalid=1;
    for (unsigned i=0;i<2;++i) {
        d.s_burst_wdata=0x44+i; d.s_burst_wlast=i==1;
        s=b.step(); check(s.bw && !s.law && !s.lw,"Burst owns each write edge");
    }
    d.s_burst_wvalid=0;
    for (unsigned i=0;i<3;++i) {
        s=b.step(); check(!s.law && !s.lw && d.s_burst_bvalid,"held Burst B locks Lite");
    }
    check(b.axi_read(0x0008)==0,"Lite reads remain available during held Burst B");
    d.s_burst_bready=1; s=b.step();
    check(s.bb && !s.law && !s.lw,"Burst B releases before Lite acceptance");
    d.s_burst_bready=0;
    s=b.step(); check(s.law && s.lw,"waiting Lite accepted after Burst");
    d.s_axi_awvalid=0; d.s_axi_wvalid=0;
    d.s_axi_bready=1;
    bool received=false;
    for (unsigned i=0;i<10;++i) if (b.step().lb) { received=true; break; }
    d.s_axi_bready=0;
    check(received,"waiting Lite has response");
    check(b.axi_read(0x1000)==0x66 && b.axi_read(0x2004)==0x45,"ownership mux kept data");
    check(b.axi_read(0x0010)==0,"arbitration created no device errors");

    // Shared reset clears BOTH ownership records, even with partial Lite data.
    d.s_axi_wvalid=1; check(b.step().lw,"partial request before reset");
    b.reset();
    const auto m=b.burst_write(0x1000,{7,8},0,3);
    check(m.transfer==2 && b.axi_read(0x1004)==8,"reset/held-response recovery");
}

void error_test(AxiBurstBfm& b, std::uint32_t words) {
    b.reset();
    bool rejected=false;
    try { (void)b.burst_write(0x0004,{1}); }
    catch (const std::runtime_error& e) {
        rejected=std::string(e.what()).find("Burst B response=2")!=std::string::npos;
        if (!rejected) throw;
    }
    check(rejected && b.axi_read(0x0008)==0,"Burst CSR rejection without side effect");
    b.axi_write(0x1000,1); // B remains incomplete, so START is rejected.
    try { b.axi_write(0x0004,1); } catch (const std::runtime_error&) {}
    check(b.axi_read(0x0010)==2,"Lite error routing preserved");
    b.axi_write(0x0010,0xff);
    // Unlike invalid descriptors, a real Device permission failure must also
    // reach BOTH Burst B and the Device's own sticky error register.
    for (std::uint32_t x=0;x<words;++x) {
        b.axi_write(0x1000+4*x,0); b.axi_write(0x2000+4*x,0);
    }
    b.axi_write(0x0004,1);
    bool done=false;
    for (unsigned poll=0;poll<10000;++poll)
        if (b.axi_read(0x0008) & 2) { done=true; break; }
    check(done,"error test completion");
    rejected=false;
    try { (void)b.burst_write(0x1000,{99}); }
    catch (const std::runtime_error& e) {
        rejected=std::string(e.what()).find("Burst B response=2")!=std::string::npos;
        if (!rejected) throw;
    }
    check(rejected && b.axi_read(0x0010)==8,"Device failure routed to Burst response");
    check(b.axi_read(0x3000)==0,"failed Burst did not corrupt result");
    b.axi_write(0x0010,0xff); b.axi_write(0x000c,1);
}

void run_case(AxiBurstBfm& b, std::uint32_t n, std::uint32_t k,
              unsigned length, unsigned gap, std::ofstream& csv) {
    b.reset(); // Outside invocation timing. Two operations below share state.
    std::vector<std::uint32_t> a(n*k),bb(n*k);
    for (unsigned operation=0;operation<2;++operation) {
        for (std::size_t i=0;i<a.size();++i) {
            const int av=operation==0 ? int(i%11)-5 : (i%2 ? 127 : -128);
            const int bv=operation==0 ? int((i*3)%13)-6 : (i%2 ? 127 : -128);
            a[i]=std::uint8_t(av); bb[i]=std::uint8_t(bv);
        }
        const auto begin=b.cycles();
        check(b.axi_read(0x0008)==0,"preflight LOAD");
        const auto load_begin=b.cycles();
        std::uint64_t transactions=0, data_cycles=0, transfers=0, master=0, slave=0, both=0;
        for (unsigned which=0;which<2;++which) {
            const auto& words=which==0 ? a : bb;
            const std::uint32_t base=which==0 ? 0x1000 : 0x2000;
            if (!length) {
                for (std::size_t x=0;x<words.size();++x) b.axi_write(base+4*std::uint32_t(x),words[x]);
                transactions+=words.size();
            } else {
                for (std::size_t x=0;x<words.size();x+=length) {
                    const auto stop=std::min(x+length,words.size());
                    const auto m=b.burst_write(base+4*std::uint32_t(x),
                        std::vector<std::uint32_t>(words.begin()+x,words.begin()+stop),gap);
                    ++transactions; data_cycles+=m.data_cycles(); transfers+=m.transfer;
                    master+=m.master_only; slave+=m.slave_only; both+=m.both;
                    check(m.cycles==m.data_cycles()+2,"per-Burst H differs from prediction");
                }
            }
        }
        check(b.axi_read(0x0008)==4,"complete buffer bitmap after load");
        const auto load=b.cycles()-load_begin;
        const auto expected=length ? 2ull*n*k+(2ull*n*k-transactions)*gap+2*transactions+2
                                   : 6ull*n*k+2;
        check(load==expected,"load cycle model mismatch");
        if (length) check(transfers==2ull*n*k && slave==0 && both==0,"continuous receiver metrics");
        b.axi_write(0x0004,1);
        bool done=false;
        for (unsigned poll=0;poll<10000;++poll) {
            const auto status=b.axi_read(0x0008);
            check(!(status & 8),"error during compute");
            if (status & 2) { done=true; break; }
        }
        check(done,"compute completion timeout");
        auto signed_byte=[](std::uint32_t v)->std::int64_t { return v<128 ? v : std::int64_t(v)-256; };
        for (std::uint32_t i=0;i<n;++i) for (std::uint32_t j=0;j<n;++j) {
            std::int64_t sum=0;
            for (std::uint32_t x=0;x<k;++x) sum+=signed_byte(a[i*k+x])*signed_byte(bb[x*n+j]);
            const auto expected_signed=((sum+131072)%262144+262144)%262144-131072;
            const auto raw=b.axi_read(0x3000+4*(i*n+j));
            const auto low=std::int32_t(raw & 0x3ffff);
            check((low>=131072 ? low-262144 : low)==expected_signed,"matmul result mismatch");
        }
        b.axi_write(0x000c,1);
        const auto total=b.cycles()-begin;
        check(b.axi_read(0x0008)==0 && b.axi_read(0x0010)==0,"clean ACK lifecycle");
        csv << n << ',' << k << ',' << (length ? "BURST" : "LITE_ON_DUAL_TOP") << ','
            << length << ',' << gap << ',' << operation << ',' << transactions << ','
            << transfers << ',' << data_cycles << ',' << master << ',' << slave << ',' << both << ','
            << expected << ',' << load << ',' << total << '\n';
        std::cout << "PASS " << (length ? "Burst" : "Lite") << " L=" << length << " gap=" << gap
                  << " op=" << operation << " load=" << load << " total=" << total << '\n';
    }
}
}

int main(int argc,char** argv) {
    VerilatedContext context; context.commandArgs(argc,argv);
    Vsystolic_axi_burst_top d{&context};
    try {
        AxiBurstBfm b{d}; b.reset();
        const auto n=b.axi_read(0x0020), k=b.axi_read(0x0024);
        check(n && k && n*k>=2,"test requires at least two input words");
        check(b.axi_read(0x0028)==8 && b.axi_read(0x002c)==18,"dtype mismatch");
        arbitration_test(b,d); error_test(b,n*k);
        std::ofstream csv("burst_comparison.csv");
        if (!csv) throw std::runtime_error("Cannot create burst_comparison.csv");
        csv << "n,k,path,length,master_gap,operation,write_transactions,burst_beats,data_cycles,"
               "master_only,slave_only,both,predicted_load,measured_load,measured_total\n";
        run_case(b,n,k,0,0,csv);
        for (unsigned length : {1u,2u,4u,8u,16u})
            for (unsigned gap : {0u,1u,3u}) run_case(b,n,k,length,gap,csv);
        csv.close();
        if (!csv) throw std::runtime_error("Failed writing CSV");
        std::cout << "PASS dual-port integration/BFM: " << checks << " checks; CSV contains RTL measurements\n";
        d.final(); return 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n'; d.final(); return 1;
    }
}
