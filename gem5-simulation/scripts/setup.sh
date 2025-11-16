#!/bin/bash
#
# Setup script - verifies environment and builds everything
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== gem5 Memory Management Comparison Setup ==="
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# Function to check command availability
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" == "OK" ]; then
        echo "  [✓] $message"
    elif [ "$status" == "WARN" ]; then
        echo "  [!] $message"
    else
        echo "  [✗] $message"
    fi
}

echo "Checking requirements..."
echo ""

# Check C++ compiler
if command_exists g++; then
    GCC_VERSION=$(g++ --version | head -1)
    print_status "OK" "g++ found: $GCC_VERSION"
else
    print_status "FAIL" "g++ not found - please install a C++ compiler"
    exit 1
fi

# Check C++11 support
echo '#include <iostream>' | g++ -std=c++11 -x c++ - -o /dev/null 2>/dev/null
if [ $? -eq 0 ]; then
    print_status "OK" "C++11 support verified"
else
    print_status "FAIL" "C++11 not supported by your compiler"
    exit 1
fi

# Check Python
if command_exists python3; then
    PYTHON_VERSION=$(python3 --version)
    print_status "OK" "Python found: $PYTHON_VERSION"
else
    print_status "WARN" "python3 not found - analysis scripts will not work"
fi

# Check Python packages
if command_exists python3; then
    if python3 -c "import matplotlib" 2>/dev/null; then
        print_status "OK" "matplotlib available"
    else
        print_status "WARN" "matplotlib not found - plots will not be generated"
        echo "             Install with: pip3 install matplotlib"
    fi
    
    if python3 -c "import numpy" 2>/dev/null; then
        print_status "OK" "numpy available"
    else
        print_status "WARN" "numpy not found - some analysis features disabled"
        echo "             Install with: pip3 install numpy"
    fi
fi

# Check Docker
if command_exists docker; then
    DOCKER_VERSION=$(docker --version)
    print_status "OK" "Docker found: $DOCKER_VERSION"
    
    # Check if Docker is running
    if docker info >/dev/null 2>&1; then
        print_status "OK" "Docker daemon is running"
    else
        print_status "WARN" "Docker daemon not running"
    fi
else
    print_status "WARN" "Docker not found - gem5 simulations in Docker won't work"
fi

# Check gem5
if [ -n "$GEM5_PATH" ]; then
    if [ -d "$GEM5_PATH" ]; then
        print_status "OK" "GEM5_PATH set: $GEM5_PATH"
        
        if [ -f "$GEM5_PATH/build/X86/gem5.opt" ]; then
            print_status "OK" "gem5 binary found (opt)"
        elif [ -f "$GEM5_PATH/build/X86/gem5.fast" ]; then
            print_status "OK" "gem5 binary found (fast)"
        else
            print_status "WARN" "gem5 binary not found in $GEM5_PATH/build/X86/"
        fi
    else
        print_status "WARN" "GEM5_PATH set but directory not found: $GEM5_PATH"
    fi
else
    print_status "WARN" "GEM5_PATH not set - you'll need to run in Docker or set this"
fi

echo ""
echo "Creating directories..."

mkdir -p "$PROJECT_ROOT/build"
print_status "OK" "build/ directory"

mkdir -p "$PROJECT_ROOT/results"
print_status "OK" "results/ directory"

mkdir -p "$PROJECT_ROOT/traces"
print_status "OK" "traces/ directory"

mkdir -p "$PROJECT_ROOT/docs"
print_status "OK" "docs/ directory"

echo ""
echo "Making scripts executable..."

chmod +x "$SCRIPT_DIR"/*.sh
print_status "OK" "All scripts are now executable"

echo ""
echo "Building TraceReplayer..."

cd "$PROJECT_ROOT"
make clean > /dev/null 2>&1 || true
make all

if [ -f "$PROJECT_ROOT/build/trace_replayer" ]; then
    print_status "OK" "TraceReplayer built successfully"
    
    # Show binary info
    BINARY_SIZE=$(ls -lh "$PROJECT_ROOT/build/trace_replayer" | awk '{print $5}')
    echo "         Binary size: $BINARY_SIZE"
else
    print_status "FAIL" "TraceReplayer build failed"
    exit 1
fi

echo ""
echo "Checking for trace files..."

# Look for trace files in parent directory
TRACE_COUNT=0
if [ -f "$PROJECT_ROOT/../trace_output/trace" ]; then
    print_status "OK" "Found trace at: ../trace_output/trace"
    TRACE_COUNT=$((TRACE_COUNT + 1))
fi

if [ -f "$PROJECT_ROOT/../trace_output_integrated/trace" ]; then
    print_status "OK" "Found trace at: ../trace_output_integrated/trace"
    TRACE_COUNT=$((TRACE_COUNT + 1))
fi

if [ -d "$PROJECT_ROOT/../dacapo_traces" ]; then
    DACAPO_COUNT=$(find "$PROJECT_ROOT/../dacapo_traces" -name "trace" -type f | wc -l)
    if [ "$DACAPO_COUNT" -gt 0 ]; then
        print_status "OK" "Found $DACAPO_COUNT DaCapo trace(s)"
        TRACE_COUNT=$((TRACE_COUNT + DACAPO_COUNT))
    fi
fi

if [ "$TRACE_COUNT" -eq 0 ]; then
    print_status "WARN" "No trace files found"
    echo "         Generate traces with ET instrumentation first"
fi

echo ""
echo "=== Setup Complete ==="
echo ""

if [ "$TRACE_COUNT" -gt 0 ]; then
    echo "You can now run:"
    echo ""
    echo "  # Test locally without gem5"
    echo "  ./scripts/test_replayer.sh -t ../trace_output/trace -m explicit"
    echo "  ./scripts/test_replayer.sh -t ../trace_output/trace -m gc"
    echo ""
fi

if [ -n "$GEM5_PATH" ] && [ -f "$GEM5_PATH/build/X86/gem5.opt" ]; then
    echo "  # Run full gem5 simulation"
    echo "  ./scripts/run_simulation.sh -t ../trace_output/trace"
    echo ""
fi

if command_exists docker && docker info >/dev/null 2>&1; then
    echo "  # Run in Docker"
    echo "  ./scripts/run_in_docker.sh -t trace_output/trace"
    echo ""
fi

echo "For more information, see README.md"
echo ""

# Create a simple test if possible
if [ "$TRACE_COUNT" -gt 0 ] && [ -f "$PROJECT_ROOT/../trace_output/trace" ]; then
    echo "=== Running Quick Test ==="
    echo ""
    "$PROJECT_ROOT/build/trace_replayer" "$PROJECT_ROOT/../trace_output/trace" explicit | head -20
    echo "..."
    echo ""
    print_status "OK" "Quick test passed!"
fi
