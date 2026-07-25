#!/usr/bin/env bash
# grokson agent — llama-server with built-in tools including bash (exec_shell_command).
# WARNING: tools run as your user with full shell access. Localhost only by default.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "${GROKSON_ENV:-$HOME/.config/grokson/env}" ]] && source "${GROKSON_ENV:-$HOME/.config/grokson/env}"
[[ -f "$ROOT/.env" ]] && source "$ROOT/.env"

MODEL="${MODEL:-${GROKSON_MODEL:-$HOME/models/Qwen3.6-35B-A3B-NVFP4-GGUF/Qwen3.6-35B-A3B-NVFP4.gguf}}"
SERVER="${SERVER:-${GROKSON_SERVER:-$HOME/.local/share/grokson/llama.cpp/build-cuda/bin/llama-server}}"
if [[ ! -x "$SERVER" ]]; then
  for cand in \
    "$HOME/Projects/builds/llama.cpp/build-cuda/bin/llama-server" \
    "$ROOT/vendor/llama.cpp/build-cuda/bin/llama-server" \
    "$(command -v llama-server 2>/dev/null || true)"; do
    [[ -n "$cand" && -x "$cand" ]] && SERVER="$cand" && break
  done
fi

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
NGL="${NGL:--1}"
CTX="${CTX:-8192}"
BATCH="${BATCH:-2048}"
UBATCH="${UBATCH:-512}"
THREADS="${THREADS:-16}"
THREADS_BATCH="${THREADS_BATCH:-32}"
FA="${FA:-auto}"
CTK="${CTK:-f16}"
CTV="${CTV:-f16}"
# Built-in tools: bash + filesystem helpers. Use TOOLS=all for everything.
# Available: read_file,file_glob_search,grep_search,exec_shell_command,write_file,edit_file,get_datetime
TOOLS="${TOOLS:-exec_shell_command,read_file,write_file,file_glob_search,grep_search,get_datetime}"
THINKING="${THINKING:-false}"
TEMP="${TEMP:-0.7}"
TOP_P="${TOP_P:-0.8}"
TOP_K="${TOP_K:-20}"
MIN_P="${MIN_P:-0.0}"
PRESENCE="${PRESENCE:-1.5}"

if [[ ! -x "$SERVER" ]]; then
  echo "Missing CUDA llama-server. Build with: ./scripts/build-llama-cuda.sh" >&2
  exit 1
fi
if [[ ! -f "$MODEL" ]]; then
  echo "Missing model: $MODEL" >&2
  echo "Download: ./scripts/download-model.sh" >&2
  exit 1
fi

echo "grokson agent"
echo "  model : $MODEL"
echo "  server: $SERVER"
echo "  tools : $TOOLS"
echo "  bind  : http://${HOST}:${PORT}"
echo "  UI    : open the URL above (WebUI agent + bash tool)"
echo
echo "  Security: exec_shell_command runs as $(whoami) with no sandbox."
echo "  Stop with Ctrl+C."
echo

exec "$SERVER" \
  -m "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  -ngl "$NGL" \
  -c "$CTX" \
  -b "$BATCH" \
  -ub "$UBATCH" \
  -t "$THREADS" \
  -tb "$THREADS_BATCH" \
  -fa "$FA" \
  -ctk "$CTK" \
  -ctv "$CTV" \
  --temp "$TEMP" \
  --top-p "$TOP_P" \
  --top-k "$TOP_K" \
  --min-p "$MIN_P" \
  --presence-penalty "$PRESENCE" \
  --chat-template-kwargs "{\"enable_thinking\":${THINKING}}" \
  --tools "$TOOLS" \
  --jinja \
  --webui \
  "$@"
