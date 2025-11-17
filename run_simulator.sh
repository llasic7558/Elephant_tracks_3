#!/bin/bash
# Complete workflow to run ET2 simulator on ET3 traces

set -e

TRACE_DIR=$1

if [ $# -eq 0 ]; then
    echo "Usage: $0 <trace_directory>"
    echo "Example: $0 pipeline_results/SimpleTrace"
    exit 1
fi

if [ ! -d "$TRACE_DIR" ]; then
    echo "Error: Directory $TRACE_DIR does not exist"
    exit 1
fi

echo "=== Running ET2 Simulator on ET3 Traces ==="
echo ""

# Step 1: Convert metadata
echo "Step 1: Converting metadata files..."
./convert_metadata.sh "$TRACE_DIR"
echo ""

# Step 2: Filter trace (remove W and D records that simulator doesn't support)
echo "Step 2: Filtering trace (removing W and D records)..."
grep -E '^[MENAU]' "$TRACE_DIR/trace" > "$TRACE_DIR/trace_filtered"
FILTERED_COUNT=$(wc -l < "$TRACE_DIR/trace_filtered")
echo "  ✓ Created filtered trace: $FILTERED_COUNT records"
echo ""

# Step 3: Run simulator
echo "Step 3: Running simulator..."
BASENAME=$(basename "$TRACE_DIR")
OUTPUT_BASE="simulator_output_$BASENAME"

echo "  Command: cat $TRACE_DIR/trace_filtered | simulator/build/simulator SIM \\"
echo "    $TRACE_DIR/classes.txt \\"
echo "    $TRACE_DIR/fields.txt \\"
echo "    $TRACE_DIR/methods.txt \\"
echo "    $OUTPUT_BASE \\"
echo "    NOCYCLE NOOBJDEBUG \\"
echo "    $BASENAME main"
echo ""

cat "$TRACE_DIR/trace_filtered" | \
  simulator/build/simulator SIM \
  "$TRACE_DIR/classes.txt" \
  "$TRACE_DIR/fields.txt" \
  "$TRACE_DIR/methods.txt" \
  "$OUTPUT_BASE" \
  NOCYCLE NOOBJDEBUG \
  "$BASENAME" main 2>&1 | tee "$TRACE_DIR/simulator_output.log"

echo ""
echo "=== Simulator Complete ==="
echo "Output saved to: $TRACE_DIR/simulator_output.log"
