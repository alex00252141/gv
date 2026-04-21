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

## 2.1) Embedded RTL assertions (internal visibility)

The design also contains a non-synthesis assertion block (guarded by ``ifndef SYNTHESIS``)
to catch internal bugs earlier than output-only checking:

- legal encoding / no-X checks for key state and data signals
- reset-value checks
- state transition protocol checks (`ON -> BUSY -> OFF -> ON`)
- request-capture integrity checks on accepted requests
- quiescent output checks in `SERVICE_ON` and `SERVICE_BUSY`
- value-conservation and denomination-conservation checks in `SERVICE_OFF`

These assertions are simulation-time checks and do not alter synthesized logic.

Optional GV-style hook:

- compile with ``define VENDING_ASSERT_PO`` to expose `assertionFail` as an output pin.
- this allows tools that reason through PO visibility to monitor assertion status.

## 3) Reproduce

Compile:

- `iverilog -g2012 -s vending_ln_tb -o /tmp/vending_ln_tb.out testbench/vending_ln_tb.v designs/SoCV/vending/vending_ln.v`

Run one regression:

- `python3 scripts/gen_vending_ln_cases.py --out /tmp/vending_ln.stim --cycles 1200 --seed 1337`
- `vvp /tmp/vending_ln_tb.out +stim=/tmp/vending_ln.stim +out=/tmp/vending_ln.trace`
- `python3 scripts/check_vending_ln_trace.py --stim /tmp/vending_ln.stim --trace /tmp/vending_ln.trace`

Expected checker output:

- `CHECK_PASS cycles=<N>`

## 4) Learning notes (assertion exercise reflection)

- **Was it easy to write assertions?**  
  Moderately easy for high-level protocol rules (state encodings and transitions), but harder for
  request-capture and denomination-level conservation because those need internal history/context.
  I had to add explicit previous-cycle sampled signals in the assertion block for robust checks.

- **Did assertions help reveal bugs?**  
  Yes, they exposed potential **verification holes** that output-only checking can miss:
  weak upper-bound inventory checks (`<=`) and missing exact denomination checks in refund/success paths.
  Tightening assertions to exact conservation relations closed these holes.

- **Did I need to revise RTL and re-verify?**  
  The core datapath/behavioral RTL did not require functional changes, but the design file was revised
  to include a stronger internal assertion suite (including X-detection and request-capture integrity).
  After adding assertions, I re-ran directed and multi-seed random regressions; all checks passed.
