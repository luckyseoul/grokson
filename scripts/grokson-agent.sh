#!/usr/bin/env bash
# grokson agent — llama-server with bash tools, bound for LAN access (headless host).
# WARNING: tools run as your user with full shell access. Anyone who can reach PORT can drive the shell.
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

# Headless / multi-node: listen on all interfaces by default
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
# llama-server forces CORS to localhost when --tools is set unless we override explicitly
CORS_ORIGINS="${CORS_ORIGINS:-*}"
NGL="${NGL:--1}"
CTX="${CTX:-8192}"
BATCH="${BATCH:-2048}"
UBATCH="${UBATCH:-512}"
THREADS="${THREADS:-16}"
THREADS_BATCH="${THREADS_BATCH:-32}"
FA="${FA:-auto}"
CTK="${CTK:-f16}"
CTV="${CTV:-f16}"
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

# Best-effort LAN addresses for other nodes
mapfile -t LAN_IPS < <(
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | grep -v '^127\.' || true
)
if [[ ${#LAN_IPS[@]} -eq 0 ]]; then
  LAN_IPS=("$(hostname -f 2>/dev/null || hostname)")
fi

echo "grokson agent (network)"
echo "  model : $MODEL"
echo "  server: $SERVER"
echo "  tools : $TOOLS"
echo "  bind  : http://${HOST}:${PORT}"
echo "  cors  : ${CORS_ORIGINS}"
echo "  from other nodes:"
for ip in "${LAN_IPS[@]}"; do
  echo "    http://${ip}:${PORT}"
  echo "    OpenAI base: http://${ip}:${PORT}/v1"
done
echo
echo "  Security: shell tools run as $(whoami). This is reachable on the LAN."
echo "  Firewall: ensure TCP ${PORT} is open if you use one."
echo "  Stop with Ctrl+C."
echo

exec "$SERVER" \
  -m "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  --cors-origins "$CORS_ORIGINS" \
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
