#!/usr/bin/env python3
"""Assumption-based load-cycle model; no RTL, CPU, DDR, or DMA simulation."""
import argparse
import csv
from pathlib import Path


def chunks(words, length):
    return [min(length, words - x) for x in range(0, words, length)]


def data_phase(beats, master_gap, slave_gap):
    """Gap is idle cycles AFTER a handshake, inside this burst only.

    Both sides are ready for the first beat. Master retains the same beat
    whenever VALID=1 and READY=0. No gaps after the last beat are charged here.
    This is one explicit receiver-capacity model, not a general AXI simulator.
    """
    counts = dict(transfer=0, master_only=0, slave_only=0, both=0)
    master_wait = slave_wait = 0
    sent = 0
    stalled_beat = None
    while sent < beats:
        valid, ready = master_wait == 0, slave_wait == 0
        if stalled_beat is not None:
            if not valid or sent != stalled_beat:
                raise AssertionError("Master withdrew or changed a stalled beat")
        stalled_beat = sent if valid and not ready else None
        if valid and ready:
            counts["transfer"] += 1
            sent += 1
            master_wait, slave_wait = master_gap, slave_gap
        else:
            category = "slave_only" if valid else "master_only" if ready else "both"
            counts[category] += 1
            master_wait = max(0, master_wait - 1)
            slave_wait = max(0, slave_wait - 1)
    return counts


def predict(n, k, length, overhead, master_gap, slave_gap):
    if n < 1 or k < 1 or n*k > 1024 or n*n > 1024:
        raise ValueError("Shape must fit the current hardware's 4 KiB windows")
    if not 1 <= length <= 16 or min(overhead, master_gap, slave_gap) < 0:
        raise ValueError("Length must be 1..16; overhead and gaps must be nonnegative")
    # Never merge A's tail with B: these occupy separate address windows.
    groups = chunks(n*k, length) + chunks(n*k, length)
    counts = dict(transfer=0, master_only=0, slave_only=0, both=0)
    for size in groups:
        for key, value in data_phase(size, master_gap, slave_gap).items():
            counts[key] += value
    data_cycles = sum(counts.values())
    outside = len(groups)*overhead
    load = data_cycles + outside + 2
    return dict(n=n, k=k, length=length, master_gap=master_gap, slave_gap=slave_gap,
                overhead_per_burst=overhead, bursts=len(groups), beats=2*n*k,
                **counts, data_cycles=data_cycles, outside_data_cycles=outside,
                ready_check_cycles=2, load_cycles=load)


def self_test():
    checks = 0
    # Closed-form checks include unequal tail bursts and minimum shapes.
    for n, k in [(1, 1), (2, 2), (2, 17), (3, 5)]:
        for length in [1, 2, 4, 8, 16]:
            for mg in [0, 1, 3]:
                for sg in [0, 1, 2]:
                    r = predict(n, k, length, 2, mg, sg)
                    m = 2*((n*k+length-1)//length)
                    gaps = 2*n*k-m
                    expected = 2*n*k + gaps*max(mg, sg) + 2*m + 2
                    if r["load_cycles"] != expected or r["transfer"] != 2*n*k:
                        raise AssertionError("Cycle/beat conservation failed")
                    if r["both"] != gaps*min(mg, sg):
                        raise AssertionError("Overlapping waits double-counted")
                    checks += 1
    if [predict(2, 17, l, 2, 0, 0)["load_cycles"] for l in [1, 2, 4, 8, 16]] != [206,138,106,90,82]:
        raise AssertionError("Ideal reference example mismatch")
    print(f"PASS model self-test: {checks} parameter combinations + reference example")


def integer_list(text):
    return [int(x) for x in text.split(",")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n", type=int, default=2)
    parser.add_argument("--k", type=int, default=17)
    parser.add_argument("--lengths", type=integer_list, default=[1,2,4,8,16])
    parser.add_argument("--master-gaps", type=integer_list, default=[0,1,3])
    parser.add_argument("--slave-gaps", type=integer_list, default=[0,1])
    parser.add_argument("--overhead", type=int, default=2,
                        help="All non-data cycles per burst, including address/response/gaps")
    parser.add_argument("--non-load-cycles", type=int, default=None,
                        help="Optional fixed non-load cost; 38 for the measured N2/K17 baseline")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent/"burst_load_predictions.csv")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    if args.non_load_cycles is not None and args.non_load_cycles < 0:
        parser.error("non-load cost must be nonnegative")
    rows = []
    try:
        for length in args.lengths:
            for mg in args.master_gaps:
                for sg in args.slave_gaps:
                    r = predict(args.n, args.k, length, args.overhead, mg, sg)
                    # Lite value is a formula calibrated to the existing blocking
                    # BFM (3 cycles/write + 2 cycles/status). Not a new RTL run.
                    reference = 6*args.n*args.k + 2
                    r.update(evidence="MODEL_PREDICTION", lite_reference_cycles=reference,
                             load_speedup=round(reference/r["load_cycles"], 6),
                             useful_bytes_per_cycle=round(2*args.n*args.k/r["load_cycles"], 6),
                             non_load_assumption=args.non_load_cycles,
                             total_cycles_prediction=(r["load_cycles"]+args.non_load_cycles
                                                      if args.non_load_cycles is not None else None))
                    rows.append(r)
    except ValueError as e:
        parser.error(str(e))
    if not rows:
        parser.error("sweep must contain at least one combination")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} MODEL_PREDICTION rows to {args.output}")
    for r in rows:
        if r["master_gap"] == 0 and r["slave_gap"] == 0:
            print(f"L={r['length']:2}: bursts={r['bursts']:2}, predicted load={r['load_cycles']}")


if __name__ == "__main__":
    main()
