#!/usr/bin/env python3
"""Generate graph-coloring SAT instances and solve them with GV MiniSat.

The script encodes k-colorability in DIMACS CNF, invokes GV's
``SATSolve DIMACS -File <cnf> -Stats`` command, and writes a CSV plus a
Markdown report that can be used to compare runtime and SAT statistics across
problem sizes and graph densities.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import re
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from random import Random
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = REPO_ROOT / "examples" / "sat_graph_coloring_runs"
STAT_RE = re.compile(r"([A-Za-z_]+)=(-?\d+(?:\.\d+)?)")


Edge = Tuple[int, int]
Clause = Tuple[int, ...]


@dataclass(frozen=True)
class InstanceSpec:
    name: str
    kind: str
    vertices: int
    colors: int
    density: float
    seed: int
    expected: str


@dataclass
class EncodedInstance:
    spec: InstanceSpec
    edges: List[Edge]
    clauses: List[Clause]
    num_vars: int
    dimacs_path: Path


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def probability(value: str) -> float:
    parsed = float(value)
    if parsed < 0.0 or parsed > 1.0:
        raise argparse.ArgumentTypeError("density must be in [0.0, 1.0]")
    return parsed


def var_id(vertex: int, color: int, colors: int) -> int:
    """DIMACS variable for "vertex has color"."""
    return vertex * colors + color + 1


def k_partite_edges(vertices: int, colors: int, density: float, seed: int) -> List[Edge]:
    """Return a graph that is guaranteed to be k-colorable.

    Vertices are assigned to color partitions by vertex index modulo k. Edges
    are only generated across partitions, so the partition assignment is a
    valid coloring even when density is 1.0.
    """

    rng = Random(seed)
    edges: List[Edge] = []
    for u, v in itertools.combinations(range(vertices), 2):
        if u % colors == v % colors:
            continue
        if rng.random() <= density:
            edges.append((u, v))
    return edges


def clique_obstruction_edges(vertices: int, colors: int, density: float, seed: int) -> List[Edge]:
    """Return a graph guaranteed to be uncolorable with ``colors`` colors.

    The first ``colors + 1`` vertices form a clique, requiring one more color
    than is available. Extra random edges control sparse/dense characteristics
    without changing the UNSAT guarantee.
    """

    if vertices <= colors:
        raise ValueError("UNSAT instances need at least colors + 1 vertices")

    rng = Random(seed)
    edges: Set[Edge] = set(itertools.combinations(range(colors + 1), 2))
    for u, v in itertools.combinations(range(vertices), 2):
        if (u, v) in edges:
            continue
        if rng.random() <= density:
            edges.add((u, v))
    return sorted(edges)


def encode_graph_coloring(vertices: int, colors: int, edges: Sequence[Edge]) -> List[Clause]:
    """Encode graph k-colorability as CNF clauses."""

    clauses: List[Clause] = []

    for vertex in range(vertices):
        # Each vertex has at least one color.
        clauses.append(tuple(var_id(vertex, color, colors) for color in range(colors)))

        # Each vertex has at most one color.
        for color_a, color_b in itertools.combinations(range(colors), 2):
            clauses.append(
                (
                    -var_id(vertex, color_a, colors),
                    -var_id(vertex, color_b, colors),
                )
            )

    for u, v in edges:
        for color in range(colors):
            clauses.append((-var_id(u, color, colors), -var_id(v, color, colors)))

    return clauses


def write_dimacs(spec: InstanceSpec, edges: Sequence[Edge], path: Path) -> List[Clause]:
    clauses = encode_graph_coloring(spec.vertices, spec.colors, edges)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("c Graph coloring SAT experiment for GV MiniSat\n")
        handle.write(f"c name={spec.name}\n")
        handle.write(f"c kind={spec.kind}\n")
        handle.write(f"c expected={spec.expected}\n")
        handle.write(f"c vertices={spec.vertices} colors={spec.colors}\n")
        handle.write(f"c edges={len(edges)} density={spec.density} seed={spec.seed}\n")
        handle.write(f"p cnf {spec.vertices * spec.colors} {len(clauses)}\n")
        for clause in clauses:
            handle.write(" ".join(str(lit) for lit in clause))
            handle.write(" 0\n")
    return clauses


def make_instance(spec: InstanceSpec, out_dir: Path) -> EncodedInstance:
    if spec.kind == "sat":
        edges = k_partite_edges(spec.vertices, spec.colors, spec.density, spec.seed)
    elif spec.kind == "unsat":
        edges = clique_obstruction_edges(spec.vertices, spec.colors, spec.density, spec.seed)
    else:
        raise ValueError(f"unknown instance kind: {spec.kind}")

    dimacs_path = out_dir / "cnf" / f"{spec.name}.cnf"
    clauses = write_dimacs(spec, edges, dimacs_path)
    return EncodedInstance(
        spec=spec,
        edges=edges,
        clauses=clauses,
        num_vars=spec.vertices * spec.colors,
        dimacs_path=dimacs_path,
    )


def build_suite(sizes: Sequence[int], colors: int, densities: Sequence[float], seed: int) -> List[InstanceSpec]:
    specs: List[InstanceSpec] = []
    for vertices in sizes:
        for density in densities:
            density_tag = str(density).replace(".", "p")
            specs.append(
                InstanceSpec(
                    name=f"sat_n{vertices}_k{colors}_d{density_tag}",
                    kind="sat",
                    vertices=vertices,
                    colors=colors,
                    density=density,
                    seed=seed,
                    expected="SAT",
                )
            )
            specs.append(
                InstanceSpec(
                    name=f"unsat_n{vertices}_k{colors}_d{density_tag}",
                    kind="unsat",
                    vertices=vertices,
                    colors=colors,
                    density=density,
                    seed=seed + 1000,
                    expected="UNSAT",
                )
            )
    return specs


def build_single_case(args: argparse.Namespace) -> List[InstanceSpec]:
    vertices = args.vertices if args.vertices is not None else max(args.colors + 1, 10)
    density = args.density if args.density is not None else 0.5
    expected = "SAT" if args.case == "sat" else "UNSAT"
    return [
        InstanceSpec(
            name=f"{args.case}_n{vertices}_k{args.colors}_d{str(density).replace('.', 'p')}",
            kind=args.case,
            vertices=vertices,
            colors=args.colors,
            density=density,
            seed=args.seed,
            expected=expected,
        )
    ]


def shell_quote(path: Path) -> str:
    text = str(path)
    if not text:
        return "''"
    if re.search(r"[^A-Za-z0-9_@%+=:,./-]", text):
        return "'" + text.replace("'", "'\"'\"'") + "'"
    return text


def write_dofile(cnf_path: Path, dofile_path: Path, with_stats: bool) -> None:
    dofile_path.parent.mkdir(parents=True, exist_ok=True)
    stats_option = " -stats" if with_stats else ""
    with dofile_path.open("w", encoding="utf-8") as handle:
        handle.write(f"satsolve dimacs -file {shell_quote(cnf_path)}{stats_option}\n")
        handle.write("q -f\n")


def parse_gv_output(output: str) -> Tuple[str, Dict[str, int]]:
    status = "UNKNOWN"
    stats: Dict[str, int] = {}
    for line in output.splitlines():
        stripped = line.strip()
        if stripped == "SAT":
            status = "SAT"
        elif stripped == "UNSAT":
            status = "UNSAT"
        elif stripped.startswith("SATStats "):
            for key, value in STAT_RE.findall(stripped):
                stats[key] = int(float(value))
    return status, stats


def run_gv(gv: Path, instance: EncodedInstance, out_dir: Path, keep_dofiles: bool) -> Dict[str, object]:
    dofile_path = out_dir / "dofile" / f"{instance.spec.name}.dofile"
    log_path = out_dir / "logs" / f"{instance.spec.name}.log"
    write_dofile(instance.dimacs_path, dofile_path, with_stats=True)

    started = time.perf_counter()
    proc = subprocess.run(
        [str(gv), "-file", str(dofile_path)],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    runtime = time.perf_counter() - started

    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(proc.stdout, encoding="utf-8")
    if not keep_dofiles:
        dofile_path.unlink(missing_ok=True)

    status, stats = parse_gv_output(proc.stdout)
    row: Dict[str, object] = {
        "status": status,
        "runtime_sec": f"{runtime:.6f}",
        "gv_returncode": proc.returncode,
        "log_path": str(log_path),
    }
    row.update(stats)
    return row


def result_row(instance: EncodedInstance, run_result: Optional[Dict[str, object]]) -> Dict[str, object]:
    row: Dict[str, object] = {
        "case": instance.spec.name,
        "kind": instance.spec.kind,
        "expected": instance.spec.expected,
        "status": "NOT_RUN",
        "vertices": instance.spec.vertices,
        "colors": instance.spec.colors,
        "density": instance.spec.density,
        "seed": instance.spec.seed,
        "vars": instance.num_vars,
        "clauses": len(instance.clauses),
        "edges": len(instance.edges),
        "runtime_sec": "",
        "starts": "",
        "decisions": "",
        "conflicts": "",
        "propagations": "",
        "learnts": "",
        "clause_literals": "",
        "learnt_literals": "",
        "gv_returncode": "",
        "cnf_path": str(instance.dimacs_path),
        "log_path": "",
    }
    if run_result:
        row.update(run_result)
    return row


def write_csv(rows: Sequence[Dict[str, object]], path: Path) -> None:
    fieldnames = [
        "case",
        "kind",
        "expected",
        "status",
        "vertices",
        "colors",
        "density",
        "seed",
        "vars",
        "clauses",
        "edges",
        "runtime_sec",
        "starts",
        "decisions",
        "conflicts",
        "propagations",
        "learnts",
        "clause_literals",
        "learnt_literals",
        "gv_returncode",
        "cnf_path",
        "log_path",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def numeric_values(rows: Iterable[Dict[str, object]], key: str) -> List[float]:
    values: List[float] = []
    for row in rows:
        value = row.get(key, "")
        if value == "":
            continue
        values.append(float(value))
    return values


def write_markdown(rows: Sequence[Dict[str, object]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    solved_rows = [row for row in rows if row.get("status") in {"SAT", "UNSAT"}]
    mismatches = [
        row for row in solved_rows if str(row.get("status")) != str(row.get("expected"))
    ]

    lines = [
        "# Graph Coloring SAT Experiment",
        "",
        "Generated DIMACS CNF instances encode k-colorability:",
        "",
        "- SAT cases are random k-partite graphs, so the partition is a valid coloring.",
        "- UNSAT cases contain a `(k + 1)`-clique, so k colors are insufficient.",
        "- Density controls how many optional edges are present and therefore how many edge clauses are generated.",
        "",
        "## Results",
        "",
        "| case | expected | status | vars | clauses | edges | runtime_sec | conflicts | decisions | propagations |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]

    for row in rows:
        lines.append(
            "| {case} | {expected} | {status} | {vars} | {clauses} | {edges} | "
            "{runtime_sec} | {conflicts} | {decisions} | {propagations} |".format(**row)
        )

    lines.extend(["", "## Observations", ""])
    if mismatches:
        lines.append("- WARNING: some solver results did not match the generated expectation.")
    elif solved_rows:
        lines.append("- All executed cases matched the generated SAT/UNSAT expectation.")
    else:
        lines.append("- GV was not executed; only DIMACS files were generated.")

    for kind in ("sat", "unsat"):
        kind_rows = [row for row in solved_rows if row.get("kind") == kind]
        if not kind_rows:
            continue
        runtimes = numeric_values(kind_rows, "runtime_sec")
        conflicts = numeric_values(kind_rows, "conflicts")
        propagations = numeric_values(kind_rows, "propagations")
        lines.append(
            "- {} cases: average runtime {:.6f}s, average conflicts {:.2f}, "
            "average propagations {:.2f}.".format(
                kind.upper(),
                statistics.mean(runtimes) if runtimes else 0.0,
                statistics.mean(conflicts) if conflicts else 0.0,
                statistics.mean(propagations) if propagations else 0.0,
            )
        )

    lines.extend(
        [
            "- Increasing graph density increases the number of clauses because every edge adds one binary clause per color.",
            "- MiniSat's conflicts/decisions reflect the search difficulty for this encoding; propagation counts often scale with both variable count and clause density.",
            "",
            "See `results.csv` for machine-readable data and `logs/*.log` for raw GV output.",
            "",
        ]
    )

    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run graph-coloring DIMACS experiments through GV MiniSat."
    )
    parser.add_argument("--gv", type=Path, default=REPO_ROOT / "gv", help="path to GV executable")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="output directory")
    parser.add_argument(
        "--case",
        choices=("suite", "sat", "unsat"),
        default="suite",
        help="run the default suite or generate a single SAT/UNSAT case",
    )
    parser.add_argument(
        "--sizes",
        nargs="+",
        type=positive_int,
        default=(8, 12, 16),
        help="vertex counts for --case suite",
    )
    parser.add_argument("--vertices", type=positive_int, help="vertex count for a single case")
    parser.add_argument("--colors", type=positive_int, default=3, help="number of colors")
    parser.add_argument(
        "--densities",
        nargs="+",
        type=probability,
        default=(0.2, 0.7),
        help="edge densities for --case suite",
    )
    parser.add_argument("--density", type=probability, help="edge density for a single case")
    parser.add_argument("--seed", type=int, default=1, help="random seed")
    parser.add_argument(
        "--skip-gv",
        "--generate-only",
        action="store_true",
        help="write DIMACS files and reports without invoking GV",
    )
    parser.add_argument(
        "--keep-dofiles",
        action="store_true",
        help="keep generated GV dofiles under the output directory",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    out_dir = args.out_dir if args.out_dir.is_absolute() else (Path.cwd() / args.out_dir)
    gv = args.gv if args.gv.is_absolute() else (Path.cwd() / args.gv)

    if args.case == "suite":
        specs = build_suite(args.sizes, args.colors, args.densities, args.seed)
    else:
        specs = build_single_case(args)

    if not args.skip_gv and not gv.exists():
        print(f"error: GV executable not found: {gv}", file=sys.stderr)
        print("build GV first or pass --skip-gv to only generate DIMACS files", file=sys.stderr)
        return 2

    rows: List[Dict[str, object]] = []
    for spec in specs:
        instance = make_instance(spec, out_dir)
        run_result = None
        if not args.skip_gv:
            run_result = run_gv(gv, instance, out_dir, args.keep_dofiles)
        rows.append(result_row(instance, run_result))

    csv_path = out_dir / "results.csv"
    report_path = out_dir / "report.md"
    write_csv(rows, csv_path)
    write_markdown(rows, report_path)

    print(f"Wrote {len(rows)} DIMACS instance(s) under {out_dir / 'cnf'}")
    print(f"Wrote CSV results to {csv_path}")
    print(f"Wrote Markdown report to {report_path}")

    mismatches = [
        row for row in rows if row["status"] not in {"NOT_RUN", row["expected"]}
    ]
    if mismatches:
        print("warning: solver result mismatches were found", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
