#!/usr/bin/env bash
# Build llama.cpp with CUDA for older GPUs (e.g. V100 = sm_70).
# Handles two common host-toolchain footguns:
#   1) GCC 15+ rejected by CUDA 12.x → prefer gcc-14 if present
#   2) CUDA 12.8 + libstdc++ noexcept clash on rsqrt/sinpi/cospi → patch include tree
#
# Usage:
#   ./scripts/build-llama-cuda.sh
#   CUDA_ARCH=70 ./scripts/build-llama-cuda.sh
#   CUDA_HOME=/usr/local/cuda-12.8 PREFIX=$HOME/.local/share/grokson ./scripts/build-llama-cuda.sh
set -euo pipefail

_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$_SCRIPT")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local/share/grokson}"
LLAMA_DIR="${LLAMA_DIR:-$PREFIX/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_DIR/build-cuda}"
CUDA_HOME="${CUDA_HOME:-${CUDA_PATH:-/usr/local/cuda-12.8}}"
# Volta V100=70, T4=75, A100=80, 30xx=86, 40xx=89, 50xx=120
CUDA_ARCH="${CUDA_ARCH:-70}"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -x "$CUDA_HOME/bin/nvcc" ]]; then
  echo "nvcc not found under CUDA_HOME=$CUDA_HOME" >&2
  exit 1
fi

export PATH="$CUDA_HOME/bin:$PATH"

# Prefer a CUDA-supported host compiler
if command -v g++-14 >/dev/null 2>&1; then
  export CC="${CC:-gcc-14}"
  export CXX="${CXX:-g++-14}"
  export CUDAHOSTCXX="${CUDAHOSTCXX:-g++-14}"
elif command -v g++-13 >/dev/null 2>&1; then
  export CC="${CC:-gcc-13}"
  export CXX="${CXX:-g++-13}"
  export CUDAHOSTCXX="${CUDAHOSTCXX:-g++-13}"
else
  export CC="${CC:-gcc}"
  export CXX="${CXX:-g++}"
  export CUDAHOSTCXX="${CUDAHOSTCXX:-$CXX}"
fi

echo "==> Host C++: $CXX  CUDA: $CUDA_HOME  ARCH: sm_$CUDA_ARCH"

# Patch a private copy of CUDA headers if the known noexcept bug is present
PATCH_ROOT="$PREFIX/cuda-host-fix"
INC_SRC="$CUDA_HOME/targets/x86_64-linux/include"
[[ -d "$INC_SRC" ]] || INC_SRC="$CUDA_HOME/include"
PATCH_INC=""
if [[ -f "$INC_SRC/crt/math_functions.hpp" ]]; then
  mkdir -p "$PATCH_ROOT"
  if [[ ! -d "$PATCH_ROOT/include-full" ]]; then
    echo "==> Copying CUDA headers for local noexcept patch"
    cp -a "$INC_SRC" "$PATCH_ROOT/include-full"
  fi
  HPP="$PATCH_ROOT/include-full/crt/math_functions.hpp"
  python3 - <<'PY' "$HPP"
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
repls = [
    ("__MATH_FUNCTIONS_DECL__ float rsqrt(const float a)\n{",
     "__MATH_FUNCTIONS_DECL__ float rsqrt(const float a) noexcept(true)\n{"),
    ("__MATH_FUNCTIONS_DECL__ float sinpi(const float a)\n{",
     "__MATH_FUNCTIONS_DECL__ float sinpi(const float a) noexcept(true)\n{"),
    ("__MATH_FUNCTIONS_DECL__ float cospi(const float a)\n{",
     "__MATH_FUNCTIONS_DECL__ float cospi(const float a) noexcept(true)\n{"),
]
changed = False
for old, new in repls:
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
if changed:
    p.write_text(t)
    print("patched", p)
else:
    print("no patch needed (already applied or different CUDA headers)")
PY
  PATCH_INC="$PATCH_ROOT/include-full"
fi

if [[ ! -d "$LLAMA_DIR/.git" ]]; then
  echo "==> Cloning llama.cpp → $LLAMA_DIR"
  mkdir -p "$(dirname "$LLAMA_DIR")"
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
else
  echo "==> Using existing $LLAMA_DIR"
fi

CMAKE_EXTRA=()
if [[ -n "$PATCH_INC" ]]; then
  CMAKE_EXTRA+=(-DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets -I${PATCH_INC}")
  CMAKE_EXTRA+=(-DCMAKE_CXX_FLAGS="-I${PATCH_INC}")
else
  CMAKE_EXTRA+=(-DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets")
fi

cmake -S "$LLAMA_DIR" -B "$BUILD_DIR" \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
  -DGGML_CUDA_F16=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_CUDA_HOST_COMPILER="$CUDAHOSTCXX" \
  "${CMAKE_EXTRA[@]}"

cmake --build "$BUILD_DIR" --config Release -j"$JOBS" --target llama-cli llama-server

echo
echo "Built:"
echo "  $BUILD_DIR/bin/llama-cli"
echo "  $BUILD_DIR/bin/llama-server"
echo
echo "Export for grokson:"
echo "  export GROKSON_CLI=$BUILD_DIR/bin/llama-cli"
