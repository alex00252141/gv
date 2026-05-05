# Graph Coloring SAT Experiment

This example explores GV's embedded MiniSat solver through the DIMACS command:

```text
gv> SATSolve DIMACS -File <dimacs-file> -Stats
```

The helper script `scripts/sat_graph_coloring_experiment.py` translates graph
`k`-colorability into CNF, writes DIMACS files, invokes GV, and collects runtime
and MiniSat statistics in CSV and Markdown form.

## Encoding

For a graph with `n` vertices and `k` colors, variable `x(v, c)` means vertex
`v` uses color `c`.

- Each vertex has at least one color: `(x(v, 0) OR ... OR x(v, k - 1))`
- Each vertex has at most one color: `(!x(v, a) OR !x(v, b))` for every color pair
- Adjacent vertices cannot share a color: `(!x(u, c) OR !x(v, c))` for every edge and color

The number of SAT variables is `n * k`. Clauses grow with both the vertex count
and the number of edges, so denser graphs produce larger DIMACS instances.

## Running a suite

Build GV first, then run:

```bash
python3 scripts/sat_graph_coloring_experiment.py \
  --sizes 8 12 16 \
  --colors 3 \
  --densities 0.2 0.7 \
  --out-dir examples/sat_graph_coloring_runs
```

The default suite generates both SAT and UNSAT instances for each size/density:

- SAT cases are random `k`-partite graphs, which are guaranteed to be `k`-colorable.
- UNSAT cases contain a `(k + 1)`-clique, which cannot be colored with `k` colors.

Outputs:

- `examples/sat_graph_coloring_runs/cnf/*.cnf`: DIMACS files
- `examples/sat_graph_coloring_runs/logs/*.log`: raw GV/MiniSat output
- `examples/sat_graph_coloring_runs/results.csv`: machine-readable measurements
- `examples/sat_graph_coloring_runs/report.md`: summary table and observations

To generate DIMACS without invoking GV:

```bash
python3 scripts/sat_graph_coloring_experiment.py --skip-gv
```

## Example questions to explore

- How does runtime change as `vars = vertices * colors` increases?
- How does density affect `#clauses`, conflicts, and propagations?
- Are SAT or UNSAT instances harder for this encoding and graph family?
- Does adding dense edge constraints prune the search quickly, or create more
  propagation work?
