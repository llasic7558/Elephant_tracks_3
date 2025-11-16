#!/bin/bash
#
# Run gem5 simulation comparing explicit memory management vs GC
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPLAYER_BIN="$PROJECT_ROOT/build/trace_replayer"
CONFIG_FILE="$PROJECT_ROOT/configs/memory_comparison_config.py"
RESULTS_DIR="$PROJECT_ROOT/results"

# Default parameters
TRACE_FILE=""
GEM5_PATH="${GEM5_PATH:-/gem5}"
CPU_TYPE="timing"
CPU_CLOCK="3GHz"
MEM_SIZE="8GB"
L1I_SIZE="32kB"
L1D_SIZE="32kB"
L2_SIZE="256kB"
GC_THRESHOLD=$((10 * 1024 * 1024))  # 10 MB
GC_ALLOC_COUNT=1000
VERBOSE=""

# Parse command line arguments
usage() {
    echo "Usage: $0 -t TRACE_FILE [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -t TRACE_FILE       Path to ET trace file"
    echo ""
    echo "Options:"
    echo "  -g GEM5_PATH        Path to gem5 installation (default: /gem5)"
    echo "  -c CPU_TYPE         CPU type: atomic, timing, o3 (default: timing)"
    echo "  -f CPU_CLOCK        CPU clock frequency (default: 3GHz)"
    echo "  -m MEM_SIZE         Memory size (default: 8GB)"
    echo "  --l1i SIZE          L1 instruction cache size (default: 32kB)"
    echo "  --l1d SIZE          L1 data cache size (default: 32kB)"
    echo "  --l2 SIZE           L2 cache size (default: 256kB)"
    echo "  --gc-threshold N    GC threshold in bytes (default: 10485760)"
    echo "  --gc-alloc N        GC after N allocations (default: 1000)"
    echo "  -v                  Verbose output"
    echo "  -h                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -t ../trace_output/trace"
    echo "  $0 -t ../trace_output/trace -c o3 --l2 512kB"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t)
            TRACE_FILE="$2"
            shift 2
            ;;
        -g)
            GEM5_PATH="$2"
            shift 2
            ;;
        -c)
            CPU_TYPE="$2"
            shift 2
            ;;
        -f)
            CPU_CLOCK="$2"
            shift 2
            ;;
        -m)
            MEM_SIZE="$2"
            shift 2
            ;;
        --l1i)
            L1I_SIZE="$2"
            shift 2
            ;;
        --l1d)
            L1D_SIZE="$2"
            shift 2
            ;;
        --l2)
            L2_SIZE="$2"
            shift 2
            ;;
        --gc-threshold)
            GC_THRESHOLD="$2"
            shift 2
            ;;
        --gc-alloc)
            GC_ALLOC_COUNT="$2"
            shift 2
            ;;
        -v)
            VERBOSE="--verbose"
            shift
            ;;
        -h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$TRACE_FILE" ]; then
    echo "Error: Trace file is required (-t option)"
    usage
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: Trace file not found: $TRACE_FILE"
    exit 1
fi

if [ ! -f "$REPLAYER_BIN" ]; then
    echo "Error: TraceReplayer binary not found: $REPLAYER_BIN"
    echo "Please run ./scripts/build.sh first"
    exit 1
fi

echo "=== gem5 Memory Management Comparison ==="
echo "Trace file: $TRACE_FILE"
echo "gem5 path:  $GEM5_PATH"
echo "CPU type:   $CPU_TYPE"
echo "CPU clock:  $CPU_CLOCK"
echo "Memory:     $MEM_SIZE"
echo "L1I/L1D:    $L1I_SIZE / $L1D_SIZE"
echo "L2:         $L2_SIZE"
echo ""

# Create results directories
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPLICIT_DIR="$RESULTS_DIR/explicit_${TIMESTAMP}"
GC_DIR="$RESULTS_DIR/gc_${TIMESTAMP}"

mkdir -p "$EXPLICIT_DIR"
mkdir -p "$GC_DIR"

echo "Results will be saved to:"
echo "  Explicit: $EXPLICIT_DIR"
echo "  GC:       $GC_DIR"
echo ""

# Function to run simulation
run_simulation() {
    local MODE=$1
    local OUTPUT_DIR=$2
    
    echo ""
    echo "=========================================="
    echo "Running $MODE mode simulation..."
    echo "=========================================="
    
    if [ -f "$GEM5_PATH/build/X86/gem5.opt" ]; then
        GEM5_BIN="$GEM5_PATH/build/X86/gem5.opt"
    elif [ -f "$GEM5_PATH/build/X86/gem5.fast" ]; then
        GEM5_BIN="$GEM5_PATH/build/X86/gem5.fast"
    else
        echo "Error: gem5 binary not found in $GEM5_PATH/build/X86/"
        exit 1
    fi
    
    CMD="$GEM5_BIN \
        --outdir=$OUTPUT_DIR \
        $CONFIG_FILE \
        $REPLAYER_BIN \
        $TRACE_FILE \
        $MODE \
        --cpu-type=$CPU_TYPE \
        --cpu-clock=$CPU_CLOCK \
        --mem-size=$MEM_SIZE \
        --l1i-size=$L1I_SIZE \
        --l1d-size=$L1D_SIZE \
        --l2-size=$L2_SIZE \
        --gc-threshold=$GC_THRESHOLD \
        --gc-alloc-count=$GC_ALLOC_COUNT \
        --output-dir=$OUTPUT_DIR \
        $VERBOSE"
    
    echo "Command: $CMD"
    echo ""
    
    # Run the simulation
    eval $CMD
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "$MODE mode simulation completed successfully"
        echo "Results: $OUTPUT_DIR"
    else
        echo ""
        echo "Error: $MODE mode simulation failed"
        exit 1
    fi
}

# Check if running in gem5 Docker container or local
if [ -f "$GEM5_PATH/build/X86/gem5.opt" ] || [ -f "$GEM5_PATH/build/X86/gem5.fast" ]; then
    # Run explicit memory management simulation
    run_simulation "explicit" "$EXPLICIT_DIR"
    
    # Run GC simulation
    run_simulation "gc" "$GC_DIR"
    
    echo ""
    echo "=========================================="
    echo "Both simulations completed!"
    echo "=========================================="
    echo ""
    echo "To analyze results:"
    echo "  python3 scripts/analyze_results.py $EXPLICIT_DIR $GC_DIR --plot"
    echo ""
else
    echo ""
    echo "=========================================="
    echo "gem5 not found locally"
    echo "=========================================="
    echo ""
    echo "This script should be run inside a gem5 Docker container or"
    echo "on a system with gem5 installed."
    echo ""
    echo "To use with Docker:"
    echo "  1. Copy this directory to Docker container"
    echo "  2. Run this script inside the container"
    echo ""
    echo "Example Docker workflow:"
    echo "  docker run -it -v \$(pwd):/workspace gem5:latest /bin/bash"
    echo "  cd /workspace/gem5-simulation"
    echo "  ./scripts/run_simulation.sh -t ../trace_output/trace"
    echo ""
    exit 1
fi
