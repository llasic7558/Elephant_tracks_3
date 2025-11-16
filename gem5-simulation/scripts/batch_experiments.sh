#!/bin/bash
#
# Run batch experiments with different configurations
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
TRACE_FILE="$1"
BATCH_RESULTS_DIR="$PROJECT_ROOT/results/batch_$(date +%Y%m%d_%H%M%S)"

if [ -z "$TRACE_FILE" ]; then
    echo "Usage: $0 <trace-file>"
    echo ""
    echo "Run batch experiments with different configurations"
    echo ""
    echo "Example:"
    echo "  $0 ../trace_output/trace"
    exit 1
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: Trace file not found: $TRACE_FILE"
    exit 1
fi

mkdir -p "$BATCH_RESULTS_DIR"

echo "=== Batch Experiment Suite ==="
echo "Trace file: $TRACE_FILE"
echo "Results dir: $BATCH_RESULTS_DIR"
echo ""

# Array of configurations to test
declare -a EXPERIMENTS=(
    "baseline:timing:3GHz:32kB:32kB:256kB:10485760:1000"
    "fast_gc:timing:3GHz:32kB:32kB:256kB:5242880:500"
    "slow_gc:timing:3GHz:32kB:32kB:256kB:20971520:2000"
    "small_cache:timing:3GHz:16kB:16kB:128kB:10485760:1000"
    "large_cache:timing:3GHz:64kB:64kB:512kB:10485760:1000"
    "fast_cpu:timing:4GHz:32kB:32kB:256kB:10485760:1000"
    "o3_baseline:o3:3GHz:32kB:32kB:256kB:10485760:1000"
)

TOTAL_EXPERIMENTS=${#EXPERIMENTS[@]}
CURRENT=0

echo "Total experiments: $((TOTAL_EXPERIMENTS * 2)) (explicit + gc for each config)"
echo ""

for exp in "${EXPERIMENTS[@]}"; do
    CURRENT=$((CURRENT + 1))
    
    # Parse configuration
    IFS=':' read -ra CONFIG <<< "$exp"
    NAME="${CONFIG[0]}"
    CPU_TYPE="${CONFIG[1]}"
    CPU_CLOCK="${CONFIG[2]}"
    L1I_SIZE="${CONFIG[3]}"
    L1D_SIZE="${CONFIG[4]}"
    L2_SIZE="${CONFIG[5]}"
    GC_THRESHOLD="${CONFIG[6]}"
    GC_ALLOC="${CONFIG[7]}"
    
    echo ""
    echo "=========================================="
    echo "Experiment $CURRENT/$TOTAL_EXPERIMENTS: $NAME"
    echo "=========================================="
    echo "Config: CPU=$CPU_TYPE@$CPU_CLOCK, L1I/D=$L1I_SIZE/$L1D_SIZE, L2=$L2_SIZE"
    echo "GC: threshold=${GC_THRESHOLD}B, alloc_count=$GC_ALLOC"
    echo ""
    
    # Create experiment directory
    EXP_DIR="$BATCH_RESULTS_DIR/$NAME"
    mkdir -p "$EXP_DIR"
    
    # Save configuration
    cat > "$EXP_DIR/config.txt" << EOF
Experiment: $NAME
CPU Type: $CPU_TYPE
CPU Clock: $CPU_CLOCK
L1I Cache: $L1I_SIZE
L1D Cache: $L1D_SIZE
L2 Cache: $L2_SIZE
GC Threshold: $GC_THRESHOLD bytes
GC Alloc Count: $GC_ALLOC
Trace File: $TRACE_FILE
Date: $(date)
EOF
    
    # Run explicit mode
    echo "Running explicit mode..."
    EXPLICIT_DIR="$EXP_DIR/explicit"
    mkdir -p "$EXPLICIT_DIR"
    
    "$PROJECT_ROOT/build/trace_replayer" \
        "$TRACE_FILE" \
        explicit \
        > "$EXPLICIT_DIR/output.txt" 2>&1
    
    # Run GC mode
    echo "Running GC mode..."
    GC_DIR="$EXP_DIR/gc"
    mkdir -p "$GC_DIR"
    
    "$PROJECT_ROOT/build/trace_replayer" \
        "$TRACE_FILE" \
        gc \
        --gc-threshold=$GC_THRESHOLD \
        --gc-alloc-count=$GC_ALLOC \
        > "$GC_DIR/output.txt" 2>&1
    
    # Quick comparison
    echo ""
    echo "Results for $NAME:"
    echo "  Explicit - $(grep "Peak Memory Usage:" "$EXPLICIT_DIR/output.txt" || echo "N/A")"
    echo "  GC       - $(grep "Peak Memory Usage:" "$GC_DIR/output.txt" || echo "N/A")"
    echo "  GC       - $(grep "GC Collections:" "$GC_DIR/output.txt" || echo "N/A")"
    
    echo "Experiment $NAME complete"
done

echo ""
echo "=========================================="
echo "All Batch Experiments Complete!"
echo "=========================================="
echo ""
echo "Results saved to: $BATCH_RESULTS_DIR"
echo ""

# Generate summary report
SUMMARY_FILE="$BATCH_RESULTS_DIR/summary.txt"
echo "Generating summary report..."

cat > "$SUMMARY_FILE" << EOF
Batch Experiment Summary
Generated: $(date)
Trace File: $TRACE_FILE
Total Experiments: $TOTAL_EXPERIMENTS

========================================
RESULTS OVERVIEW
========================================

EOF

for exp in "${EXPERIMENTS[@]}"; do
    IFS=':' read -ra CONFIG <<< "$exp"
    NAME="${CONFIG[0]}"
    
    echo "" >> "$SUMMARY_FILE"
    echo "--- $NAME ---" >> "$SUMMARY_FILE"
    
    EXPLICIT_OUT="$BATCH_RESULTS_DIR/$NAME/explicit/output.txt"
    GC_OUT="$BATCH_RESULTS_DIR/$NAME/gc/output.txt"
    
    if [ -f "$EXPLICIT_OUT" ]; then
        echo "Explicit:" >> "$SUMMARY_FILE"
        grep -A 10 "=== Memory Statistics ===" "$EXPLICIT_OUT" | head -11 >> "$SUMMARY_FILE" || true
    fi
    
    if [ -f "$GC_OUT" ]; then
        echo "" >> "$SUMMARY_FILE"
        echo "GC:" >> "$SUMMARY_FILE"
        grep -A 10 "=== Memory Statistics ===" "$GC_OUT" | head -11 >> "$SUMMARY_FILE" || true
    fi
done

echo ""
echo "Summary report: $SUMMARY_FILE"
echo ""
echo "To view summary:"
echo "  cat $SUMMARY_FILE"
echo ""
echo "To compare specific experiments:"
echo "  diff $BATCH_RESULTS_DIR/baseline/explicit/output.txt \\"
echo "       $BATCH_RESULTS_DIR/fast_gc/explicit/output.txt"
