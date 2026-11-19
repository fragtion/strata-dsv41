# strata-dsv41: DeepSeek-V4.1-Flash

A standalone build of the DeepSeek-V4.1-Flash engine (`strata-dsv41`) and its OpenAI- and Anthropic-compatible server,
taken from upstream [Strata](https://github.com/Niko1221/Strata) at commit **`13eedf552`**, the last upstream commit with
DeepSeek in it.

Upstream removed DeepSeek in Strata 0.2.14. This repository keeps it buildable and runnable. Everything else upstream
ships (the Qwen engines, the desktop app, the `strata` Terminal, setup, Docker) has been left out, and the server knows
only DeepSeek.

## Contents

- [Source and credits](#source-and-credits)
- [Platforms](#platforms)
- [Quick start (Windows, NVIDIA)](#quick-start-windows-nvidia)
- [Building the engine](#building-the-engine)
- [Models and packs](#models-and-packs)
- [Running the server](#running-the-server)
- [Settings](#settings)
- [Checking and tuning](#checking-and-tuning)
- [Slots and restore points](#slots-and-restore-points)
- [Pictures (vision)](#pictures-vision)
- [Several conversations at once](#several-conversations-at-once)
- [Troubleshooting](#troubleshooting)
- [Repository layout](#repository-layout)

## Source and credits

| | |
|---|---|
| Upstream commit | [`13eedf552`](https://github.com/Niko1221/Strata/commit/13eedf552) (2026-11-11), upstream `main`, the last commit before the DeepSeek removal |
| Engine version | **0.1.59.1** (`strata-dsv41 --version` prints `strata-dsv41 0.1.59.1 build <commit>`) |
| Last upstream DeepSeek packages | 0.1.59 ([upstream release v0.2.13](https://github.com/Niko1221/Strata/releases/tag/v0.2.13)) |

The engine source (`engine/src/dsv41`, `engine/include/strata/dsv41`) is upstream's at that commit, unchanged. What changed here is
what was cut around it: the build files, the server's Qwen paths, and the files nothing used any more. See
[NOTICE](NOTICE) for the full list of sources.

All of the engine and server work is upstream's and Project Maya's:

- **Strata**, MIT, Copyright (c) 2026 Niko1221 and the Strata contributors ([LICENSE](LICENSE)). This repository's
  changes are under the same licence.
- **Project Maya** (`maya-ds4`, by mw00, with needmorevram and the Project Maya contributors), MIT: the DeepSeek engine
  is ported from it ([engine/third_party/project-maya](engine/third_party/project-maya/NOTICE.md)).
- **antirez/ds4**, MIT: the Metal form of the vision tower follows it ([engine/third_party/antirez-ds4](engine/third_party/antirez-ds4/NOTICE.md)).
- **ggml / llama.cpp**, MIT, the ggml authors: vendored in [engine/third_party/strata-ggml](engine/third_party/strata-ggml/UPSTREAM.md)
  and [engine/third_party/ggml](engine/third_party/ggml/LICENSE).
- **The model weights** are DeepSeek's, published as GGUF by ISTA-DASLab and Unsloth under their own licences. No model
  file is in this repository.

## Platforms

| Platform | Build | Status |
|---|---|---|
| Windows, NVIDIA (CUDA 13) | `build-dsv41.bat` | **built and run** |
| Linux, NVIDIA (CUDA 13) | CMake, [below](#building-the-engine) | untested; upstream released packages for it |
| AMD (HIP: gfx1100-1102, gfx1151, gfx1200/1201) | CMake with `-DSTRATA_ENABLE_HIP=ON` | **untested**: the CMake files were rewritten for this repository |
| macOS, Apple Silicon (Metal) | [`engine/metal/CMakeLists.txt`](engine/metal/CMakeLists.txt), target `strata_ds4` | **untested**: the Metal CMake was rewritten for this repository |

Upstream ran the HIP engine on Radeon AI PRO R9700 cards and Strix Halo, and the Metal engine on an M5 Max. The source of
those engines is unchanged, but their build files here have never been run. If you build one of them, please open an issue
with what happened.

Upstream's own DeepSeek guides, with their measurements on those machines, are at the source commit:
[DEEPSEEK41.md](https://github.com/Niko1221/Strata/blob/13eedf552/docs/DEEPSEEK41.md) and
[DEEPSEEK_MAC.md](https://github.com/Niko1221/Strata/blob/13eedf552/docs/DEEPSEEK_MAC.md). They describe upstream's installer
and app, which are not part of this repository.

## Quick start (Windows, NVIDIA)

Needs:

- Windows 10 or 11, an NVIDIA card (RTX 30 or newer) with driver 580.65 or newer;
- Python 3.10 or newer;
- about 64 GB of RAM for the 2-bit sets (less works, slowly);
- an NVMe drive with room for the model (190 to 275 GB, [below](#models-and-packs));
- to build: Visual Studio 2022 with the C++ workload, and the CUDA 13.0 toolkit.

```bat
git clone https://github.com/fragtion/strata-dsv41
cd strata-dsv41
py -m venv .venv
.venv\Scripts\python.exe -m pip install -r terminal\requirements.txt -r terminal\requirements-build.txt
set DSV41_ARCH=86-real
build-dsv41.bat
```

Use your card's number in `DSV41_ARCH`: `86-real` for RTX 30, `89-real` for RTX 40, `120` for RTX 50. Then download a
model and make its pack ([Models and packs](#models-and-packs)), write a run config ([Running the server](#running-the-server))
and start the server.

**Without building.** Upstream's last package, `strata-dsv41-0.1.59-windows-x86_64-cuda-cuda13.tar.gz` from the
[v0.2.13 release](https://github.com/Niko1221/Strata/releases/tag/v0.2.13), runs with this server too. Check it against
that release's `SHA256SUMS.txt` and unpack it into `engine-dsv41\`.

## Building the engine

### Windows (`build-dsv41.bat`)

```bat
build-dsv41.bat
set DSV41_ARCH=86-real & build-dsv41.bat
```

- **Toolchain.** `vswhere` finds Visual Studio 2022 (any edition, or the Build Tools). CUDA comes from
  `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0`, or set `CUDA_ROOT`. CMake and Ninja come from `.venv` when
  they are there, otherwise from `PATH`.
- **Architectures.** `DSV41_ARCH` defaults to `86-real;89-real;120` (RTX 30, 40 and 50, plus PTX for 120). One
  architecture builds about three times faster.
- **Result.** `engine-dsv41\<version>-windows-x86_64-cuda-cuda13-src\strata-dsv41.exe`, with `cublas64_13.dll` and
  `cublasLt64_13.dll` copied from CUDA beside it. The compiler log is `build-dsv41\build.log`.
- **Build id.** The git commit is read when CMake configures, so build from a git checkout and `--version` names it.

### By hand (Windows or Linux, NVIDIA)

```sh
cmake -S engine -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DSTRATA_PORTABLE=ON "-DCMAKE_CUDA_ARCHITECTURES=86-real"
cmake --build build --target strata-dsv41
```

### AMD (HIP), untested

```sh
cmake -S engine -B build-hip -G Ninja -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_HIP=ON -DSTRATA_PORTABLE=ON -DCMAKE_HIP_ARCHITECTURES=gfx1201
cmake --build build-hip --target strata-dsv41
```

Needs ROCm with hipBLAS. Upstream's scripts, adapted to this build, are `terminal/tools/dsv41/build_hip_linux.sh` (Linux) and
`terminal\tools\dsv41\win\build_hip_win.bat` (Windows, ROCm from TheRock's wheels). `engine/cmake/hip_backend.cmake` has the options.

### Mac (Metal), untested

```sh
cmake -S engine/metal -B build-metal -G Ninja -DCMAKE_BUILD_TYPE=Release -DMETAL_CPP_DIR=/path/to/metal-cpp
cmake --build build-metal --target strata_ds4
```

Needs Xcode's command line tools and Apple's [metal-cpp](https://developer.apple.com/metal/cpp/) headers.

### CMake options

| Option | Default | What it does |
|---|---|---|
| `STRATA_ENABLE_CUDA` | OFF | build for NVIDIA |
| `STRATA_ENABLE_HIP` | OFF | build for AMD |
| `STRATA_PORTABLE` | OFF | a CPU lane that runs on any AVX2 CPU instead of only the build machine's (use it for a build you copy elsewhere) |
| `STRATA_BUILD_TESTS` | OFF | also build the tests in `engine/tests/dsv41` |

With neither CUDA nor HIP, only the CPU lane's benchmark (`ds4_gg_bench`) is built. The vendored ggml in
`engine/third_party/strata-ggml` is used; nothing is downloaded.

### Tests

```sh
cmake -S engine -B build-tests -G Ninja -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_TESTS=ON "-DCMAKE_CUDA_ARCHITECTURES=86-real"
cmake --build build-tests
ctest --test-dir build-tests
```

`ctest` runs the host-side tests. `ds4_tq_test` and `ds4_iq_test` need a GPU and are run by hand. The server's tests run
without a GPU:

```sh
python -m pip install -r terminal/requirements-dev.txt
python -m pytest terminal/serve
```

## Models and packs

The engine reads a **pack**: a few MB of index and metadata that point into the GGUF files, plus a hot-expert profile.
The model files stay where they are.

### The sets

| Set | Hugging Face | Download | Quality (KL against the original model) |
|---|---|---|---|
| IQ1_M, 1.75 bpw | [ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF) | 239 GB | 0.217; weaker on prose |
| IQ2_XXS, 2.00 bpw | the same | 257 GB | 0.170 |
| IQ2_XS, 2.25 bpw | the same | 274 GB | 0.107 |
| Coder (192 of 384 experts a layer) | [ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-Coder-GGUF](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-Coder-GGUF) | 191 GB | for code; file list and hashes in [terminal/data/dsv41/coder-set.json](terminal/data/dsv41/coder-set.json) |
| UD-Q8_K_XL | [unsloth/DeepSeek-V4.1-Flash-1017-GGUF](https://huggingface.co/unsloth/DeepSeek-V4.1-Flash-1017-GGUF) | 508 GB | for several cards and hundreds of GB of RAM |

The KL numbers are upstream's (4,995 positions). The download sizes include files every set shares, which you download
once into one folder:

| Shared file | From | Size | What it is |
|---|---|---|---|
| `DeepSeek-V4.1-Flash-Engram-IQ4_NL.gguf` | ISTA-DASLab (the first repository) | 111 GB | the n-gram table (Engram), read from RAM or the drive |
| `dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf` | Unsloth | 8 GB | the DSpark draft model |
| `mmproj-BF16.gguf` | Unsloth | 1 GB | the vision tower, for pictures |
| `UD-Q8_K_XL/DeepSeek-V4.1-Flash-1017-UD-Q8_K_XL-00001-of-00009.gguf` | Unsloth | 6 MB | metadata only, for the four-shard ISTA-DASLab sets |

ISTA-DASLab's sets come in two layouts: four shards (`...-0000N-of-00004.gguf`) and, since 2026-10-27, six
(`...-0000N-of-00006.gguf`, where shard 1 is a small metadata file). The engine reads both.

### Making a pack

The official sets, with the shared files in `SHARED`:

```bat
.venv\Scripts\python.exe terminal\tools\dsv41\pack_gguf.py --model SETDIR --shards <the set's shard files> ^
  --engram SHARED\DeepSeek-V4.1-Flash-Engram-IQ4_NL.gguf ^
  --engram-meta <metadata shard> ^
  --dspark-gguf SHARED\dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf ^
  --dspark-noise-token 128799 --dspark-markov-rank 256 ^
  --mmproj SHARED\mmproj-BF16.gguf ^
  --out PACK
copy terminal\data\dsv41\profile-2.25.bin PACK\expert-profile.bin
```

- **`--engram-meta`.** For a four-shard set, Unsloth's 6 MB first shard. For a six-shard set (and the Coder), the set's
  own shard 1.
- **`--dspark-noise-token 128799 --dspark-markov-rank 256`.** The ISTA-DASLab files do not carry these. Without them the
  drafter drafts deep less often (about 10% slower with DSpark).
- **`--mmproj`.** Leave it out for a text-only pack.
- **No other flags.** `--skip-tensors` or `--dense-override` make a pack without an error, and the model then writes
  garbage.
- **Profile.** Copy the profile that matches the set: `profile-2.00.bin` (also for 1.75), `profile-2.25.bin` or
  `profile-coder.bin`. It decides which experts load into VRAM first. The Coder needs its own: the engine refuses a
  profile counted on 384 experts.
- **Check.** `strata-dsv41 --pack PACK --pack-info` lists any missing file. Then run the smoke test
  ([Checking and tuning](#checking-and-tuning)).

The Unsloth UD-Q8_K_XL set needs only `--model` (and `--mmproj` for pictures). `pack_gguf.py --help` lists every option.

Keep the model files on an NVMe drive. The experts that are in neither VRAM nor the RAM store are read from it for every
token.

## Running the server

The server is started with a run config, a JSON file. `.gitignore` keeps `strata-*.json` and `run-*.bat` in the repository
root out of git, so you can keep them there.

```json
{
 "exe": "C:\\strata-dsv41\\engine-dsv41\\0.1.59.1-windows-x86_64-cuda-cuda13-src\\strata-dsv41.exe",
 "lib_dirs": ["C:\\strata-dsv41\\engine-dsv41\\0.1.59.1-windows-x86_64-cuda-cuda13-src"],
 "args": ["--pack", "E:\\packs\\deepseek-v4.1-flash-2.25bpw",
          "--max-context", "262144", "--eos", "1", "--dspark", "auto", "--dspark-conf", "0.65"],
 "tokenizer": "E:\\packs\\deepseek-v4.1-flash-2.25bpw\\tokenizer",
 "model_name": "deepseek-v4.1-flash",
 "arch": "deepseek41",
 "log": "C:\\strata-dsv41\\strata-deepseek-v4.1-flash.log",
 "engine_ready_s": 3600,
 "gpu": 0
}
```

```bat
.venv\Scripts\python.exe terminal\serve\server.py --engine strata --config strata-deepseek-v4.1-flash.json --port 8080 --open
```

`--port` sets the port (the default is 8095; the config has no port key). `--open` opens the chat page in the browser.
Loading takes one to a few minutes.

**Config keys:**

| Key | What it does |
|---|---|
| `exe`, `args` | the engine and its flags ([Settings](#settings)) |
| `lib_dirs` | folders put first on the engine's library path (the CUDA DLLs beside it) |
| `tokenizer` | the pack's `tokenizer` folder |
| `arch` | must be `"deepseek41"`; the server refuses anything else |
| `log` | the engine's log. Slots go into `ds4-slots` beside it |
| `host` | `"0.0.0.0"` listens on the network as well. The default is `127.0.0.1`, this computer only |
| `api_key` | requires this key. Recommended whenever `host` is not `127.0.0.1` |
| `env` | environment variables for the engine, for example `{"DS4_STORE_GB": "30"}` |
| `parallel` | answer N conversations at once ([below](#several-conversations-at-once)) |
| `engine_ready_s` | how long to wait for the engine to load, in seconds |

For the Coder with pictures, add `"--vision", "on", "--reserve-mib", "900"` to `args`.

**The API.** OpenAI and Anthropic on the same port: `/v1/chat/completions`, `/v1/messages`, `/v1/models`, `/health`,
`/metrics`, streaming or not.

- **Thinking** is on by default. `reasoning_effort: "none"` or `chat_template_kwargs.enable_thinking: false` turns it off.
  The effort words are `low` (50), `medium` (62), `high` (75, the default) and `max` (100), or a whole number from 1 to 100.
- **Tool calls.** The model writes DSML. The server turns it into OpenAI `tool_calls` and Anthropic `tool_use`, with
  `tool_choice`, streamed arguments and calls written inside the thinking.
- **Prompts** use the GGUF's own chat template.
- **Sampling.** When a request sets none, temperature is 1.0 and top_p is 1.0. `logit_bias` works as described in
  [docs/LOGIT_BIAS.md](docs/LOGIT_BIAS.md).
- **Speed.** Each response carries `timings.predicted_per_second`, the answer speed from the engine's own clock.
- **Context.** A prompt that does not fit the context gets a 400; it is never cut. When the prompt fits but the prompt
  plus `max_tokens` does not, `max_tokens` is shortened to the room left (`"fit_max_tokens": false` turns that off).

`python terminal/serve/server.py --help` lists the server's own options.

## Settings

### Engine flags (`args`)

```
--pack <pack> [--gpus 0,1,...] [--max-context N] [--reserve-mib N]
[--vram-experts F] [--cpu-threads N] [--expert-profile FILE|none] [--profile-readonly] [--ssd-cache GB] [--ssd-policy lru|lfu|lfulru]
[--tp N] [--threads on|off] [--prefill-chunk N] [--dspark on|off|none|auto] [--dspark-block N] [--dspark-conf F] [--experts N|auto]
[--vision on|off] [--vision-resident] [--mmap-experts on|off|auto] [--parallel N]
```

- **`--max-context`**: 8K to 1M. Upstream tested up to 256K. The context's cache takes VRAM the experts would otherwise
  use, and a very long prompt is read slowly.
- **`--dspark auto|on`**: the DSpark drafter. Do not use `off`: it still loads the drafter, and its 7 GB of experts take
  VRAM. `auto` leaves it unloaded where it would not help, for example on a 12 GB card with the 2-bit sets. `none` does
  not load it at all.
- **`--experts auto|5|6`**: the model picks 6 experts a token. **5** ("Faster") is a small quality change and answers
  sooner. `auto` picks 5 on cards with 16 GiB or less and on integrated GPUs.
- **`--ssd-cache GB`**: the RAM store for the experts that are not in VRAM. It sizes itself by default.
- **`--reserve-mib N`**: VRAM kept free, for the picture tower and prompt buffers.
- **`--prefill-chunk N`**: the long-prompt chunk size. The engine picks one by default.

The engine uses neither large pages nor a working-set lock, so it needs no "Lock pages in memory" privilege and no
elevated prompt.

### `DS4_*` environment settings

The engine reads more than 100 `DS4_*` variables (Project Maya's names; `grep getenv\(\"DS4_ engine/src/dsv41`). Most are for
measuring and debugging. The ones worth knowing:

| Variable | What it does |
|---|---|
| `DS4_STORE_GB` | a fixed RAM store size in GB, the same as `--ssd-cache` |
| `DS4_COPY_GB`, `DS4_COPY_ALL` | the CPU lane's RAM copy of its experts. `DS4_COPY_ALL=1` copies them all in at load |
| `DS4_ASYNC_T` | the verify window's async threshold (default 16). Upstream used 4 on Strix Halo |
| `DS4_NO_VIEW` | `=1` drops the shards' file views after the load and reads unbuffered (Windows) |
| `DS4_CHUNK_LOG`, `DS4_ROUND_LOG`, `DS4_TRACE`, `DS4_PROF`, `DS4_IO_STATS` | diagnostic logs |

### `STRATA_DS4_*` environment settings

The ones for users:

| Setting | Default | What it does |
|---|---|---|
| `STRATA_DS4_SLOT_KEEP` | 1 | `0` turns slots off |
| `STRATA_DS4_SLOT_GB` | 2 (server), 16 (engine) | the slot folder's cap |
| `STRATA_DS4_SLOT_DAYS` | 7 | slots older than this are removed |
| `STRATA_DS4_SLOT_DIR` | `ds4-slots` beside the log | where slots go |
| `STRATA_DS4_AUTO_PIN` | 1 | `0` turns off the shared system-prompt checkpoint |
| `STRATA_DS4_RESTORE_POINTS` | 4 | restore points a conversation; `0` off |
| `STRATA_DS4_RESTORE_TAIL` | 512 | how far before a prompt's end the tail restore point sits |
| `STRATA_DS4_PREFIX_GB`, `STRATA_DS4_PREFIX_KEEP`, `STRATA_DS4_PREFIX_MIN` | 2, 2, 1024 | shared-prefix checkpoints |
| `STRATA_DS4_PROMPT_SKIP` | 1 | the long-prompt layer skip |
| `STRATA_DS4_PIN_BY_NEED` | on (Windows, one GPU) | `0` turns pin-by-need off |
| `STRATA_DS4_READ_PIECES` | 0 | opt-in read-pieces mode |
| `STRATA_DS4_HIPK` | 0 | AMD: the matrix-core kernel; `=0` SIMT, `=2` the alternative |

The others in the source (`STRATA_DS4_DISK_SKIP_*`, `STRATA_DS4_RAM_TIER`, `STRATA_DS4_NO_TC`, ...) are upstream's
research switches.

## Checking and tuning

| What | How |
|---|---|
| Does the pack answer? | `python terminal\tools\dsv41\smoke.py --exe <strata-dsv41> --pack <pack>`: 16 tokens through the engine, and the reply must name Paris. Stop the server first |
| Short tune | `python terminal\tools\dsv41\tune.py --config <run config> [--mode quick\|thorough]`. It runs the engine a few times on a fixed question and tries `--dspark on`, `--dspark-block 3` and the CPU thread count. It keeps a setting only for a gain over 5% and writes it into the config's `args`. About 5 to 10 minutes |
| Answer speed | the response's `timings.predicted_per_second`, or `/metrics` (`decode_tok_s`) |
| Pack and conversion tools | `terminal\tools\dsv41\`: `pack_gguf.py`, `vision_pack.py`, `drafter_pack.py`, `ista_intake.py`, `pin_coder.py`, `requant_gguf.py`, `dense_requant.py`, `tq_convert.py` (trellis experts, see `terminal\tools\trellis\README.md`) |
| Reference and compare | `terminal\tools\dsv41\`: `ref.py`, `ref_gguf.py`, `compare.py`, `dumpcmp.py`, `dumpscan*.py`, `dspark_ref.py`, `make_imatrix.py`, `engram_*.py` |
| Kernel experiments | `terminal\tools\dsv41_lab\` |

## Slots and restore points

Agents and sub-agents take turns on the model. The engine sets a conversation aside when another request takes the model,
and takes it back when the next prompt continues it, even after a restart.

- **Where.** In `ds4-slots` beside the run log. A 6.5K-token conversation takes about 17 MB.
- **Cap.** The server caps the folder at 2 GB (`STRATA_DS4_SLOT_GB`).
- **Clean-up.** Slots older than a week, or from another model, are removed.
- **Shared prefix.** The system prompt and tools an agent shares with its sub-agents are kept as a checkpoint.

**Restore points** are positions where a later prompt is likely to branch off: the conversation's turn marks, 512 tokens
before the prompt's end, and the shared prefix. The server asks the engine to keep up to 4 a conversation, so an edited or
regenerated turn re-reads only from the nearest point. None is kept before 1,024 tokens.

## Pictures (vision)

With a pack made with `--mmproj` and `--vision on`, the engine reads pictures with its own vision tower.

- **Memory.** The tower waits in pinned RAM (about 1 GB). It takes its 319 MiB of VRAM only while it reads a picture, from
  the room `--reserve-mib` keeps free. Use `--reserve-mib 900` with pictures on.
- **No free VRAM.** The last expert slots are lent to the tower for that turn and read back afterwards.
- **Picture size.** The server (`terminal/serve/ds_pictures.py`, needs Pillow) scales each picture so both sides are multiples of
  42, at most 1024 image tokens. JPEG, PNG, BMP, GIF, WebP, TIFF and AVIF work.
- **Off.** With `--vision off`, or a pack without the tower, a request with a picture gets a 400 that says so.
  `--vision-resident` keeps the tower on the card.

## Several conversations at once

Off by default: requests take turns. `"parallel": N` in the config (2 to 8), or `--parallel N` on the server's command
line, answers that many conversations together.

Each conversation takes its own attention cache out of the experts' VRAM: about 0.01 GB at 8K context, 0.17 GB at 128K
and 0.68 GB at 512K. If the cards cannot hold every conversation's buffers, the engine runs as many as fit and says so in
its log. Upstream measured it on Linux with 24 GB and larger cards (4 conversations at once: 73 tokens/s in all on four
R9700, against 41 for one alone).

## Troubleshooting

**The port is in use.** Another server holds it. `curl http://127.0.0.1:8080/health` shows which model. Stop it, or pass
another `--port`.

**Out of VRAM at start.** Another program holds the card (check `nvidia-smi`). With pictures on, raise `--reserve-mib` if
the first picture fails.

**Garbage text.** A pack built with `--skip-tensors` or `--dense-override` loads but writes garbage. Make the pack again
with the recipe above and run the smoke test.

**LNK1104 while building.** The linker cannot write TEMP. `build-dsv41.bat` points TEMP at `build-dsv41\tmp`; do the same
for a build by hand.

**Slow answers.** The experts that are in neither VRAM nor the RAM store are read from the drive for every token. Use
NVMe, close programs that hold VRAM or RAM, and check the engine's start lines in the run log: how many experts are in
VRAM, the `RAM store` size, `experts per word`, and whether DSpark was loaded.

**A small RAM store with an old engine.** Engines before 0.1.53 could take a discrete card for a shared-memory GPU and
shrink the RAM store (upstream #4147). This engine has the fix. With an older one, set `"env": {"DS4_STORE_GB": "<GB>"}`.

## Repository layout

The folders follow upstream Strata's 0.2.16 layout.

| Path | What it is |
|---|---|
| `engine/` | everything CMake builds: `CMakeLists.txt`, `cmake/`, `src/`, `include/`, `metal/`, `third_party/` and the C++ tests |
| `engine/src/dsv41`, `engine/include/strata/dsv41` | the engine |
| `engine/src/kernels/cpu`, `engine/include/strata/kernels/cpu`, `engine/src/platform`, `engine/include/strata/platform` | the CPU lane's kernels and the thread pool |
| `engine/src/prefill/wmma_gemm.cu`, `engine/src/core/device.cu` | two shared files the HIP build needs |
| `engine/metal/` | the Metal build |
| `engine/tests/dsv41` | the engine's tests |
| `engine/third_party/` | vendored ggml and the credits |
| `terminal/` | the Python side: the server, its helpers, the tools, the data and the requirements |
| `terminal/serve/` | the server and its tests |
| `terminal/strata_control/` | small helpers the server uses (paths, processes, GPU roles) |
| `terminal/tools/dsv41`, `terminal/tools/trellis`, `terminal/tools/dsv41_lab`, `terminal/tools/strata_tokenizer.py` | pack, conversion, reference and test tools |
| `terminal/data/dsv41` | the hot-expert profiles and the Coder's file list |
| `docs/` | the pages |
| `.github/SECURITY.md` | how to report a security problem |
| `build-dsv41.bat` | the Windows build |
