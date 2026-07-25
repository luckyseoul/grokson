#!/usr/bin/env bash
# grokson — run Qwen3.6-35B-A3B NVFP4 via llama.cpp dequant path on non-Blackwell GPUs.
#
# Bench on Tesla V100 16GB (2026-07-25), short code prompt n≈80:
#   ngl -1 (auto)  ~82–88 PP / ~38–43 TG   ← use this
#   ngl 28 fixed   ~69 PP / ~15 TG
#   -ub 512        best all-rounder
#   -t 16 -tb 32   solid
#   -ctk/-ctv f16  best TG among tried
#
# Micro-run ("Hi", n=2) can show ~70 TG; sustained chat/code is ~40 TG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "${GROKSON_ENV:-$HOME/.config/grokson/env}" ]] && source "${GROKSON_ENV:-$HOME/.config/grokson/env}"
[[ -f "$ROOT/.env" ]] && source "$ROOT/.env"

MODEL="${MODEL:-${GROKSON_MODEL:-$HOME/models/Qwen3.6-35B-A3B-NVFP4-GGUF/Qwen3.6-35B-A3B-NVFP4.gguf}}"
CLI="${CLI:-${GROKSON_CLI:-$HOME/.local/share/grokson/llama.cpp/build-cuda/bin/llama-cli}}"
# fall back to common build locations
if [[ ! -x "$CLI" ]]; then
  for cand in \
    "$HOME/Projects/builds/llama.cpp/build-cuda/bin/llama-cli" \
    "$ROOT/vendor/llama.cpp/build-cuda/bin/llama-cli" \
    "$(command -v llama-cli 2>/dev/null || true)"; do
    [[ -n "$cand" && -x "$cand" ]] && CLI="$cand" && break
  done
fi

NGL="${NGL:--1}"          # auto-fit layers to free VRAM
CTX="${CTX:-4096}"
N="${N:--1}"              # -1 = until stop (interactive)
BATCH="${BATCH:-2048}"
UBATCH="${UBATCH:-512}"
THREADS="${THREADS:-16}"
THREADS_BATCH="${THREADS_BATCH:-32}"
FA="${FA:-auto}"
CTK="${CTK:-f16}"
CTV="${CTV:-f16}"
MODE="${MODE:-chat}"      # chat | code
THINKING="${THINKING:-false}"

if [[ ! -x "$CLI" ]]; then
  echo "Missing CUDA llama-cli." >&2
  echo "Set GROKSON_CLI or build with:  ./scripts/build-llama-cuda.sh" >&2
  exit 1
fi
if [[ ! -f "$MODEL" ]]; then
  echo "Missing model: $MODEL" >&2
  echo "Download with:  ./scripts/download-model.sh" >&2
  echo "Or set MODEL=/path/to/Qwen3.6-35B-A3B-NVFP4.gguf" >&2
  exit 1
fi

case "$MODE" in
  chat)
    TEMP="${TEMP:-0.7}"
    TOP_P="${TOP_P:-0.8}"
    TOP_K="${TOP_K:-20}"
    MIN_P="${MIN_P:-0.0}"
    PRESENCE="${PRESENCE:-1.5}"
    REPEAT="${REPEAT:-1.0}"
    ;;
  code)
    TEMP="${TEMP:-0.6}"
    TOP_P="${TOP_P:-0.95}"
    TOP_K="${TOP_K:-20}"
    MIN_P="${MIN_P:-0.0}"
    PRESENCE="${PRESENCE:-0.0}"
    REPEAT="${REPEAT:-1.0}"
    ;;
  *)
    echo "MODE must be chat or code (got: $MODE)" >&2
    exit 1
    ;;
esac

args=(
  -m "$MODEL"
  -ngl "$NGL"
  -c "$CTX"
  -n "$N"
  -b "$BATCH"
  -ub "$UBATCH"
  -t "$THREADS"
  -tb "$THREADS_BATCH"
  -fa "$FA"
  -ctk "$CTK"
  -ctv "$CTV"
  --temp "$TEMP"
  --top-p "$TOP_P"
  --top-k "$TOP_K"
  --min-p "$MIN_P"
  --presence-penalty "$PRESENCE"
  --repeat-penalty "$REPEAT"
  --chat-template-kwargs "{\"enable_thinking\":${THINKING}}"
  --simple-io
)

has_prompt=0
for a in "$@"; do
  case "$a" in
    -p|--prompt|-f|--file) has_prompt=1; break ;;
  esac
done
if (( has_prompt )); then
  args+=(-no-cnv --single-turn)
fi

exec "$CLI" "${args[@]}" "$@"
