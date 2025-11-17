#!/bin/bash
# Complete Oracle Construction Pipeline
# 
# Takes an ET trace with Merlin deaths (deaths at end) and produces a complete oracle
#
# Usage: ./build_oracle_complete.sh <trace_offline> <output_dir> [--verbose]

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TRACE_OFFLINE="$1"
OUTPUT_DIR="$2"
VERBOSE=""

if [ "$3" == "--verbose" ]; then
    VERBOSE="--verbose"
fi

# Check arguments
if [ -z "$TRACE_OFFLINE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <trace_offline> <output_dir> [--verbose]"
    echo ""
    echo "Example:"
    echo "  $0 ../../test_offline_fixed/SimpleTrace/trace_offline ./output --verbose"
    exit 1
fi

# Check input file exists
if [ ! -f "$TRACE_OFFLINE" ]; then
    echo "Error: Input trace file not found: $TRACE_OFFLINE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Output file paths
TRACE_REORDERED="$OUTPUT_DIR/trace_reordered"
ORACLE_TXT="$OUTPUT_DIR/oracle.txt"
ORACLE_CSV="$OUTPUT_DIR/oracle.csv"

echo "================================"
echo "Oracle Construction Pipeline"
echo "================================"
echo "Input:  $TRACE_OFFLINE"
echo "Output: $OUTPUT_DIR"
echo ""

# Step 1: Reorder death records
echo "[Step 1/2] Reordering death records..."
python3 "$SCRIPT_DIR/reorder_deaths.py" \
    "$TRACE_OFFLINE" \
    "$TRACE_REORDERED" \
    $VERBOSE --validate

if [ $? -ne 0 ]; then
    echo "Error: Death reordering failed"
    exit 1
fi

echo "✓ Death records reordered: $TRACE_REORDERED"
echo ""

# Step 2: Build oracle
echo "[Step 2/2] Building oracle event stream..."
python3 "$SCRIPT_DIR/build_oracle.py" \
    "$TRACE_REORDERED" \
    --output "$ORACLE_TXT" \
    --csv "$ORACLE_CSV" \
    --stats \
    $VERBOSE

if [ $? -ne 0 ]; then
    echo "Error: Oracle building failed"
    exit 1
fi

echo "✓ Oracle built:"
echo "  - Text format: $ORACLE_TXT"
echo "  - CSV format:  $ORACLE_CSV"
echo ""

# Summary
echo "================================"
echo "Oracle Construction Complete!"
echo "================================"
echo ""
echo "Files created:"
echo "  1. $TRACE_REORDERED"
echo "  2. $ORACLE_TXT"
echo "  3. $ORACLE_CSV"
echo ""
echo "Quick checks:"
echo "  - View oracle: cat $ORACLE_TXT | head -20"
echo "  - Death positions: grep -n '^D' $TRACE_REORDERED | head -10"
echo "  - Load in Python: pd.read_csv('$ORACLE_CSV')"
echo ""
