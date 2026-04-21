#!/usr/bin/env python3
"""
Golden-model checker for vending_ln simulation traces.

Inputs:
  - stimulus file lines: reset coin50 coin10 coin5 coin1 item
  - trace file lines   : cycle serviceTypeOut itemTypeOut out50 out10 out5 out1

Exit code:
  0 => all checks pass
  1 => at least one mismatch / invariant violation
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from typing import List, Tuple

SERVICE_OFF = 0
SERVICE_ON = 1
SERVICE_BUSY = 2

ITEM_NONE = 0
ITEM_A = 1
ITEM_B = 2
ITEM_C = 3


def sat_add3(a: int, b: int) -> int:
    return min(7, a + b)


def item_cost(item: int) -> int:
    if item == ITEM_A:
        return 8
    if item == ITEM_B:
        return 15
    if item == ITEM_C:
        return 22
    return 0


def coins_value(c50: int, c10: int, c5: int, c1: int) -> int:
    return c50 * 50 + c10 * 10 + c5 * 5 + c1


def read_stimulus(path: str) -> List[Tuple[int, int, int, int, int, int]]:
    rows: List[Tuple[int, int, int, int, int, int]] = []
    with open(path, "r", encoding="ascii") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            toks = line.split()
            if len(toks) != 6:
                raise ValueError(f"stimulus line {lineno}: expected 6 ints, got {len(toks)}")
            rows.append(tuple(int(x) for x in toks))  # type: ignore[arg-type]
    return rows


def read_trace(path: str) -> List[Tuple[int, int, int, int, int, int, int]]:
    rows: List[Tuple[int, int, int, int, int, int, int]] = []
    with open(path, "r", encoding="ascii") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            toks = line.split()
            if len(toks) != 7:
                raise ValueError(f"trace line {lineno}: expected 7 ints, got {len(toks)}")
            rows.append(tuple(int(x) for x in toks))  # type: ignore[arg-type]
    return rows


@dataclass
class Req:
    c50: int = 0
    c10: int = 0
    c5: int = 0
    c1: int = 0
    item: int = ITEM_NONE
    input_value: int = 0


@dataclass
class ModelState:
    service: int = SERVICE_ON
    item_out: int = ITEM_NONE
    out50: int = 0
    out10: int = 0
    out5: int = 0
    out1: int = 0
    cnt50: int = 2
    cnt10: int = 2
    cnt5: int = 2
    cnt1: int = 2
    prev50: int = 2
    prev10: int = 2
    prev5: int = 2
    prev1: int = 2
    req: Req = field(default_factory=Req)


def solve_change(target: int, cnt50: int, cnt10: int, cnt5: int, cnt1: int):
    for c50 in range(min(cnt50, target // 50), -1, -1):
        rem50 = target - c50 * 50
        for c10 in range(min(cnt10, rem50 // 10), -1, -1):
            rem10 = rem50 - c10 * 10
            for c5 in range(min(cnt5, rem10 // 5), -1, -1):
                rem5 = rem10 - c5 * 5
                if rem5 <= cnt1:
                    return True, c50, c10, c5, rem5
    return False, 0, 0, 0, 0


def step_model(
    st: ModelState, reset: int, c50: int, c10: int, c5: int, c1: int, item_in: int
) -> ModelState:
    if reset == 0:
        return ModelState()

    # Copy old state and mutate as sequential logic does.
    nxt = ModelState(
        service=st.service,
        item_out=st.item_out,
        out50=st.out50,
        out10=st.out10,
        out5=st.out5,
        out1=st.out1,
        cnt50=st.cnt50,
        cnt10=st.cnt10,
        cnt5=st.cnt5,
        cnt1=st.cnt1,
        prev50=st.prev50,
        prev10=st.prev10,
        prev5=st.prev5,
        prev1=st.prev1,
        req=Req(st.req.c50, st.req.c10, st.req.c5, st.req.c1, st.req.item, st.req.input_value),
    )

    if st.service == SERVICE_ON:
        nxt.out50 = nxt.out10 = nxt.out5 = nxt.out1 = 0
        nxt.item_out = ITEM_NONE
        nxt.service = SERVICE_ON

        if item_in != ITEM_NONE:
            nxt.prev50 = st.cnt50
            nxt.prev10 = st.cnt10
            nxt.prev5 = st.cnt5
            nxt.prev1 = st.cnt1

            nxt.req = Req(c50, c10, c5, c1, item_in, coins_value(c50, c10, c5, c1))

            nxt.cnt50 = sat_add3(st.cnt50, c50)
            nxt.cnt10 = sat_add3(st.cnt10, c10)
            nxt.cnt5 = sat_add3(st.cnt5, c5)
            nxt.cnt1 = sat_add3(st.cnt1, c1)

            nxt.service = SERVICE_BUSY

    elif st.service == SERVICE_BUSY:
        cost = item_cost(st.req.item)
        if st.req.input_value < cost:
            nxt.cnt50, nxt.cnt10, nxt.cnt5, nxt.cnt1 = st.prev50, st.prev10, st.prev5, st.prev1
            nxt.out50, nxt.out10, nxt.out5, nxt.out1 = st.req.c50, st.req.c10, st.req.c5, st.req.c1
            nxt.item_out = ITEM_NONE
            nxt.service = SERVICE_OFF
        else:
            target = st.req.input_value - cost
            ok, ch50, ch10, ch5, ch1 = solve_change(target, st.cnt50, st.cnt10, st.cnt5, st.cnt1)
            if ok:
                nxt.cnt50 = st.cnt50 - ch50
                nxt.cnt10 = st.cnt10 - ch10
                nxt.cnt5 = st.cnt5 - ch5
                nxt.cnt1 = st.cnt1 - ch1
                nxt.out50, nxt.out10, nxt.out5, nxt.out1 = ch50, ch10, ch5, ch1
                nxt.item_out = st.req.item
                nxt.service = SERVICE_OFF
            else:
                nxt.cnt50, nxt.cnt10, nxt.cnt5, nxt.cnt1 = st.prev50, st.prev10, st.prev5, st.prev1
                nxt.out50, nxt.out10, nxt.out5, nxt.out1 = st.req.c50, st.req.c10, st.req.c5, st.req.c1
                nxt.item_out = ITEM_NONE
                nxt.service = SERVICE_OFF
    else:
        nxt.out50 = nxt.out10 = nxt.out5 = nxt.out1 = 0
        nxt.item_out = ITEM_NONE
        nxt.service = SERVICE_ON

    return nxt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stim", required=True)
    parser.add_argument("--trace", required=True)
    args = parser.parse_args()

    stim = read_stimulus(args.stim)
    trace = read_trace(args.trace)

    if len(stim) != len(trace):
        print(f"CHECK_FAIL length mismatch: stim={len(stim)} trace={len(trace)}")
        return 1

    st = ModelState()
    fail_count = 0

    for idx, (s, t) in enumerate(zip(stim, trace)):
        reset, c50, c10, c5, c1, item_in = s
        cyc, service_o, item_o, out50, out10, out5, out1 = t
        if cyc != idx:
            print(f"CHECK_FAIL cycle index mismatch line={idx} trace_cycle={cyc}")
            fail_count += 1
            continue

        st = step_model(st, reset, c50, c10, c5, c1, item_in)

        exp = (st.service, st.item_out, st.out50, st.out10, st.out5, st.out1)
        got = (service_o, item_o, out50, out10, out5, out1)
        if exp != got:
            print(
                "CHECK_FAIL"
                f" cycle={idx}"
                f" stim={s}"
                f" exp(service,item,outs)={exp}"
                f" got={got}"
            )
            fail_count += 1

        # Explicit transaction invariants on SERVICE_OFF:
        # 1) Refund case (item_out=NONE): refund must equal inserted value.
        # 2) Success case: (change + item_cost) must equal inserted value.
        if service_o == SERVICE_OFF:
            out_value = out50 * 50 + out10 * 10 + out5 * 5 + out1
            inserted = st.req.input_value
            if item_o == ITEM_NONE:
                if out_value != inserted:
                    print(
                        "CHECK_FAIL"
                        f" cycle={idx}"
                        f" refund_mismatch out_value={out_value} inserted={inserted}"
                    )
                    fail_count += 1
            else:
                if out_value + item_cost(item_o) != inserted:
                    print(
                        "CHECK_FAIL"
                        f" cycle={idx}"
                        f" value_conservation_mismatch change={out_value}"
                        f" item_cost={item_cost(item_o)} inserted={inserted}"
                    )
                    fail_count += 1

    if fail_count:
        print(f"CHECK_FAIL total_mismatches={fail_count}")
        return 1

    print(f"CHECK_PASS cycles={len(stim)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
