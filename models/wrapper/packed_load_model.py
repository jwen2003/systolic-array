#!/usr/bin/env python3
"""Analytical packed load prediction; no DUT/BFM imports.
Assumes word-aligned dense INT8 packing, separate A/B bursts, continuous W,
single outstanding, immediate Device commit, AW then data then B (H=2).
"""
import argparse
import csv
import json


def predict(n, k, length):
    if min(n, k, length) < 1 or length > 16:
        raise ValueError('positive shape and Burst length 1..16 required')
    words_per_matrix = (n*k + 3)//4
    beats = 2*words_per_matrix
    bursts = 2*((words_per_matrix+length-1)//length)
    transaction_done = beats + 2*bursts
    return dict(beats=beats, bursts=bursts,
                last_commit_cycles=transaction_done-1,
                write_complete_cycles=transaction_done,
                confirmed_load_cycles=transaction_done+2)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--n', type=int, default=2)
    p.add_argument('--k', type=int, default=17)
    p.add_argument('--length', type=int, default=16)
    p.add_argument('--check-csv', nargs='+')
    args = p.parse_args()
    if args.check_csv:
        rows = 0
        for path in args.check_csv:
            with open(path, newline='') as f:
                for row in csv.DictReader(f):
                    pred = predict(int(row['n']), int(row['k']), int(row['length']))
                    for key, value in pred.items():
                        if int(row[key]) != value:
                            raise SystemExit(f'{path}: {key}: measured={row[key]}, predicted={value}')
                    rows += 1
        print(f'PASS independent packed model: {rows} RTL rows')
    else:
        print(json.dumps(predict(args.n, args.k, args.length), indent=2))


if __name__ == '__main__':
    main()
