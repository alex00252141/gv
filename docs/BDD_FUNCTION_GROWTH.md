# BDD growth study on different Boolean functions

This note demonstrates how to build BDDs programmatically (instead of long dofiles), and how node count grows with input size.

## Program used

Implemented in:

- `tests/bdd/bdd_function_growth.cpp`

Build and run:

- `g++ -std=c++14 -O2 tests/bdd/bdd_function_growth.cpp src/bdd/bddMgrV.cpp src/bdd/bddNodeV.cpp src/util/myString.cpp -Isrc/bdd -Isrc/util -Isrc -o /tmp/bdd_function_growth`
- `/tmp/bdd_function_growth`

The program constructs ROBDDs for:

- n-bit ripple adder (`a + b`), measuring all output bits.
- n x n multiplier (`a * b`), measuring all output bits.
- Counter transition relation (`next = state + 1 mod 2^n`).
- Random SOP logic (3n random cubes, deterministic seed).
- Parity/XOR chain (as an additional canonical function family).

Variable ordering used:

- Arithmetic and counter: interleaved LSB-first (`a0, b0, a1, b1, ...`).
- Parity and random logic: linear (`x0, x1, ..., x(n-1)`).

## Measured node counts

### Adder (n-bit ripple, outputs = n sum bits + carry)

| n | nodes |
|---:|---:|
| 2 | 11 |
| 4 | 34 |
| 6 | 69 |
| 8 | 116 |
| 10 | 175 |
| 12 | 246 |
| 14 | 329 |
| 16 | 424 |
| 18 | 531 |
| 20 | 650 |
| 22 | 781 |
| 24 | 924 |

Observed growth: roughly quadratic over all output bits in this setup.

### Multiplier (n x n, outputs = 2n bits)

| n | nodes |
|---:|---:|
| 2 | 14 |
| 3 | 51 |
| 4 | 171 |
| 5 | 551 |
| 6 | 1709 |
| 7 | 5397 |

Observed growth: fast exponential trend in this experiment.

### Counter relation (next = state + 1 mod 2^n)

| n | nodes |
|---:|---:|
| 2 | 6 |
| 4 | 16 |
| 6 | 26 |
| 8 | 36 |
| 10 | 46 |
| 12 | 56 |
| 14 | 66 |
| 16 | 76 |
| 18 | 86 |
| 20 | 96 |
| 22 | 106 |
| 24 | 116 |

Observed growth: linear.

### Parity (xor of n inputs)

| n | nodes |
|---:|---:|
| 4 | 5 |
| 8 | 9 |
| 12 | 13 |
| 16 | 17 |
| 20 | 21 |
| 24 | 25 |
| 28 | 29 |
| 32 | 33 |
| 36 | 37 |
| 40 | 41 |
| 44 | 45 |
| 48 | 49 |
| 52 | 53 |
| 56 | 57 |
| 60 | 61 |
| 64 | 65 |

Observed growth: linear, approximately `n + 1`.

### Random SOP logic (3n random cubes)

| n | nodes |
|---:|---:|
| 4 | 1 |
| 6 | 10 |
| 8 | 53 |
| 10 | 129 |
| 12 | 262 |
| 14 | 514 |
| 16 | 775 |
| 18 | 1045 |
| 20 | 1434 |
| 22 | 1665 |
| 24 | 2280 |

Observed growth: superlinear and irregular; depends heavily on random structure and variable order.

## Complexity discussion

For ROBDDs, complexity is usually discussed in terms of node count `|BDD(f)|`.

- **Worst case (any function)**: `|BDD(f)| = O(2^n)`.
- **Best/structured cases**: often polynomial, sometimes linear.

For the tested families (under this variable order):

- **Adder**: polynomial (empirically near quadratic when counting all output bits together in this implementation).
- **Multiplier**: typically exponential for common fixed orders; this run shows a clear exponential trend.
- **Counter relation (`next = state + 1`)**: linear growth.
- **Parity**: linear growth.
- **Random SOP**: usually hard to compress at larger n; often trends toward exponential behavior in worst case.

## Key takeaways

1. BDD size is dominated by **function structure + variable ordering**.
2. Arithmetic does not imply the same complexity: adders can stay compact while multipliers can explode.
3. Programmatic generation (as done in `bdd_function_growth.cpp`) is much easier to scale than hand-written dofiles.
