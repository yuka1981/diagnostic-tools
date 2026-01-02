#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HPCG_REPO="https://github.com/hpcg-benchmark/hpcg.git"
HPCG_DIR="$PROJECT_ROOT/hpcg_source"
BUILD_DIR="build"
AGENT_BIN_PATH="$PROJECT_ROOT/agent/agent"

echo "=== HPCG Build and Run Script ==="

# 1. Build the Agent
echo "Building the HPC Agent..."
pushd "$PROJECT_ROOT/agent" > /dev/null
go build -o agent .
popd > /dev/null

# 2. Clone HPCG Source
if [ ! -d "$HPCG_DIR" ]; then
    echo "Cloning HPCG source from $HPCG_REPO..."
    git clone $HPCG_REPO "$HPCG_DIR"
else
    echo "HPCG source directory already exists."
fi

# 3. Use Agent to Build and Run in the source root
pushd "$HPCG_DIR" > /dev/null

echo "Starting HPCG workflow via Agent..."

$AGENT_BIN_PATH hpcg \
    --id "hpcg-source-$(date +%Y%m%d-%H%M)" \
    --build "make arch=Linux_Serial" \
    --run "./bin/xhpcg" \
    --nx 104 --ny 104 --nz 104 \
    --rt 60

popd > /dev/null

echo "=== Done ==="
