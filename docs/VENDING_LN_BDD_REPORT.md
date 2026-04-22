# Vending Machine BDD Verification Report (LN)

## 1) Objective

Use the in-repo BDD assertion checker flow to verify vending-machine safety properties.

Because direct BDD proof on the full vending RTL suffers transition-relation blow-up,
the process includes abstraction/refinement and then proves properties on the refined abstract model.

## 2) BDD engine status (implementation + sanity check)

The BDD proof core in `src/prove/proveBdd.cpp` is now implemented:

- initial-state construction (`pinit`)
- transition relation construction (`ptrans`)
- image/reachability fixed-point (`pimage`)
- monitor check over reached set (`pcheckp`)
- `Y -> X` next-state renaming helper

Sanity check on built-in benchmark:

- dofile: `tests/full/prove/dofile/prove_bdd.dofile`
- result: fixed point reached; all monitors safe.

## 3) Why full vending model was not directly provable

Observation for `designs/SoCV/vending/vending-simple.v`:

- PI=12, PO=17, LATCH=48, AIG=3085
- BDD flow stalls at `ptrans tri tr` (bounded 90s probe)

This indicates transition relation BDD construction dominates cost and triggers memory/time explosion
before image iteration.

## 4) Abstraction/refinement path

### 4.1 First abstraction attempt

`designs/SoCV/vending/vending_ln_bdd_abs.v` (reduced coin types and arithmetic width) still stalled at `ptrans`.

### 4.2 Refined abstraction (successful)

`designs/SoCV/vending/vending_ln_bdd_abs2.v`:

- single request bit (`reqValid`)
- single item type (cost=1 token)
- single 2-bit token coin bucket (0..3) with saturating storage
- keeps protocol states `ON/BUSY/OFF`
- keeps rollback/refund and success value-conservation semantics

BDD dofile:

- `tests/full/prove/dofile/vending_ln_bdd_abs2.dofile`

Run result:

- fixed point reached at time/frame 11
- all bad monitors proven safe

## 5) Proven properties (AG(~bad_i))

In `vending_ln_bdd_abs2.v`, these outputs are monitored:

1. `bad_state_encoding`  
   Service state is always one of `OFF/ON/BUSY`.
2. `bad_output_protocol`  
   Outside `OFF`, outputs must be quiescent (`coinOut=0`, `itemOut=0`).
3. `bad_refund_value`  
   In refund branch (`OFF && !itemOut`), refunded amount equals inserted amount.
4. `bad_success_value`  
   In success branch (`OFF && itemOut`), `change + item_cost == inserted`.
5. `bad_storage_conservation`  
   Refund branch: storage rolls back to previous value.  
   Success branch: `storage_after + change == storage_after_insert`.

Each property is checked by `pcheckp -o <idx>` and reported safe.

## 6) Soundness / conclusion notes

- This is an **under-approximation / abstraction** of the original vending design.
- Therefore, proved safety here is strong evidence for control/data invariant design intent,
  but not a complete proof of the full concrete RTL.
- No violated monitor was observed in the refined abstraction run.
- Since no counterexample exists in this abstraction run, there is no spurious CEX to refine.

To further tighten confidence toward the concrete RTL, next refinements can gradually reintroduce:

- separate 5/1 coin buckets instead of one token bucket
- larger storage width
- multiple item costs

while keeping `ptrans` tractable.
