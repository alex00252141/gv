# MiniSat Study Notes

MiniSat is small enough to read end-to-end, but it still contains the core ideas from a modern
CDCL SAT solver. This repository keeps the MiniSat-derived implementation in
`satsolvers/minisat/` and wraps it for GV through `src/sat/MinisatMgr`.

## How the lecture ideas appear in code

- **Variables, literals, and clauses.** `SolverTypes.h` represents a variable as an integer and a
  literal as `2 * var + sign`, which makes negation a cheap bit flip. Clauses are packed into a
  compact allocation with literal data followed by optional activity/proof fields.
- **Boolean constraint propagation.** `SolverV::propagate()` implements the two-watched-literal
  scheme from the lecture notes. Each falsified literal only visits clauses watching that literal,
  searches for a replacement watch, and otherwise either enqueues the other watched literal or
  reports a conflict.
- **Decision ordering.** `VarOrder` keeps a heap ordered by variable activity. Conflict analysis
  bumps variable activity (`varBumpActivity()`), then decay gradually forgets older conflicts, which
  is MiniSat's VSIDS-style dynamic ordering.
- **Conflict analysis and learning.** `SolverV::analyze()` derives a learnt clause by walking the
  implication graph back from a conflict. It produces an asserting clause and a backtrack level, so
  `search()` can do non-chronological backtracking and add the new clause to the learnt database.
- **Restarts and learnt database management.** `SolverV::solve()` repeatedly calls `search()` with
  growing conflict and learnt-clause budgets. At decision level 0 it simplifies the database, and
  `reduceDB()` removes low-activity learnt clauses when the learnt set grows.
- **Incremental SAT in GV.** `MinisatMgr` exposes assumptions (`assumeProperty()`), assertions
  (`assertProperty()`), and circuit-to-CNF encoding (`add_AND_Formula()`, etc.). Verification code
  can reuse the same solver state while changing assumptions, matching the lecture note's
  observation that learnt constraints can be shared across related properties.

## GV command added

`SATSolve DIMACS` now accepts an optional conflict budget:

```text
SATSolve DIMACS -File <dimacs.cnf> [-ConflictMax <non-negative integer>]
```

Without `-ConflictMax`, behavior is unchanged. With the option, GV calls MiniSat's bounded search
and reports `UNKNOWN` if the conflict budget is exhausted before proving `SAT` or `UNSAT`. This is a
simple proof-effort control useful for experimenting with MiniSat's restart/search behavior.
