#include "axi_burst_bfm.hpp"
#include "Vsystolic_axi_burst_top.h"
#include "Vsystolic_axi_burst_top___024root.h"
#include "verilated.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr unsigned N = 2;
constexpr unsigned K = 17;
constexpr unsigned WORDS = N * K;
constexpr unsigned TOTAL_INPUTS = 2 * WORDS;
constexpr std::uint32_t STATUS = 0x0008;
constexpr std::uint32_t COMMAND = 0x0004;
constexpr std::uint32_t ACK = 0x000c;
constexpr std::uint32_t A_BASE = 0x1000;
constexpr std::uint32_t B_BASE = 0x2000;
constexpr std::uint32_t C_BASE = 0x3000;

struct Result {
    unsigned gap = 0;
    unsigned length = 0;
    std::uint64_t load_a = 0;
    std::uint64_t load_b = 0;
    std::uint64_t pure_write = 0;
    std::uint64_t ready_check = 0;
    std::uint64_t load_with_ready = 0;
    std::uint64_t start_access = 0;
    std::uint64_t start_edge = 0;
    std::uint64_t done_edge = 0;
    std::uint64_t compute_cycles = 0;
    std::uint64_t done_poll = 0;
    std::uint64_t poll_reads = 0;
    std::uint64_t read_c = 0;
    std::uint64_t ack = 0;
    std::uint64_t end_to_end = 0;
    std::uint64_t repeat_task = 0;
    std::uint64_t transactions = 0;
    std::uint64_t beats = 0;
};

std::int32_t sx18(std::uint32_t value) {
    value &= 0x3ffffu;
    return (value & 0x20000u) ? std::int32_t(value) - 0x40000 : std::int32_t(value);
}

std::int64_t golden(const std::vector<std::uint32_t>& a,
                    const std::vector<std::uint32_t>& b,
                    unsigned row, unsigned col) {
    auto sx8 = [](std::uint32_t value) { return std::int64_t(std::int8_t(value)); };
    std::int64_t sum = 0;
    for (unsigned inner = 0; inner < K; ++inner)
        sum += sx8(a[row * K + inner]) * sx8(b[inner * N + col]);
    return ((sum + 131072) % 262144 + 262144) % 262144 - 131072;
}

void require_no_lite_activity(const BurstSample& sample) {
    if (sample.law || sample.lw || sample.lb || sample.lar || sample.lr)
        throw std::runtime_error("unexpected AXI-Lite activity during scheduled burst");
}

