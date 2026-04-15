# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

GV is a C++ EDA/formal-verification framework that builds a single `./gv` CLI binary. It integrates ABC, Yosys, MiniSat, Glucose, and a VCD parser. Build uses CMake + Make; external engines are fetched via `ExternalProject_Add` / `FetchContent` at build time.

### Build

```bash
make        # cmake configure + parallel build (≈5-8 min first time)
```

The binary is symlinked to `./gv` at the project root.

### Test

```bash
make test       # run standard test suite (21 dofile tests)
make test-full  # include the "full" folder tests (takes longer)
```

Tests use `./scripts/RUN_TEST` which diffs `./gv -file <test>.dofile` output against reference logs in `tests/*/ref_linux/`. One test (`tests/common/dofile/help.dofile`) fails due to stale reference data (missing Simulate/Prove command sections) — this is a pre-existing issue.

### Lint

```bash
./scripts/LINT   # runs clang-format + clang-tidy (requires GNU parallel, clang-format, clang-tidy)
```

### Running the application

```bash
LD_LIBRARY_PATH=build/engines/src/engine-yosys:$LD_LIBRARY_PATH ./gv
```

The `LD_LIBRARY_PATH` prefix is needed so the dynamic linker finds `libyosys.so`. Without it, `./gv` may segfault or fail to load Yosys functionality.

### Key gotchas

- **Default `c++` is clang 18** on the Cloud Agent VM, which selects GCC 14's toolchain but C++ headers are only present if `g++-14` (or `libstdc++-14-dev`) is installed. The update script handles this, but if you see `'new' file not found` or similar errors, run `sudo apt-get -y install g++-14`.
- **`libstdc++.so` symlink**: The linker may fail with `cannot find -lstdc++` because the `.so` symlink is missing from `/usr/lib/x86_64-linux-gnu/`. The update script creates it; if it disappears, run: `sudo ln -sf /usr/lib/gcc/x86_64-linux-gnu/13/libstdc++.so /usr/lib/x86_64-linux-gnu/libstdc++.so`.
- **First build is slow** (5-8 min) because it git-clones and compiles ABC, Yosys, VCD-parser, fmt, and Glucose. Subsequent incremental builds are fast.
- **`GNU parallel`** is required by both `scripts/RUN_TEST` and `scripts/LINT`.
