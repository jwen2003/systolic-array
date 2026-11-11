#include <functional>
// Reuse the independent golden/check helpers and old-port arbitration tests.
// The old benchmark entry remains available through its unchanged own script.
#define main unpacked_benchmark_main
#include "../burst/main.cpp"
#undef main

namespace {
struct PackedData {
    std::vector<std::uint32_t> words;
    std::vector<std::uint8_t> strobes;
};
PackedData pack(const std::vector<std::uint32_t>& bytes) {
    // Pack in the Device contract's linear row-major order. Tail strobes mark
    // only real elements; asserting a padding lane is tested as an error below.
    PackedData p;
    for (std::size_t x=0;x<bytes.size();x+=4) {
        std::uint32_t word=0; std::uint8_t strobe=0;
        for (std::size_t lane=0;lane<4 && x+lane<bytes.size();++lane) {
            word |= (bytes[x+lane]&255u) << (8*lane);
            strobe |= std::uint8_t(1u<<lane);
        }
        p.words.push_back(word); p.strobes.push_back(strobe);
    }
    return p;
}
void expect_error(const std::function<void()>& request) {
    bool rejected=false;
    try { request(); }
    catch (const std::runtime_error& e) {
        rejected=std::string(e.what()).find("response=2")!=std::string::npos;
        if (!rejected) throw;
    }
    check(rejected,"expected SLVERR response");
}
void packed_contract(AxiBurstBfm& b, unsigned count) {
    b.reset();
    // Every lane is independently enabled. Upper lanes must work with lane 0 off.
    b.burst_write(0x4000,{0x807f02ff},0,3,{0xa});
    for (unsigned x=0;x<std::min(count,4u);++x)
        check(b.axi_read(0x1000+4*x)==(x==1 ? 2u : x==3 ? 0xffffff80u : 0u),
              "sparse WSTRB / held response / sign extension");
    b.burst_write(0x4000,{0x001100fe},0,0,{0x5});
    const std::uint32_t first[]={0xfffffffeu,2,17,0xffffff80u};
    for (unsigned x=0;x<std::min(count,4u);++x)
        check(b.axi_read(0x1000+4*x)==first[x],"masked lanes must preserve prior values");
    // Old -> packed -> old updates must alias a single physical input store.
    b.axi_write(0x1000,33); check(b.axi_read(0x1000)==33,"legacy alias write");
    b.axi_write(0x4000,0x77,1); check(b.axi_read(0x1000)==0x77,"Lite packed alias");
    b.burst_write(0x4000,{0xffffffff},0,0,{0});
    check(b.axi_read(0x1000)==0x77,"zero strobe preserves payload");
    b.reset();
    check(b.axi_read(0x1000)==0 && b.axi_read(8)==0,"reset clears maps not exposed stale storage");
    // Missing a valid lane must prevent INPUTS_READY and reject START.
    for (unsigned x=0;x<count;++x) b.axi_write(0x2000+4*x,x);
    auto a=pack(std::vector<std::uint32_t>(count,1));
    a.strobes.back() &= std::uint8_t(~(1u<<((count-1)%4)));
    for (std::size_t x=0;x<a.words.size();x+=16) {
        const auto stop=std::min(x+16,a.words.size());
        b.burst_write(0x4000+4*unsigned(x),{a.words.begin()+x,a.words.begin()+stop},0,0,
                      {a.strobes.begin()+x,a.strobes.begin()+stop});
    }
    check(!(b.axi_read(8)&4),"missing lane must not set INPUTS_READY");
    expect_error([&]{b.axi_write(4,1);});
    check(b.axi_read(0x10)==2,"incomplete inputs sticky bit");
    b.axi_write(0x10,255);
    const auto tail_addr=0x4000+4*((count-1)/4);
    const auto missing_lane=(count-1)%4;
    b.burst_write(tail_addr,{0x01010101},0,0,{std::uint8_t(1u<<missing_lane)});
    check(b.axi_read(8)==4,"final missing lane completes bitmap");
    // Tail invalid asserted lane must reject all lanes of that beat.
    if (count%4) {
        const auto before=b.axi_read(0x1000+4*(count-1));
        expect_error([&]{b.burst_write(tail_addr,{0x99999999},0,0,{15});});
        check(b.axi_read(0x1000+4*(count-1))==before,"invalid tail must reject whole beat");
        check(b.axi_read(0x10)==4,"tail error sticky status");
        b.axi_write(0x10,255);
    }
    // Descriptor outside rounded packed range must not reach Device.
    expect_error([&]{b.burst_write(0x4000+4*unsigned(a.words.size()-1),{1,2});});
    check(b.axi_read(0x10)==0,"descriptor rejection has no Device side effect");
    expect_error([&]{b.axi_read(0x4000);});
    b.axi_write(0x10,255);
    expect_error([&]{b.axi_write(0x4001,1);});
    check(b.axi_read(0x10)==32,"misaligned packed Lite access");
    b.axi_write(0x10,255);
    b.axi_write(4,1);
    expect_error([&]{b.burst_write(0x5000,{0x12345678},0,0,{15});});
    check(b.axi_read(0x10)==8,"packed write forbidden during operation");
    b.axi_write(0x10,255);
    bool done=false;
    for (unsigned x=0;x<10000;++x) if (b.axi_read(8)&2) {done=true; break;}
    check(done,"contract test completion");
    const auto result=b.axi_read(0x3000);
    expect_error([&]{b.burst_write(0x4000,{0},0,0,{15});});
    check(b.axi_read(0x3000)==result,"DONE snapshot stable after forbidden packed write");
    b.axi_write(0x10,255); b.axi_write(12,1);
    check(b.axi_read(8)==0,"ACK clears both maps");
}
void packed_case(AxiBurstBfm& b,unsigned n,unsigned k,unsigned length,std::ofstream& csv) {
    b.reset();
    for (unsigned operation=0;operation<2;++operation) {
        std::vector<std::uint32_t> a(n*k),bb(n*k);
        for (unsigned x=0;x<n*k;++x) {
            // Distinct consecutive bytes, negative values, and overflow workload.
            a[x]=std::uint8_t(operation ? (x%2 ? 127 : -128) : int((x*7)%251)-125);
            bb[x]=std::uint8_t(operation ? (x%2 ? 127 : -128) : int((x*13)%253)-126);
        }
        // Invocation timing includes preflight through ACK. The later readback
        // replay is outside this boundary and validates storage coordinates
        // and bitmaps without contaminating the performance measurement.
        const auto begin=b.cycles(); check(b.axi_read(8)==0,"packed preflight");
        const auto load_begin=b.cycles();
        std::uint64_t beats=0,bursts=0,last_commit=0;
        for (unsigned which=0;which<2;++which) {
            const auto p=pack(which ? bb : a);
            for (std::size_t x=0;x<p.words.size();x+=length) {
                const auto stop=std::min(x+length,p.words.size());
                const auto m=b.burst_write((which ? 0x5000 : 0x4000)+4*unsigned(x),
                    {p.words.begin()+x,p.words.begin()+stop},0,0,
                    {p.strobes.begin()+x,p.strobes.begin()+stop});
                check(m.transfer==stop-x && m.master_only==0 && m.slave_only==0 && m.both==0,
                      "packed continuous transfer metrics");
                check(m.cycles==m.transfer+2,"packed per-burst fixed overhead");
                beats+=m.transfer; ++bursts; last_commit=m.last_transfer_cycle-load_begin;
            }
        }
        const auto writes=b.cycles()-load_begin;
        check(b.axi_read(8)==4,"packed inputs ready after last write");
        const auto confirmed=b.cycles()-load_begin;
        const auto predicted_beats=2ull*((n*k+3)/4);
        const auto predicted_bursts=2ull*((((n*k+3)/4)+length-1)/length);
        check(beats==predicted_beats && bursts==predicted_bursts,"packed descriptor model");
        check(writes==predicted_beats+2*predicted_bursts,"packed write-cycle prediction");
        check(last_commit+1==writes,"last commit precedes final B by one cycle");
        b.axi_write(4,1);
        bool done=false;
        for (unsigned x=0;x<10000;++x) {
            const auto status=b.axi_read(8); check(!(status&8),"packed operation error");
            if (status&2) {done=true;break;}
        }
        check(done,"packed completion timeout");
        auto signed_byte=[](std::uint32_t v)->std::int64_t {return v<128 ? v : std::int64_t(v)-256;};
        for (unsigned i=0;i<n;++i) for (unsigned j=0;j<n;++j) {
            std::int64_t sum=0;
            for (unsigned x=0;x<k;++x) sum+=signed_byte(a[i*k+x])*signed_byte(bb[x*n+j]);
            const auto expected=((sum+131072)%262144+262144)%262144-131072;
            const auto raw=b.axi_read(0x3000+4*(i*n+j));
            const auto low=std::int32_t(raw&0x3ffff);
            check((low>=131072 ? low-262144 : low)==expected,"packed independent matmul golden");
        }
        b.axi_write(12,1);
        const auto total=b.cycles()-begin;
        // Readback validation is a SEPARATE replay; it must not inflate invocation timing.
        const auto p=pack(a);
        for (std::size_t x=0;x<p.words.size();x+=16) {
            const auto stop=std::min(x+16,p.words.size());
            b.burst_write(0x4000+4*unsigned(x),{p.words.begin()+x,p.words.begin()+stop},0,0,
                          {p.strobes.begin()+x,p.strobes.begin()+stop});
        }
        for (unsigned x=0;x<n*k;++x)
            check(b.axi_read(0x1000+4*x)==std::uint32_t(std::int32_t(signed_byte(a[x]))),
                  "packed A old-window readback including cross-row");
        const auto q=pack(bb);
        for (std::size_t x=0;x<q.words.size();x+=16) {
            const auto stop=std::min(x+16,q.words.size());
            b.burst_write(0x5000+4*unsigned(x),{q.words.begin()+x,q.words.begin()+stop},0,0,
                          {q.strobes.begin()+x,q.strobes.begin()+stop});
        }
        for (unsigned x=0;x<n*k;++x)
            check(b.axi_read(0x2000+4*x)==std::uint32_t(std::int32_t(signed_byte(bb[x]))),
                  "packed B old-window readback");
        // Clear replay state through a full lifecycle, no reset between measured operations.
        b.axi_write(4,1);
        bool replay_done=false;
        for (unsigned x=0;x<10000;++x) if (b.axi_read(8)&2) {replay_done=true;break;}
        check(replay_done,"readback replay completion"); b.axi_write(12,1);
        csv<<n<<','<<k<<",PACKED,"<<length<<','<<operation<<','<<beats<<','<<bursts<<','
           <<last_commit<<','<<writes<<','<<confirmed<<','<<total<<'\n';
        std::cout<<"PASS packed L="<<length<<" op="<<operation<<" write="<<writes
                 <<" last_commit="<<last_commit<<" confirmed_load="<<confirmed<<" total="<<total<<'\n';
    }
}
}
int main(int argc,char** argv) {
    VerilatedContext context; context.commandArgs(argc,argv); Vsystolic_axi_burst_top d{&context};
    try {
        AxiBurstBfm b{d}; b.reset(); const auto n=b.axi_read(0x20),k=b.axi_read(0x24);
        check(n*k>=4,"packed tests require >=4 entries");
        arbitration_test(b,d); error_test(b,n*k); packed_contract(b,n*k);
        std::ofstream baseline("unpacked_reference.csv"),csv("packed_comparison.csv");
        if (!baseline || !csv) throw std::runtime_error("CSV open failed");
        baseline<<"n,k,path,length,master_gap,operation,write_transactions,burst_beats,data_cycles,master_only,slave_only,both,predicted_load,measured_load,measured_total\n";
        run_case(b,n,k,16,0,baseline);
        csv<<"n,k,path,length,operation,beats,bursts,last_commit_cycles,write_complete_cycles,confirmed_load_cycles,total_cycles\n";
        for (unsigned length : {1u,4u,16u}) packed_case(b,n,k,length,csv);
        baseline.close();csv.close(); if (!baseline || !csv) throw std::runtime_error("CSV write failed");
        std::cout<<"PASS packed integration: "<<checks<<" checks\n"; d.final(); return 0;
    } catch(const std::exception& e) {std::cerr<<"FAIL: "<<e.what()<<'\n';d.final();return 1;}
}
