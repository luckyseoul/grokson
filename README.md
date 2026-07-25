# grokson

**Run Qwen3.6-35B-A3B NVFP4 on non-Blackwell NVIDIA GPUs** (tested on Tesla V100 16GB) using [llama.cpp](https://github.com/ggml-org/llama.cpp)’s dequant path — not Ollama’s Mac-only MLX tags.

NVFP4 is a **weight format**. You do **not** need Blackwell FP4 tensor cores to *load* it. Runtime can dequantize tiles to FP16 and matmul on Volta/Turing/Ampere the same way a 64-bit OS runs 32-bit code: compatibility path, not native ISA.

```text
NVFP4 weights on disk  →  vectorized dequant  →  FP16 Tensor Cores (V100, etc.)
```

On a V100 16GB with auto layer offload (`-ngl -1`), sustained generation is about **~40 tok/s** for normal prompts (short micro-runs can spike ~70 tok/s and are not the steady number).

## Why this exists

| Approach | Result on Linux + V100 |
|----------|-------------------------|
| `ollama pull qwen3.6:35b-a3b-nvfp4` | **Fails** — official tags are **MLX / macOS-only** (`412: this model requires macOS`) |
| GGUF Q4 without NVFP4 | Works, but not the NVFP4 quant you wanted |
| **NVFP4 GGUF + llama.cpp CUDA** | **Works** — dequant on GPU/CPU, A3B keeps per-token compute light |

**A3B (3B active)** reduces FLOPs per token vs dense 35B. Weight file size can still be ~22GB; use `-ngl -1` so llama.cpp auto-fits layers into free VRAM (partial GPU + system RAM).

## Quick start

```bash
git clone https://github.com/luckyseoul/grokson.git
cd grokson

# 1) Build llama.cpp for your GPU arch (V100 = 70)
./scripts/build-llama-cuda.sh
# CUDA_ARCH=86 ./scripts/build-llama-cuda.sh   # example: RTX 30xx

# 2) Download NVFP4 GGUF (~22GB)
./scripts/download-model.sh

# 3) Install `grokson` on PATH
./scripts/install-alias.sh
source ~/.bashrc

# 4) Run
grokson                                          # CLI chat
grokson -p "Say hello in one short sentence." -n 64
MODE=code grokson -p "Write is_prime(n) in Python. Only code." -n 128
grokson agent                                    # WebUI + bash tool
```

### Environment

| Variable | Meaning |
|----------|---------|
| `GROKSON_CLI` / `CLI` | Path to CUDA `llama-cli` |
| `GROKSON_MODEL` / `MODEL` | Path to `.gguf` |
| `MODE` | `chat` (default) or `code` sampling |
| `NGL` | GPU layers (`-1` = auto, default) |
| `CTX`, `N`, `THREADS`, … | See `scripts/grokson.sh` |

Optional config file: `~/.config/grokson/env` or repo `.env`.


## Agent mode (bash + tools, LAN access)

Plain `grokson` is local CLI chat. For **bash tools** on a **headless** box, reachable from other machines:

```bash
grokson agent
# binds 0.0.0.0:8080 by default
# prints LAN URLs, e.g. http://192.168.x.x:8080
```

From another node (browser, curl, OpenAI-compatible client):

```bash
# WebUI
http://<server-ip>:8080

# OpenAI-compatible API
export OPENAI_BASE_URL=http://<server-ip>:8080/v1
curl http://<server-ip>:8080/v1/models
```

Default tools:

| Tool | Role |
|------|------|
| `exec_shell_command` | **bash** / shell |
| `read_file` / `write_file` | file I/O |
| `file_glob_search` / `grep_search` | search |
| `get_datetime` | clock |

```bash
TOOLS=all grokson agent          # all built-in tools
PORT=8090 grokson agent          # custom port
HOST=0.0.0.0 grokson agent       # explicit all-interfaces (default)
CORS_ORIGINS='*' grokson agent   # default; required so remote UIs work with --tools
HOST=127.0.0.1 grokson agent     # lock to local only if you want
```

**Security:** shell tools run as the server user with **no sandbox**. Binding `0.0.0.0` means **anyone who can reach the port** can drive the model and tools. Use firewall / trusted LAN / VPN. Open TCP `PORT` on the host firewall if needed.

## Tuned defaults (V100 16GB bench)

| Knob | Default | Notes |
|------|---------|--------|
| `-ngl` | **`-1` (auto)** | Fixed `28` was ~15 TG; auto ~40 TG |
| `-ub` | `512` | Best all-rounder; `1024` better on tiny prompts only |
| `-t` / `-tb` | `16` / `32` | |
| `-fa` | `auto` | |
| KV cache | `f16` / `f16` | |
| Chat sampling | T0.7 top_p0.8 top_k20 presence **1.5** | Non-thinking instruct |
| Code sampling | T0.6 top_p0.95 presence 0 | `MODE=code` |

## Model

Default download:

- [knoopx/Qwen3.6-35B-A3B-NVFP4-GGUF](https://huggingface.co/knoopx/Qwen3.6-35B-A3B-NVFP4-GGUF)  
  file: `Qwen3.6-35B-A3B-NVFP4.gguf` (~22GB)

Tensor types include many **NVFP4** blocks (plus BF16/F32 auxiliaries). llama.cpp dequants for matmul on GPUs without native FP4.

Other NVFP4 GGUFs can be used by setting `MODEL=...`.

## Build notes (CUDA + older GPUs)

`scripts/build-llama-cuda.sh`:

1. Targets **`CMAKE_CUDA_ARCHITECTURES`** (default **70** for V100).  
   CUDA 13.x dropped offline compile for `< sm_75` — use **CUDA 12.8** (or similar) for V100.
2. Prefers **gcc/g++-14** if present (GCC 15 often rejected by CUDA 12.x).
3. Applies a local **noexcept** patch to CUDA `math_functions.hpp` when the known `rsqrt`/`sinpi`/`cospi` host-compile clash appears.

## What this is not

- Not native Blackwell **W4A4 FP4 Tensor Core** throughput (that’s a different speed tier).
- Not a fix for Ollama shipping NVFP4 only as MLX on macOS.
- Not a claim that FP4 bit-patterns equal INT4 — re-quant is a second approximation; dequant-at-runtime keeps the NVFP4 checkpoint.

## License

MIT — see [LICENSE](LICENSE).

Model weights are subject to their own licenses (Qwen / quant host on Hugging Face).

## Credits

- [llama.cpp](https://github.com/ggml-org/llama.cpp) — NVFP4 dequant + CUDA backends  
- Qwen team — Qwen3.6-35B-A3B  
- Community NVFP4 GGUF packaging (default: knoopx)  
- Method validated on **Tesla V100-SXM2-16GB**, Ubuntu, CUDA 12.8, driver 580