Result run_case(AxiBurstBfm& bfm, Vsystolic_axi_burst_top& dut,
                unsigned gap, unsigned length,
                const std::vector<std::uint32_t>& a,
                const std::vector<std::uint32_t>& b,
                std::ofstream& element_events,
                std::ofstream& transaction_events,
                std::ofstream& timeline) {
    bfm.reset();
    Result result;
    result.gap = gap;
    result.length = length;

    std::uint64_t accepted_start = 0;
    std::uint64_t visible_done = 0;
    bfm.set_cycle_observer([&](std::uint64_t cycle) {
        if (dut.rootp->systolic_axi_burst_top__DOT__core_start) accepted_start = cycle;
        if (dut.rootp->systolic_axi_burst_top__DOT__core_done) visible_done = cycle;
    });

    const auto t0 = bfm.cycles();
    auto phase = t0;
    unsigned global_index = 0;
    unsigned transaction_index = 0;

    auto scheduled_transaction = [&](const char* matrix, std::uint32_t address,
                                     const std::vector<std::uint32_t>& values,
                                     unsigned matrix_start) {
        const auto begin = bfm.cycles();
        dut.s_burst_awaddr = address;
        dut.s_burst_awlen = std::uint8_t(values.size() - 1);
        dut.s_burst_awsize = 2;
        dut.s_burst_awburst = 1;
        dut.s_burst_awvalid = 1;
        dut.s_burst_wvalid = 0;
        dut.s_burst_bready = 0;

        std::uint64_t aw_cycle = 0;
        for (unsigned guard = 0; guard < 10000 && !aw_cycle; ++guard) {
            const auto sample = bfm.step();
            require_no_lite_activity(sample);
            if (sample.baw) aw_cycle = bfm.cycles();
        }
        if (!aw_cycle) throw std::runtime_error("AW timeout");
        dut.s_burst_awvalid = 0;

        std::uint64_t first_w = 0;
        std::uint64_t last_w = 0;
        for (unsigned beat = 0; beat < values.size(); ++beat, ++global_index) {
            const auto ready_cycle = t0 + std::uint64_t(global_index) * (gap + 1);
            dut.s_burst_wvalid = 0;
            while (bfm.cycles() < ready_cycle) {
                const auto sample = bfm.step();
                require_no_lite_activity(sample);
                if (sample.bw) throw std::runtime_error("W handshake while WVALID is low");
            }

            dut.s_burst_wdata = values[beat];
            dut.s_burst_wstrb = 1;
            dut.s_burst_wlast = beat + 1 == values.size();
            dut.s_burst_wvalid = 1;
            std::uint64_t handshake = 0;
            for (unsigned guard = 0; guard < 10000 && !handshake; ++guard) {
                const auto stable_data = dut.s_burst_wdata;
                const auto stable_strb = dut.s_burst_wstrb;
                const auto stable_last = dut.s_burst_wlast;
                const auto sample = bfm.step();
                require_no_lite_activity(sample);
                if (!sample.bw && (dut.s_burst_wdata != stable_data ||
                                   dut.s_burst_wstrb != stable_strb ||
                                   dut.s_burst_wlast != stable_last))
                    throw std::runtime_error("W payload changed while stalled");
                if (sample.bw) handshake = bfm.cycles();
            }
            if (!handshake) throw std::runtime_error("W timeout");
            if (!first_w) first_w = handshake;
            last_w = handshake;
            element_events << gap << ',' << length << ',' << global_index << ','
                           << matrix << ',' << (matrix_start + beat) << ','
                           << ready_cycle << ',' << handshake << ','
                           << (handshake - ready_cycle) << '\n';
        }
        dut.s_burst_wvalid = 0;
        dut.s_burst_wlast = 0;
        dut.s_burst_bready = 1;
        std::uint64_t b_cycle = 0;
        for (unsigned guard = 0; guard < 10000 && !b_cycle; ++guard) {
            const auto sample = bfm.step();
            require_no_lite_activity(sample);
            if (sample.bb) {
                if (sample.bbre) throw std::runtime_error("Burst response was not OKAY");
                b_cycle = bfm.cycles();
            }
        }
        dut.s_burst_bready = 0;
        if (!b_cycle) throw std::runtime_error("B timeout");
        if (b_cycle != last_w + 1) throw std::runtime_error("unexpected last-W to B latency");

        transaction_events << gap << ',' << length << ',' << transaction_index++
                           << ',' << matrix << ",0x" << std::hex << address << std::dec
                           << ',' << values.size() << ',' << (values.size() - 1)
                           << ',' << begin << ',' << aw_cycle << ',' << first_w
                           << ',' << last_w << ',' << b_cycle << ",OKAY\n";
        ++result.transactions;
        result.beats += values.size();
    };

    auto load_matrix = [&](const char* matrix, std::uint32_t base,
                           const std::vector<std::uint32_t>& values) {
        for (unsigned index = 0; index < values.size(); index += length) {
            const auto stop = std::min<unsigned>(index + length, values.size());
            scheduled_transaction(matrix, base + 4 * index,
                                  std::vector<std::uint32_t>(values.begin() + index,
                                                             values.begin() + stop),
                                  index);
        }
    };

    load_matrix("A", A_BASE, a);
    result.load_a = bfm.cycles() - phase;
    phase = bfm.cycles();
    load_matrix("B", B_BASE, b);
    result.load_b = bfm.cycles() - phase;
    result.pure_write = bfm.cycles() - t0;

    phase = bfm.cycles();
    if (bfm.axi_read(STATUS) != 4) throw std::runtime_error("inputs not ready");
    result.ready_check = bfm.cycles() - phase;
    result.load_with_ready = bfm.cycles() - t0;

    phase = bfm.cycles();
    bfm.axi_write(COMMAND, 1, 1);
    result.start_access = bfm.cycles() - phase;
    phase = bfm.cycles();
    do {
        ++result.poll_reads;
    } while (!(bfm.axi_read(STATUS) & 2));
    result.done_poll = bfm.cycles() - phase;

    phase = bfm.cycles();
    for (unsigned row = 0; row < N; ++row) {
        for (unsigned col = 0; col < N; ++col) {
            const auto actual = sx18(bfm.axi_read(C_BASE + 4 * (row * N + col)));
            if (actual != golden(a, b, row, col))
                throw std::runtime_error("golden mismatch");
        }
    }
    result.read_c = bfm.cycles() - phase;
    result.end_to_end = bfm.cycles() - t0;
    phase = bfm.cycles();
    bfm.axi_write(ACK, 1, 1);
    result.ack = bfm.cycles() - phase;
    result.repeat_task = bfm.cycles() - t0;
    if (bfm.axi_read(STATUS) != 0) throw std::runtime_error("ACK did not restore LOAD");

    result.start_edge = accepted_start;
    result.done_edge = visible_done;
    if (!accepted_start || !visible_done || visible_done <= accepted_start)
        throw std::runtime_error("missing START/DONE event");
    result.compute_cycles = visible_done - accepted_start;
    timeline << gap << ',' << length << ",t0," << t0 << '\n'
             << gap << ',' << length << ",writes_complete," << t0 + result.pure_write << '\n'
             << gap << ',' << length << ",ready_complete," << t0 + result.load_with_ready << '\n'
             << gap << ',' << length << ",device_start," << accepted_start << '\n'
             << gap << ',' << length << ",device_done," << visible_done << '\n'
             << gap << ',' << length << ",last_c_response," << t0 + result.end_to_end << '\n'
             << gap << ',' << length << ",ack_complete," << t0 + result.repeat_task << '\n';
    bfm.set_cycle_observer({});
    return result;
}
} // namespace

