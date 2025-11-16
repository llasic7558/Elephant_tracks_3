#!/bin/bash
#
# Compare different memory allocators on the same trace using LD_PRELOAD
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TRACE_FILE=""
MODE="explicit"
VERBOSE=""

usage() {
    echo "Usage: $0 -t TRACE_FILE [OPTIONS]"
    echo ""
    echo "Compare memory allocators (standard, mimalloc, jemalloc)"
    echo ""
    echo "Required:"
    echo "  -t TRACE_FILE    Path to ET trace file"
    echo ""
    echo "Options:"
    echo "  -m MODE          Mode: explicit or gc (default: explicit)"
    echo "  -v               Verbose output"
    echo "  -h               Show this help"
    echo ""
    echo "Example:"
    echo "  $0 -t ../trace_output/trace -m explicit"
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
    echo "Error: Trace file is required"
    usage
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: Trace file not found: $TRACE_FILE"
    exit 1
fi

BINARY="$PROJECT_ROOT/build/trace_replayer"
if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found: $BINARY"
    echo "Build with: make"
    exit 1
fi

RESULTS_DIR="$PROJECT_ROOT/results/allocator_comparison_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "=== Memory Allocator Comparison ==="
echo "Trace file: $TRACE_FILE"
echo "Mode:       $MODE"
echo "Results:    $RESULTS_DIR"
echo ""

# Test which allocators are available
declare -a ALLOCATORS=("standard" "mimalloc" "jemalloc")

echo "Testing allocator availability..."
for alloc in "${ALLOCATORS[@]}"; do
    echo "  Checking $alloc..."
done
echo ""

echo "Running comparisons..."
echo ""

# Function to run a single test
run_test() {
    local ALLOC=$1
    local OUTPUT="$RESULTS_DIR/${ALLOC}_${MODE}.txt"
    local TIMING_FILE="$RESULTS_DIR/${ALLOC}_${MODE}_timing.txt"
    
    echo "=========================================="
    echo "Testing: $ALLOC"
    echo "=========================================="
    
    # Run with time measurement
    local START=$(date +%s)
    
    "$SCRIPT_DIR/run_with_allocator.sh" \
        --allocator="$ALLOC" \
        -t "$TRACE_FILE" \
        -m "$MODE" \
        -e "$VERBOSE" \
        > "$OUTPUT" 2>&1 || true
    
    local END=$(date +%s)
    local ELAPSED=$((END - START))
    
    # Extract key statistics
    local PEAK_MEM=$(grep "Peak Memory Usage:" "$OUTPUT" | awk '{print $4, $5, $6, $7}' | head -1)
    local TOTAL_ALLOCS=$(grep "Total Allocations:" "$OUTPUT" | awk '{print $3}' | head -1)
    local GC_COUNT=$(grep "GC Collections:" "$OUTPUT" | awk '{print $3}' | head -1)
    local REPLAY_TIME=$(grep "Replay time:" "$OUTPUT" | awk '{print $3, $4}' | head -1)
    
    echo "Results:"
    echo "  Wall Clock Time:   ${ELAPSED}s"
    echo "  Replay Time:       $REPLAY_TIME"
    echo "  Peak Memory:       $PEAK_MEM"
    echo "  Total Allocations: $TOTAL_ALLOCS"
    if [ -n "$GC_COUNT" ]; then
        echo "  GC Collections:    $GC_COUNT"
    fi
    echo "  Output:            $OUTPUT"
    echo ""
    
    # Save timing info
    echo "$ELAPSED" > "$TIMING_FILE"
}

# Run tests for all allocators
for alloc in "${ALLOCATORS[@]}"; do
    run_test "$alloc"
done

# Generate comparison report
REPORT_FILE="$RESULTS_DIR/comparison_report.txt"

echo "=========================================="
echo "Generating Comparison Report"
echo "=========================================="

cat > "$REPORT_FILE" << EOF
Memory Allocator Comparison Report
===================================

Date: $(date)
Trace File: $TRACE_FILE
Mode: $MODE

===================================
RESULTS
===================================

EOF

for alloc in "${ALLOCATORS[@]}"; do
    echo "" >> "$REPORT_FILE"
    echo "--- $alloc ---" >> "$REPORT_FILE"
    
    OUTPUT="$RESULTS_DIR/${alloc}_${MODE}.txt"
    TIMING_FILE="$RESULTS_DIR/${alloc}_${MODE}_timing.txt"
    
    if [ -f "$TIMING_FILE" ]; then
        echo "Wall Clock Time: $(cat "$TIMING_FILE")s" >> "$REPORT_FILE"
    fi
    
    if [ -f "$OUTPUT" ]; then
        grep -A 15 "=== Memory Statistics ===" "$OUTPUT" >> "$REPORT_FILE" 2>/dev/null || true
        echo "" >> "$REPORT_FILE"
    fi
done

echo ""
echo "=========================================="
echo "Comparison Complete!"
echo "=========================================="
echo ""
echo "Report: $REPORT_FILE"
echo ""
echo "View with: cat $REPORT_FILE"
echo ""

# Display summary
echo "Summary:"
for alloc in "${ALLOCATORS[@]}"; do
    TIMING_FILE="$RESULTS_DIR/${alloc}_${MODE}_timing.txt"
    OUTPUT="$RESULTS_DIR/${alloc}_${MODE}.txt"
    
    if [ -f "$TIMING_FILE" ]; then
        TIME=$(cat "$TIMING_FILE")
        PEAK=$(grep "Peak Memory Usage:" "$OUTPUT" | awk '{print $4, $5}' | head -1)
        printf "  %-12s Time: %8ss  Peak Memory: %s\n" "$alloc" "$TIME" "$PEAK"
    fi
done
