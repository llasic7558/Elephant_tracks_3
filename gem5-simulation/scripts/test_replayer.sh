#!/bin/bash
#
# Test TraceReplayer locally without gem5
# Useful for debugging and verifying trace files
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPLAYER_BIN="$PROJECT_ROOT/build/trace_replayer"

# Default parameters
TRACE_FILE=""
MODE="explicit"
VERBOSE=""
GC_THRESHOLD=$((10 * 1024 * 1024))
GC_ALLOC_COUNT=1000

usage() {
    echo "Usage: $0 -t TRACE_FILE [OPTIONS]"
    echo ""
    echo "Test the TraceReplayer without gem5"
    echo ""
    echo "Required:"
    echo "  -t TRACE_FILE       Path to ET trace file"
    echo ""
    echo "Options:"
    echo "  -m MODE             Mode: explicit or gc (default: explicit)"
    echo "  --gc-threshold N    GC threshold in bytes (default: 10485760)"
    echo "  --gc-alloc N        GC after N allocations (default: 1000)"
    echo "  -v                  Verbose output"
    echo "  -h                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -t ../trace_output/trace"
    echo "  $0 -t ../trace_output/trace -m gc -v"
    echo "  $0 -t ../dacapo_traces/trace -m gc --gc-threshold 20971520"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t)
            TRACE_FILE="$2"
            shift 2
            ;;
        -m)
            MODE="$2"
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

if [ -z "$TRACE_FILE" ]; then
    echo "Error: Trace file is required (-t option)"
    usage
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: Trace file not found: $TRACE_FILE"
    exit 1
fi

# Build if necessary
if [ ! -f "$REPLAYER_BIN" ]; then
    echo "TraceReplayer not found, building..."
    cd "$SCRIPT_DIR"
    ./build.sh
    cd - > /dev/null
fi

echo "=== Testing TraceReplayer ==="
echo "Binary:     $REPLAYER_BIN"
echo "Trace file: $TRACE_FILE"
echo "Mode:       $MODE"
echo ""

# Count trace records
echo "Analyzing trace file..."
TOTAL_LINES=$(wc -l < "$TRACE_FILE")
ALLOC_COUNT=$(grep -c "^[NA] " "$TRACE_FILE" || true)
DEATH_COUNT=$(grep -c "^D " "$TRACE_FILE" || true)
UPDATE_COUNT=$(grep -c "^U " "$TRACE_FILE" || true)
METHOD_COUNT=$(grep -c "^[ME] " "$TRACE_FILE" || true)

echo "Trace statistics:"
echo "  Total lines:    $TOTAL_LINES"
echo "  Allocations:    $ALLOC_COUNT"
echo "  Deaths:         $DEATH_COUNT"
echo "  Field updates:  $UPDATE_COUNT"
echo "  Method events:  $METHOD_COUNT"
echo ""

# Build command
CMD="$REPLAYER_BIN $TRACE_FILE $MODE"

if [ "$MODE" == "gc" ]; then
    CMD="$CMD --gc-threshold=$GC_THRESHOLD --gc-alloc-count=$GC_ALLOC_COUNT"
fi

if [ -n "$VERBOSE" ]; then
    CMD="$CMD --verbose"
fi

echo "Running command:"
echo "  $CMD"
echo ""
echo "=========================================="

# Run with timing
START_TIME=$(date +%s)
eval $CMD
END_TIME=$(date +%s)

ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Test completed in $ELAPSED seconds"
echo ""

# Show memory usage if available
if command -v /usr/bin/time &> /dev/null; then
    echo "Running again with detailed memory measurement..."
    /usr/bin/time -l $CMD 2>&1 | grep -E "(maximum resident|peak memory)" || true
fi

echo ""
echo "=== Test Successful ==="
