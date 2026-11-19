# AGENTS.md

This repository is the DeepSeek-V4.1-Flash engine (`strata-dsv41`) and its server, trimmed from upstream Strata at
`13eedf552`. [README.md](README.md) is the reference for building, packing a model, running the server and every setting.

## Layout

- `engine/src/dsv41`, `engine/include/strata/dsv41`: the engine. Upstream's source, unchanged; keep it that way unless a change is the
  point of the work.
- `engine/`: everything CMake builds (`cmake -S engine`; CUDA or HIP; `engine/metal/CMakeLists.txt` for Apple Silicon).
- `terminal/serve/`: the OpenAI- and Anthropic-compatible server. It accepts only `"arch": "deepseek41"` configs.
- `terminal/strata_control/`: small helpers the server imports.
- `terminal/tools/dsv41`: packing, conversion, smoke test and tuner.

## Checks

- Server tests, no GPU needed: `python -m pytest terminal/serve`.
- Engine tests: configure with `-DSTRATA_BUILD_TESTS=ON`, then `ctest` for the host-side tests. `ds4_tq_test` and
  `ds4_iq_test` need a GPU.
- A change to the engine or its build: rebuild (`build-dsv41.bat` on Windows) and run `terminal/tools/dsv41/smoke.py` against a
  pack.

## What is verified

Only the Windows NVIDIA (CUDA) build has been built and run. The HIP and Metal builds are untested; say so in anything
you write about them. Make no claim about speed or correctness without a measurement.

Measurements, benchmark results and details of anyone's own machine or install (hardware, paths, local configs) are not
committed. Keep them in untracked files.

## Commits

Plain words, short sentences. Credit upstream Strata and Project Maya for engine and server work.
