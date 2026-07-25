#!/usr/bin/env bash
# Install `grokson` on PATH and as a bash alias.
set -euo pipefail

_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$_SCRIPT")/.." && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
mkdir -p "$BIN_DIR"
ln -sfn "$ROOT/scripts/grokson.sh" "$BIN_DIR/grokson"
chmod +x "$ROOT/scripts/grokson.sh" "$BIN_DIR/grokson"

BASHRC="${BASHRC:-$HOME/.bashrc}"
MARKER="# grokson — Qwen3.6 NVFP4 via llama.cpp"
if [[ -f "$BASHRC" ]] && ! grep -qF "$MARKER" "$BASHRC"; then
  cat >> "$BASHRC" <<EOF

$MARKER
alias grokson='$BIN_DIR/grokson'
EOF
  echo "Appended alias to $BASHRC"
fi

echo "Installed: $BIN_DIR/grokson"
echo "New shells: source ~/.bashrc   (or open a new terminal)"
echo "Run:        grokson"
echo "            MODE=code grokson -p '...' -n 128"
