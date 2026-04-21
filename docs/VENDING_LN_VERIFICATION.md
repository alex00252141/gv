# Vending machine RTL + correctness verification (LN)

This note documents how to verify the `vending_ln.v` implementation from the provided spec.

## 1) What is implemented

`designs/SoCV/vending/vending_ln.v` implements a 3-state FSM:

- `SERVICE_ON`: accept request only when `itemTypeIn != ITEM_NONE`
- `SERVICE_BUSY`: compute result for the accepted request
- `SERVICE_OFF`: present output for one cycle, then return to `SERVICE_ON`

Key spec behaviors implemented:

- Reset initializes machine to `SERVICE_ON` with 2 coins of each denomination.
- Input/output coin limits are respected (2-bit inputs, 3-bit outputs/stored counts).
- Coin storage saturates at 7.
- If input money is insufficient, output no item and refund inserted coins.
- If change cannot be composed from stored coins, output no item and refund inserted coins.
- Otherwise output requested item and exact change.
- No request is accepted unless machine is in `SERVICE_ON`.

## 2) How correctness is checked

Correctness is validated by cycle-accurate differential checking:

1. `scripts/gen_vending_ln_cases.py` generates:
   - directed corner cases
   - constrained-random request traffic
2. `testbench/vending_ln_tb.v` simulates RTL and records outputs per cycle.
3. `scripts/check_vending_ln_trace.py` runs an independent golden model and compares:
   - `serviceTypeOut`
   - `itemTypeOut`
   - all output coin counts

Additionally, checker enforces transaction-level value conservation on every `SERVICE_OFF` cycle:

- refund case (`itemTypeOut == ITEM_NONE`): refunded value == inserted value
- success case: `change value + item cost == inserted value`

## 3) Reproduce

Compile:

- `iverilog -g2012 -s vending_ln_tb -o /tmp/vending_ln_tb.out testbench/vending_ln_tb.v designs/SoCV/vending/vending_ln.v`

Run one regression:

- `python3 scripts/gen_vending_ln_cases.py --out /tmp/vending_ln.stim --cycles 1200 --seed 1337`
- `vvp /tmp/vending_ln_tb.out +stim=/tmp/vending_ln.stim +out=/tmp/vending_ln.trace`
- `python3 scripts/check_vending_ln_trace.py --stim /tmp/vending_ln.stim --trace /tmp/vending_ln.trace`

Expected checker output:

- `CHECK_PASS cycles=<N>`