int main(int argc, char** argv) {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    Vsystolic_axi_burst_top dut{&context};
    AxiBurstBfm bfm{dut};

    try {
        std::vector<std::uint32_t> a(WORDS), b(WORDS);
        for (unsigned index = 0; index < WORDS; ++index) {
            a[index] = std::uint8_t(int(index % 11) - 5);
            b[index] = std::uint8_t(int((index * 3) % 13) - 6);
        }

        std::ofstream element_events("element_events.csv");
        std::ofstream transaction_events("transaction_events.csv");
        std::ofstream timeline("timeline.csv");
        element_events << "supply_gap,max_length,global_element,matrix,matrix_element,ready_cycle,w_handshake_cycle,ready_to_handshake_cycles\n";
        transaction_events << "supply_gap,max_length,transaction,matrix,address,beats,AxLEN,begin_cycle,aw_cycle,first_w_cycle,last_w_cycle,b_cycle,response\n";
        timeline << "supply_gap,max_length,event,cycle\n";

        const std::array<unsigned, 4> gaps{0, 1, 3, 7};
        const std::array<unsigned, 2> lengths{1, 16};
        const std::array<std::array<std::uint64_t, 2>, 4> predictions{{
            {{204, 80}}, {{204, 136}}, {{270, 270}}, {{538, 538}}
        }};
        std::vector<Result> results;
        for (unsigned gap_index = 0; gap_index < gaps.size(); ++gap_index) {
            for (unsigned length_index = 0; length_index < lengths.size(); ++length_index) {
                auto result = run_case(bfm, dut, gaps[gap_index], lengths[length_index],
                                       a, b, element_events, transaction_events, timeline);
                if (result.pure_write != predictions[gap_index][length_index])
                    throw std::runtime_error("measured pure-write cycles differ from model");
                results.push_back(result);
            }
        }

        std::ofstream csv("comparison.csv");
        csv << "supply_gap,max_length,predicted_pure_write,measured_pure_write,write_transactions,w_beats,load_a,load_b,ready_check,load_with_ready,start_access,compute_cycles,done_poll,poll_reads,read_c,ack,end_to_end,repeat_task\n";
        for (unsigned index = 0; index < results.size(); ++index) {
            const auto& result = results[index];
            const auto predicted = predictions[index / 2][index % 2];
            csv << result.gap << ',' << result.length << ',' << predicted << ','
                << result.pure_write << ',' << result.transactions << ',' << result.beats
                << ',' << result.load_a << ',' << result.load_b << ',' << result.ready_check
                << ',' << result.load_with_ready << ',' << result.start_access << ','
                << result.compute_cycles << ',' << result.done_poll << ',' << result.poll_reads
                << ',' << result.read_c << ',' << result.ack << ',' << result.end_to_end
                << ',' << result.repeat_task << '\n';
        }

        std::ofstream summary("gap_comparison.csv");
        summary << "supply_gap,l1_pure_write,l16_pure_write,absolute_savings,speedup,l1_end_to_end,l16_end_to_end,end_to_end_savings,end_to_end_speedup\n";
        for (unsigned gap_index = 0; gap_index < gaps.size(); ++gap_index) {
            const auto& l1 = results[2 * gap_index];
            const auto& l16 = results[2 * gap_index + 1];
            summary << gaps[gap_index] << ',' << l1.pure_write << ',' << l16.pure_write
                    << ',' << (l1.pure_write - l16.pure_write) << ','
                    << (double(l1.pure_write) / l16.pure_write) << ','
                    << l1.end_to_end << ',' << l16.end_to_end << ','
                    << (l1.end_to_end - l16.end_to_end) << ','
                    << (double(l1.end_to_end) / l16.end_to_end) << '\n';
        }

        std::cout << "PASS Burst supply-gap scan: 8/8 configurations match model and golden\n";
        dut.final();
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        dut.final();
        return 1;
    }
}
