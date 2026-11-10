#include "axi_burst_bfm.hpp"
#include "Vsystolic_axi_burst_top.h"
#include "Vsystolic_axi_burst_top___024root.h"
#include "verilated.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr std::uint32_t STATUS = 0x0008;
constexpr std::uint32_t COMMAND = 0x0004;
constexpr std::uint32_t ACK = 0x000c;
constexpr std::uint32_t A_BASE = 0x1000;
constexpr std::uint32_t B_BASE = 0x2000;
constexpr std::uint32_t C_BASE = 0x3000;
constexpr std::uint32_t A_PACKED_BASE = 0x4000;
constexpr std::uint32_t B_PACKED_BASE = 0x5000;
constexpr unsigned N = 2;
constexpr unsigned K = 17;
constexpr unsigned MAX_BURST = 16;

struct PackedWords {
    std::vector<std::uint32_t> data;
    std::vector<std::uint8_t> strobes;
};

struct Result {
    std::string mode;
    std::uint64_t load_a = 0;
    std::uint64_t load_b = 0;
    std::uint64_t write_total = 0;
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
    std::uint64_t write_transactions = 0;
    std::uint64_t write_beats = 0;
    std::vector<std::int32_t> outputs;
};

PackedWords pack_bytes(const std::vector<std::uint32_t>& values) {
    PackedWords result;
    for (std::size_t index = 0; index < values.size(); index += 4) {
        std::uint32_t word = 0;
        std::uint8_t strobe = 0;
        for (std::size_t lane = 0; lane < 4 && index + lane < values.size(); ++lane) {
            word |= (values[index + lane] & 0xffu) << (8 * lane);
            strobe |= std::uint8_t(1u << lane);
        }
        result.data.push_back(word);
        result.strobes.push_back(strobe);
    }
    return result;
}

std::int64_t signed_byte(std::uint32_t value) {
    return std::int64_t(std::int8_t(value & 0xffu));
}

std::int32_t signed_accumulator(std::uint32_t value) {
    value &= 0x3ffffu;
    return (value & 0x20000u) ? std::int32_t(value) - 0x40000 : std::int32_t(value);
}

std::int32_t golden(const std::vector<std::uint32_t>& a,
                    const std::vector<std::uint32_t>& b,
                    unsigned row, unsigned column) {
    std::int64_t sum = 0;
    for (unsigned inner = 0; inner < K; ++inner) {
        sum += signed_byte(a[row * K + inner]) * signed_byte(b[inner * N + column]);
    }
    return std::int32_t(((sum + 131072) % 262144 + 262144) % 262144 - 131072);
}

std::string strobes_text(const std::vector<std::uint8_t>& strobes) {
    std::string result;
    for (std::size_t index = 0; index < strobes.size(); ++index) {
        if (index) result += ';';
        result += "0x";
        constexpr char hex[] = "0123456789abcdef";
        result += hex[strobes[index] & 0xfu];
    }
    return result;
}

