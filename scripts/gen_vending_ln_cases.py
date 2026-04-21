#!/usr/bin/env python3
"""
Generate constrained-random + directed stimuli for vending_ln verification.

Each line in output file:
    reset coin50 coin10 coin5 coin1 item
"""

from __future__ import annotations

import argparse
import random


def build_cases(num_random: int, seed: int) -> list[tuple[int, int, int, int, int, int]]:
    rng = random.Random(seed)
    cases: list[tuple[int, int, int, int, int, int]] = []

    # Initial reset pulse to initialize machine inventory.
    cases.append((0, 0, 0, 0, 0, 0))
    cases.append((1, 0, 0, 0, 0, 0))

    # Directed sanity cases.
    # 1) successful ITEM_A with exact amount (5 + 1 + 1 + 1 = 8)
    cases.append((1, 0, 0, 1, 3, 1))
    cases.extend([(1, 0, 0, 0, 0, 0)] * 3)

    # 2) insufficient amount for ITEM_C (should refund all inserted coins)
    cases.append((1, 0, 1, 0, 1, 3))  # 11 < 22
    cases.extend([(1, 0, 0, 0, 0, 0)] * 3)

    # 3) input with ITEM_NONE should be ignored.
    cases.append((1, 3, 3, 3, 3, 0))
    cases.extend([(1, 0, 0, 0, 0, 0)] * 2)

    # 4) drain 1-dollar coins, then require unavailable change:
    #    two successful ITEM_A purchases using a 10-dollar coin consume four 1-dollar coins
    #    (machine starts with only two and must refill from inserted coins if available),
    #    then another 10-dollar ITEM_A request should eventually hit refund path once
    #    exact change cannot be composed.
    cases.append((1, 0, 1, 0, 0, 1))
    cases.extend([(1, 0, 0, 0, 0, 0)] * 3)
    cases.append((1, 0, 1, 0, 0, 1))
    cases.extend([(1, 0, 0, 0, 0, 0)] * 3)
    cases.append((1, 0, 1, 0, 0, 1))
    cases.extend([(1, 0, 0, 0, 0, 0)] * 3)

    # Constrained random traffic.
    for _ in range(num_random):
        # Keep reset deasserted after init sequence.
        reset = 1

        # Majority idle cycles, occasional request cycles.
        if rng.random() < 0.6:
            item = 0
            c50 = c10 = c5 = c1 = 0
        else:
            item = rng.randint(1, 3)
            c50 = rng.randint(0, 3)
            c10 = rng.randint(0, 3)
            c5 = rng.randint(0, 3)
            c1 = rng.randint(0, 3)
        cases.append((reset, c50, c10, c5, c1, item))

    return cases


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=20260421)
    parser.add_argument("--cycles", type=int, default=600)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    rows = build_cases(num_random=args.cycles, seed=args.seed)
    with open(args.out, "w", encoding="ascii") as f:
        for row in rows:
            f.write("%d %d %d %d %d %d\n" % row)

    print(f"WROTE {len(rows)} cycles to {args.out}")


if __name__ == "__main__":
    main()
