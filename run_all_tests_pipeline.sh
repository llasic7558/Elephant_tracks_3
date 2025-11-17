#!/bin/bash
#
# Complete ET3 Offline Pipeline - All Tests
#
# This script runs all Java tests through the complete offline Merlin pipeline:
# 1. Generate runtime traces (no deaths)
# 2. Add deaths offline with MerlinDeathTracker
# 3. Reorder deaths to correct temporal positions
# 4. Build oracle for gem5 simulation
#

set -e

echo "════════════════════════════════════════════════════════════════════════════"
echo "ET3 Complete Offline Pipeline - All Tests"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Configuration
BASE_DIR="/Users/luka/Desktop/Honors_Thesis/et2-java"
AGENT_JAR="$BASE_DIR/javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
OUTPUT_DIR="$BASE_DIR/pipeline_results"
SCRIPTS_DIR="$BASE_DIR/gem5-simulation/scripts"

# Test programs (excluding FooClass.java which is a helper class)
TESTS=("SimpleTrace" "HelloWorld" "Methods" "NewCall" "LotsOfAllocs")

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."
if [ ! -f "$AGENT_JAR" ]; then
    echo "ERROR: Agent JAR not found. Building..."
    cd "$BASE_DIR/javassist-inst/et2-instrumenter"
    mvn clean package -q
    cd "$BASE_DIR"
fi

if [ ! -f "$SCRIPTS_DIR/reorder_deaths.py" ]; then
    echo "ERROR: reorder_deaths.py not found at $SCRIPTS_DIR"
    exit 1
fi

if [ ! -f "$SCRIPTS_DIR/build_oracle.py" ]; then
    echo "ERROR: build_oracle.py not found at $SCRIPTS_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Clean and create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Summary counters
total_tests=0
successful_tests=0
failed_tests=0

