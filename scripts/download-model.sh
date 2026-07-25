#!/usr/bin/env bash
# Download Qwen3.6-35B-A3B NVFP4 GGUF (weights stay NVFP4; runtime dequants on older GPUs).
set -euo pipefail

DEST="${DEST:-$HOME/models/Qwen3.6-35B-A3B-NVFP4-GGUF}"
REPO="${REPO:-knoopx/Qwen3.6-35B-A3B-NVFP4-GGUF}"
FILE="${FILE:-Qwen3.6-35B-A3B-NVFP4.gguf}"

mkdir -p "$DEST"

if command -v hf >/dev/null 2>&1; then
  hf download "$REPO" "$FILE" --local-dir "$DEST"
elif command -v huggingface-cli >/dev/null 2>&1; then
  huggingface-cli download "$REPO" "$FILE" --local-dir "$DEST"
else
  echo "Install Hugging Face CLI:  pip install -U huggingface_hub" >&2
  echo "Then:  hf download $REPO $FILE --local-dir $DEST" >&2
  exit 1
fi

echo
echo "Model path:"
echo "  $DEST/$FILE"
echo
echo "  export GROKSON_MODEL=$DEST/$FILE"
echo "  # or:  MODEL=$DEST/$FILE grokson"