Result run_mode(AxiBurstBfm& bfm, Vsystolic_axi_burst_top& dut,
                bool packed, const std::vector<std::uint32_t>& a,
                const std::vector<std::uint32_t>& b,
                std::ofstream& events, std::ofstream& timeline) {
    bfm.reset();
    Result result;
    result.mode = packed ? "PACKED" : "UNPACKED";
    std::uint64_t accepted_start = 0;
    std::uint64_t visible_done = 0;
    bfm.set_cycle_observer([&](std::uint64_t cycle) {
        if (dut.rootp->systolic_axi_burst_top__DOT__core_start) accepted_start = cycle;
        if (dut.rootp->systolic_axi_burst_top__DOT__core_done) visible_done = cycle;
    });

    const auto first_request = bfm.cycles();
    auto phase = first_request;
    unsigned transaction_index = 0;

    auto write_transaction = [&](const char* matrix, std::uint32_t address,
                                 const std::vector<std::uint32_t>& words,
                                 const std::vector<std::uint8_t>& strobes) {
        const auto begin = bfm.cycles();
        const auto metrics = bfm.burst_write(address, words, 0, 0, strobes);
        if (metrics.transfer != words.size() || metrics.master_only ||
            metrics.slave_only || metrics.both) {
            throw std::runtime_error("non-continuous write transfer");
        }
        events << result.mode << ',' << matrix << ',' << transaction_index++
               << ",0x" << std::hex << address << std::dec
               << ',' << words.size() << ',' << (words.size() - 1)
               << ',' << (begin + 1) << ',' << (begin + 2)
               << ',' << metrics.last_transfer_cycle << ',' << bfm.cycles()
               << ',' << metrics.last_transfer_cycle << ','
               << strobes_text(strobes) << ",OKAY\n";
        ++result.write_transactions;
        result.write_beats += words.size();
    };

    auto load_matrix = [&](const char* matrix, std::uint32_t normal_base,
                           std::uint32_t packed_base,
                           const std::vector<std::uint32_t>& values) {
        if (packed) {
            const auto payload = pack_bytes(values);
            write_transaction(matrix, packed_base, payload.data, payload.strobes);
        } else {
            for (std::size_t index = 0; index < values.size(); index += MAX_BURST) {
                const auto stop = std::min(index + MAX_BURST, values.size());
                std::vector<std::uint32_t> words(values.begin() + index, values.begin() + stop);
                std::vector<std::uint8_t> strobes(words.size(), 0x1);
                write_transaction(matrix, normal_base + 4 * std::uint32_t(index), words, strobes);
            }
        }
    };

    load_matrix("A", A_BASE, A_PACKED_BASE, a);
    result.load_a = bfm.cycles() - phase;
    phase = bfm.cycles();
    load_matrix("B", B_BASE, B_PACKED_BASE, b);
    result.load_b = bfm.cycles() - phase;
    result.write_total = result.load_a + result.load_b;
    phase = bfm.cycles();
    if (bfm.axi_read(STATUS) != 4) throw std::runtime_error("inputs not ready");
    result.ready_check = bfm.cycles() - phase;
    result.load_with_ready = bfm.cycles() - first_request;

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
        for (unsigned column = 0; column < N; ++column) {
            const auto actual = signed_accumulator(bfm.axi_read(C_BASE + 4 * (row * N + column)));
            const auto expected = golden(a, b, row, column);
            if (actual != expected) throw std::runtime_error("independent golden mismatch");
            result.outputs.push_back(actual);
        }
    }
    result.read_c = bfm.cycles() - phase;
    result.end_to_end = bfm.cycles() - first_request;
    phase = bfm.cycles();
    bfm.axi_write(ACK, 1, 1);
    result.ack = bfm.cycles() - phase;
    result.repeat_task = bfm.cycles() - first_request;
    if (bfm.axi_read(STATUS) != 0) throw std::runtime_error("ACK did not restore LOAD state");

    result.start_edge = accepted_start;
    result.done_edge = visible_done;
    if (!accepted_start || !visible_done || visible_done <= accepted_start) {
        throw std::runtime_error("missing START/DONE event");
    }
    result.compute_cycles = visible_done - accepted_start;
    timeline << result.mode << ",first_request," << first_request << '\n'
             << result.mode << ",writes_complete," << first_request + result.write_total << '\n'
             << result.mode << ",ready_check_complete," << first_request + result.load_with_ready << '\n'
             << result.mode << ",device_start," << accepted_start << '\n'
             << result.mode << ",device_done," << visible_done << '\n'
             << result.mode << ",last_c_response," << first_request + result.end_to_end << '\n'
             << result.mode << ",ack_complete," << first_request + result.repeat_task << '\n';
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
        std::vector<std::uint32_t> a(N * K), b(N * K);
        for (unsigned index = 0; index < N * K; ++index) {
            a[index] = std::uint8_t(int((index * 7) % 251) - 125);
            b[index] = std::uint8_t(int((index * 13) % 253) - 126);
        }
        std::ofstream events("transaction_events.csv");
        std::ofstream timeline("timeline.csv");
        events << "mode,matrix,transaction,address,beats,AxLEN,aw_cycle,first_w_cycle,last_w_cycle,b_cycle,wlast_cycle,wstrb,response\n";
        timeline << "mode,event,cycle\n";
        const auto unpacked = run_mode(bfm, dut, false, a, b, events, timeline);
        const auto packed = run_mode(bfm, dut, true, a, b, events, timeline);
        if (unpacked.compute_cycles != packed.compute_cycles) {
            throw std::runtime_error("compute windows differ");
        }
        if (unpacked.outputs != packed.outputs) {
            throw std::runtime_error("packed and unpacked results differ");
        }
        std::ofstream results("comparison.csv");
        results << "mode,write_transactions,write_beats,load_a,load_b,pure_write,ready_check,load_with_ready,start_access,start_cycle,done_cycle,compute_cycles,done_poll,poll_reads,read_c,ack,end_to_end,repeat_task,useful_input_bytes_per_write_cycle\n";
        for (const auto* result : {&unpacked, &packed}) {
            results << result->mode << ',' << result->write_transactions << ',' << result->write_beats
                    << ',' << result->load_a << ',' << result->load_b << ',' << result->write_total
                    << ',' << result->ready_check << ',' << result->load_with_ready
                    << ',' << result->start_access << ',' << result->start_edge << ',' << result->done_edge
                    << ',' << result->compute_cycles << ',' << result->done_poll << ',' << result->poll_reads
                    << ',' << result->read_c << ',' << result->ack << ',' << result->end_to_end
                    << ',' << result->repeat_task << ',' << (68.0 / result->write_total) << '\n';
        }
        std::ofstream prediction("prediction_vs_measurement.csv");
        prediction << "mode,predicted_pure_write,measured_pure_write,predicted_end_to_end,measured_end_to_end,delta\n"
                   << "UNPACKED,80," << unpacked.write_total << ",115," << unpacked.end_to_end << ',' << (std::int64_t(unpacked.end_to_end)-115) << '\n'
                   << "PACKED,22," << packed.write_total << ",57," << packed.end_to_end << ',' << (std::int64_t(packed.end_to_end)-57) << '\n';
        std::cout << "PASS controlled packed vs unpacked: unpacked=" << unpacked.end_to_end
                  << " packed=" << packed.end_to_end << " cycles\n";
        dut.final();
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        dut.final();
        return 1;
    }
}