# Process each test
for test in "${TESTS[@]}"; do
    total_tests=$((total_tests + 1))
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Test $total_tests/${#TESTS[@]}: $test${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    TEST_DIR="$OUTPUT_DIR/$test"
    mkdir -p "$TEST_DIR"
    
    # Step 1: Compile test program
    echo -e "${YELLOW}[1/5]${NC} Compiling $test..."
    if [ "$test" == "LotsOfAllocs" ]; then
        # LotsOfAllocs requires FooClass
        javac -d "$TEST_DIR" "$BASE_DIR/java/LotsOfAllocs.java" "$BASE_DIR/java/FooClass.java" 2>/dev/null
    elif [ "$test" == "NewCall" ]; then
        # NewCall also requires FooClass
        javac -d "$TEST_DIR" "$BASE_DIR/java/NewCall.java" "$BASE_DIR/java/FooClass.java" 2>/dev/null
    else
        javac -d "$TEST_DIR" "$BASE_DIR/java/$test.java" 2>/dev/null
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "  ${GREEN}✗ Compilation failed${NC}"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    echo -e "  ${GREEN}✓ Compiled${NC}"
    
    # Step 2: Run with ET3 agent (generate trace without deaths)
    echo -e "${YELLOW}[2/5]${NC} Generating runtime trace (offline mode)..."
    cd "$TEST_DIR"
    java -javaagent:"$AGENT_JAR" $test > program_output.txt 2>&1
    EXIT_CODE=$?
    cd "$BASE_DIR"
    
    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "  ${GREEN}✗ Runtime failed (exit code: $EXIT_CODE)${NC}"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    if [ ! -f "$TEST_DIR/trace" ]; then
        echo -e "  ${GREEN}✗ No trace file generated${NC}"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    # Analyze runtime trace
    TOTAL_LINES=$(wc -l < "$TEST_DIR/trace" | tr -d ' ')
    M_COUNT=$(grep -c '^M' "$TEST_DIR/trace" || echo 0)
    E_COUNT=$(grep -c '^E' "$TEST_DIR/trace" || echo 0)
    N_COUNT=$(grep -c '^N' "$TEST_DIR/trace" || echo 0)
    A_COUNT=$(grep -c '^A' "$TEST_DIR/trace" || echo 0)
    U_COUNT=$(grep -c '^U' "$TEST_DIR/trace" || echo 0)
    W_COUNT=$(grep -c '^W' "$TEST_DIR/trace" || echo 0)
    D_COUNT_BEFORE=$(grep -c '^D' "$TEST_DIR/trace" || echo 0)
    ALLOC_COUNT=$((N_COUNT + A_COUNT))
    
    echo -e "  ${GREEN}✓ Trace generated: $TOTAL_LINES lines${NC}"
    echo "     M=$M_COUNT E=$E_COUNT N=$N_COUNT A=$A_COUNT U=$U_COUNT W=$W_COUNT D=$D_COUNT_BEFORE"
    
    if [ $D_COUNT_BEFORE -gt 0 ]; then
        echo -e "  ${YELLOW}⚠ WARNING: Found $D_COUNT_BEFORE death records (should be 0 in offline mode)${NC}"
    fi
    
    # Step 3: Add deaths with offline Merlin
    echo -e "${YELLOW}[3/5]${NC} Adding death records (MerlinDeathTracker)..."
    java -cp "$AGENT_JAR" veroy.research.et2.javassist.MerlinDeathTracker \
        "$TEST_DIR/trace" \
        "$TEST_DIR/trace_with_deaths" \
        > "$TEST_DIR/merlin_output.txt" 2>&1
    
    if [ ! -f "$TEST_DIR/trace_with_deaths" ]; then
        echo -e "  ${GREEN}✗ Merlin processing failed${NC}"
        cat "$TEST_DIR/merlin_output.txt"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    D_COUNT_AFTER=$(grep -c '^D' "$TEST_DIR/trace_with_deaths" || echo 0)
    echo -e "  ${GREEN}✓ Deaths added: $D_COUNT_AFTER${NC}"
    
    # Step 4: Reorder deaths to correct temporal positions
    echo -e "${YELLOW}[4/5]${NC} Reordering deaths..."
    python3 "$SCRIPTS_DIR/reorder_deaths.py" \
        "$TEST_DIR/trace_with_deaths" \
        "$TEST_DIR/trace_reordered" \
        > "$TEST_DIR/reorder_output.txt" 2>&1
    
    if [ ! -f "$TEST_DIR/trace_reordered" ]; then
        echo -e "  ${GREEN}✗ Reordering failed${NC}"
        cat "$TEST_DIR/reorder_output.txt"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    REORDERED_LINES=$(wc -l < "$TEST_DIR/trace_reordered" | tr -d ' ')
    echo -e "  ${GREEN}✓ Reordered: $REORDERED_LINES lines${NC}"
    
    # Step 5: Build oracle for gem5 simulation
    echo -e "${YELLOW}[5/5]${NC} Building oracle..."
    python3 "$SCRIPTS_DIR/build_oracle.py" \
        "$TEST_DIR/trace_reordered" \
        --output "$TEST_DIR/oracle.txt" \
        --csv "$TEST_DIR/oracle.csv" \
        --stats \
        > "$TEST_DIR/oracle_output.txt" 2>&1
    
    if [ ! -f "$TEST_DIR/oracle.csv" ]; then
        echo -e "  ${GREEN}✗ Oracle building failed${NC}"
        cat "$TEST_DIR/oracle_output.txt"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    # Parse oracle statistics
    ORACLE_EVENTS=$(wc -l < "$TEST_DIR/oracle.csv" | tr -d ' ')
    ORACLE_EVENTS=$((ORACLE_EVENTS - 1))  # Subtract header
    echo -e "  ${GREEN}✓ Oracle built: $ORACLE_EVENTS events${NC}"
    
    # Create summary file
    cat > "$TEST_DIR/SUMMARY.txt" << EOF
═══════════════════════════════════════════════════════════════════
$test - Pipeline Summary
═══════════════════════════════════════════════════════════════════

Runtime Trace (trace):
  Total lines: $TOTAL_LINES
  Method entries (M): $M_COUNT
  Method exits (E): $E_COUNT
  Allocations (N): $N_COUNT
  Arrays (A): $A_COUNT
  Field updates (U): $U_COUNT
  Witness/GetField (W): $W_COUNT
  Deaths (D): $D_COUNT_BEFORE (should be 0 in offline mode)

Offline Merlin Processing (trace_with_deaths):
  Deaths added: $D_COUNT_AFTER
  Total lines: $(wc -l < "$TEST_DIR/trace_with_deaths" | tr -d ' ')

After Reordering (trace_reordered):
  Total lines: $REORDERED_LINES
  Deaths in correct positions

Oracle (oracle.csv):
  Total events: $ORACLE_EVENTS
  Format: CSV with timestamp, event_type, object_id, size, etc.

Files Generated:
  - trace                 : Runtime trace (no deaths)
  - trace_with_deaths     : Deaths appended at end
  - trace_reordered       : Deaths in correct temporal order
  - oracle.txt            : Human-readable oracle
  - oracle.csv            : Machine-readable oracle for gem5
  - program_output.txt    : Program stdout/stderr
  - merlin_output.txt     : MerlinDeathTracker output
  - reorder_output.txt    : Reordering script output
  - oracle_output.txt     : Oracle builder output and statistics

═══════════════════════════════════════════════════════════════════
EOF
    
    successful_tests=$((successful_tests + 1))
    echo -e "${GREEN}✓ Pipeline complete for $test${NC}"
    echo ""
done

# Final summary
echo "════════════════════════════════════════════════════════════════════════════"
echo "FINAL SUMMARY"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Total tests: $total_tests"
echo -e "${GREEN}Successful: $successful_tests${NC}"
if [ $failed_tests -gt 0 ]; then
    echo -e "${YELLOW}Failed: $failed_tests${NC}"
fi
echo ""
echo "Results directory: $OUTPUT_DIR"
echo ""

# Create master summary
cat > "$OUTPUT_DIR/MASTER_SUMMARY.txt" << EOF
════════════════════════════════════════════════════════════════════════════
ET3 Offline Pipeline - Master Summary
Generated: $(date)
════════════════════════════════════════════════════════════════════════════

Configuration:
  Agent JAR: $AGENT_JAR
  Output Directory: $OUTPUT_DIR
  
Tests Processed: $total_tests
Successful: $successful_tests
Failed: $failed_tests

Test Results:
EOF

for test in "${TESTS[@]}"; do
    if [ -f "$OUTPUT_DIR/$test/SUMMARY.txt" ]; then
        echo "" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "─────────────────────────────────────────────────────────────────────────" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "$test" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "─────────────────────────────────────────────────────────────────────────" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        
        # Extract key stats
        ALLOCS=$(grep "^  Allocations (N):" "$OUTPUT_DIR/$test/SUMMARY.txt" | awk '{print $3}')
        ARRAYS=$(grep "^  Arrays (A):" "$OUTPUT_DIR/$test/SUMMARY.txt" | awk '{print $3}')
        DEATHS=$(grep "^  Deaths added:" "$OUTPUT_DIR/$test/SUMMARY.txt" | awk '{print $3}')
        ORACLE=$(grep "^  Total events:" "$OUTPUT_DIR/$test/SUMMARY.txt" | awk '{print $3}')
        
        echo "  Allocations: $ALLOCS (N) + $ARRAYS (A) = $((ALLOCS + ARRAYS))" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "  Deaths: $DEATHS" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "  Oracle events: $ORACLE" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "  ✓ Complete" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
    else
        echo "" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "─────────────────────────────────────────────────────────────────────────" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "$test" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "─────────────────────────────────────────────────────────────────────────" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
        echo "  ✗ FAILED" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
    fi
done

echo "" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "════════════════════════════════════════════════════════════════════════════" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "Next Steps:" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "  1. Review oracle CSV files for gem5 simulation" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "  2. Use oracle.csv files as input to memory allocator simulation" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "  3. Compare allocator performance across different test workloads" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"
echo "" >> "$OUTPUT_DIR/MASTER_SUMMARY.txt"

if [ $successful_tests -eq $total_tests ]; then
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ ALL TESTS COMPLETED SUCCESSFULLY${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⚠ $failed_tests test(s) failed - see individual directories for details${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════${NC}"
fi

echo ""
echo "Master summary: $OUTPUT_DIR/MASTER_SUMMARY.txt"
echo ""
