#!/usr/bin/env python3
"""Predict readback sensitivity, calibrated against the reported RTL benchmark.

Model clock edges explicitly at the transaction level, without modeling PE data.
All accelerated readback modes are hypothetical interfaces. Only the reported
baseline cycle counts are RTL observations.
"""
import argparse
import csv
import sys

SHAPES = {
    (2, 2): (559, 464, 28, 23, 19, 0, 0),
    (8, 8): (3919, 3254, 196, 161, 361, 228, 76),
    (16, 64): (23839, 12914, 1192, 617, 1577, 8132, 4028),
    (32, 32): (54559, 43634, 2728, 2153, 1577, 8132, 4028),
}
MODES = (("lite", 1, 2), ("1_per_cycle", 1, 1),
         ("2_per_cycle", 2, 1), ("4_per_cycle", 4, 1))


def input_bursts(n, k):
    words = (n * k + 3) // 4
    return [min(16, words - base) for base in range(0, words, 16)] * 2


def simulate(n, k, tasks, dual, mode):
    _, lanes, spacing = mode
    bursts = input_bursts(n, k)
    input_span = sum(beats + 2 for beats in bursts)  # AW, W beats, B
    core_run = k + 2 * n - 2
    result_beats = (n * n + lanes - 1) // lanes
    start = input_span + 1  # First Burst AW at edge 0.
    start_times = []
    core_writes = done_writes = response_writes = ack_wait = input_wait = 0

    for task in range(tasks):
        start_times.append(start)
        done = start + core_run + 2
        first_response = done + 5
        last_response = first_response + spacing * (result_beats - 1)
        ack_request = last_response + 1
        ack = ack_request + 1
        if task == tasks - 1:
            break
        if not dual:
            start = ack + 2 + input_span + 1
            continue

        # Launch each Burst as early as allowed after the current START.
        # Once ACK is requested, give it the next free write slot. A Burst
        # which already owns the port holds it through its B handshake.
        free = start + 2
        ack_sent = False
        for beats in bursts:
            if not ack_sent and free >= ack_request:
                ack = free + 1
                free += 3  # ACK AW/W, Device commit, B.
                ack_sent = True
            for edge in range(free + 1, free + 1 + beats):
                core_writes += start + 2 <= edge < done
                done_writes += edge > done and (not ack_sent or edge <= ack)
                response_writes += (
                    first_response <= edge <= last_response
                    and (edge - first_response) % spacing == 0
                )
            free += beats + 2
        if not ack_sent:
            ack = max(ack_request, free) + 1
        ack_wait += ack - (ack_request + 1)
        next_start = max(ack + 4, free + 1)
        input_wait += next_start - (ack + 4)
        start = next_start

    return {
        "cycles": ack + 1,  # Inclusive first AW through final Device ACK.
        "mean_ii": (start_times[-1] - start_times[0]) / (tasks - 1),
        "core_writes": core_writes,
        "done_writes": done_writes,
        "response_writes": response_writes,
        "ack_wait": ack_wait,
        "input_wait": input_wait,
    }


def validate():
    for (n, k), expected in SHAPES.items():
        single = simulate(n, k, 20, False, MODES[0])
        dual = simulate(n, k, 20, True, MODES[0])
        actual = (single["cycles"], dual["cycles"],
                  single["mean_ii"], dual["mean_ii"], dual["core_writes"],
                  dual["done_writes"], dual["response_writes"])
        if actual != expected:
            raise ValueError(f"N={n}, K={k}: model {actual}, reported {expected}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tasks", type=int, default=20)
    args = parser.parse_args()
    if args.tasks < 2:
        parser.error("--tasks must be at least 2")
    validate()
    writer = csv.writer(sys.stdout)
    writer.writerow(("n", "k", "mode", "single_cycles", "dual_cycles",
                     "dual_vs_lite", "single_vs_dual", "dual_mean_ii",
                     "dual_ack_wait_avg", "dual_input_wait_after_ack_avg"))
    for n, k in SHAPES:
        baseline = simulate(n, k, args.tasks, True, MODES[0])["cycles"]
        for mode in MODES:
            single = simulate(n, k, args.tasks, False, mode)
            dual = simulate(n, k, args.tasks, True, mode)
            writer.writerow((
                n, k, mode[0], single["cycles"], dual["cycles"],
                f'{baseline / dual["cycles"]:.4f}',
                f'{single["cycles"] / dual["cycles"]:.4f}',
                f'{dual["mean_ii"]:.2f}',
                f'{dual["ack_wait"] / (args.tasks - 1):.2f}',
                f'{dual["input_wait"] / (args.tasks - 1):.2f}',
            ))


if __name__ == "__main__":
    main()
