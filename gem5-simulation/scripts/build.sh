#!/bin/bash
#
# Build script for TraceReplayer
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"
BUILD_DIR="$PROJECT_ROOT/build"

echo "=== Building TraceReplayer ==="
echo "Project root: $PROJECT_ROOT"
echo "Source dir: $SRC_DIR"
echo "Build dir: $BUILD_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"

# Detect OS and set appropriate flags
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    CXX_FLAGS="-std=c++11 -O3 -Wall -Wextra"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux"
    CXX_FLAGS="-std=c++11 -O3 -Wall -Wextra -static"
else
    echo "Unknown OS: $OSTYPE"
    CXX_FLAGS="-std=c++11 -O3 -Wall -Wextra"
fi

# Build
echo ""
echo "Compiling TraceReplayer.cpp..."
g++ $CXX_FLAGS -o "$BUILD_DIR/trace_replayer" "$SRC_DIR/TraceReplayer.cpp"

if [ $? -eq 0 ]; then
    echo ""
    echo "=== Build Successful ==="
    echo "Binary location: $BUILD_DIR/trace_replayer"
    
    # Show file info
    ls -lh "$BUILD_DIR/trace_replayer"
    
    # Test run to show usage
    echo ""
    echo "=== Usage ==="
    "$BUILD_DIR/trace_replayer" 2>&1 || true
else
    echo ""
    echo "=== Build Failed ==="
    exit 1
fi
