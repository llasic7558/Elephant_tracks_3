#!/bin/bash
# Build Oracle Replay Simulator
# Follows the original paper's approach

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================"
echo "Building Oracle Replay Simulator"
echo "================================"
echo ""

cd "$PROJECT_DIR"

# Clean previous build
if [ -d "build" ]; then
    echo "Cleaning previous build..."
    make -f Makefile.oracle clean
    echo ""
fi

# Build
echo "Compiling..."
make -f Makefile.oracle

if [ $? -eq 0 ]; then
    echo ""
    echo "================================"
    echo "Build successful!"
    echo "================================"
    echo ""
    echo "Executable: build/bin/oracle_replay"
    echo ""
    echo "Test it with:"
    echo "  make -f Makefile.oracle test"
    echo ""
    echo "Or directly:"
    echo "  ./build/bin/oracle_replay --oracle path/to/oracle.csv --verbose"
    echo ""
else
    echo ""
    echo "Build failed!"
    exit 1
fi
