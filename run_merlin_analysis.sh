#!/bin/bash

# Merlin Death Tracker - ET3 Integration Script
# This script runs ET3 to generate a trace and then applies Merlin analysis

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ET3 + Merlin Death Tracker${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Configuration
PROJECT_ROOT="/Users/luka/Desktop/Honors_Thesis/et2-java"
ET3_AGENT="javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
TEST_PROGRAM="${1:-SimpleTrace}"
OUTPUT_DIR="trace_output"
VERBOSE="${2:-false}"

# Check if ET3 agent exists
if [ ! -f "$PROJECT_ROOT/$ET3_AGENT" ]; then
    echo -e "${RED}ERROR: ET3 agent not found at $ET3_AGENT${NC}"
    echo "Please build the agent first:"
    echo "  cd javassist-inst/et2-instrumenter && mvn clean compile package"
    exit 1
fi

cd "$PROJECT_ROOT"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Step 1: Compile the test program
echo -e "${YELLOW}[1/5]${NC} Compiling $TEST_PROGRAM.java..."
if [ -f "java/$TEST_PROGRAM.java" ]; then
    javac -d "$OUTPUT_DIR" "java/$TEST_PROGRAM.java"
    echo -e "${GREEN}      ✓ Compilation successful${NC}"
else
    echo -e "${RED}ERROR: Test program not found: java/$TEST_PROGRAM.java${NC}"
    exit 1
fi

# Step 2: Run with ET3 agent to generate trace
echo -e "${YELLOW}[2/5]${NC} Running $TEST_PROGRAM with ET3 agent..."
cd "$OUTPUT_DIR"
java -javaagent:"../$ET3_AGENT" "$TEST_PROGRAM" > program_output.txt 2>&1
cd ..
echo -e "${GREEN}      ✓ Trace generated${NC}"

# Step 3: Compile MerlinDeathTracker if needed
echo -e "${YELLOW}[3/5]${NC} Compiling MerlinDeathTracker..."
MERLIN_SOURCE="javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/MerlinDeathTracker.java"
MERLIN_CLASS="javassist-inst/et2-instrumenter/target/classes/veroy/research/et2/javassist/MerlinDeathTracker.class"

if [ ! -f "$MERLIN_CLASS" ] || [ "$MERLIN_SOURCE" -nt "$MERLIN_CLASS" ]; then
    mkdir -p "javassist-inst/et2-instrumenter/target/classes"
    javac -d "javassist-inst/et2-instrumenter/target/classes" "$MERLIN_SOURCE"
    echo -e "${GREEN}      ✓ MerlinDeathTracker compiled${NC}"
else
    echo -e "${GREEN}      ✓ MerlinDeathTracker already compiled${NC}"
fi

# Step 4: Apply Merlin analysis
echo -e "${YELLOW}[4/5]${NC} Applying Merlin algorithm to reconstruct death records..."
VERBOSE_FLAG=""
if [ "$VERBOSE" = "true" ] || [ "$VERBOSE" = "--verbose" ]; then
    VERBOSE_FLAG="--verbose"
fi

if [ -f "$OUTPUT_DIR/trace" ]; then
    java -cp "javassist-inst/et2-instrumenter/target/classes" \
        veroy.research.et2.javassist.MerlinDeathTracker \
        "$OUTPUT_DIR/trace" \
        "$OUTPUT_DIR/trace_with_deaths" \
        $VERBOSE_FLAG
    echo -e "${GREEN}      ✓ Death records reconstructed${NC}"
else
    echo -e "${RED}ERROR: Trace file not found at $OUTPUT_DIR/trace${NC}"
    exit 1
fi

# Step 5: Generate summary statistics
echo -e "${YELLOW}[5/5]${NC} Generating statistics..."
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Results Summary${NC}"
echo -e "${GREEN}========================================${NC}"

ALLOC_COUNT=$(grep -c "^[NAI]" "$OUTPUT_DIR/trace" || echo "0")
UPDATE_COUNT=$(grep -c "^U" "$OUTPUT_DIR/trace" || echo "0")
METHOD_ENTRY=$(grep -c "^M" "$OUTPUT_DIR/trace" || echo "0")
METHOD_EXIT=$(grep -c "^E" "$OUTPUT_DIR/trace" || echo "0")
DEATH_COUNT=$(grep -c "^D" "$OUTPUT_DIR/trace_with_deaths" || echo "0")

echo "Test Program:        $TEST_PROGRAM"
echo "Original Trace:      $OUTPUT_DIR/trace"
echo "Enhanced Trace:      $OUTPUT_DIR/trace_with_deaths"
echo ""
echo "Trace Statistics:"
echo "  Allocations:       $ALLOC_COUNT"
echo "  Field Updates:     $UPDATE_COUNT"
echo "  Method Entries:    $METHOD_ENTRY"
echo "  Method Exits:      $METHOD_EXIT"
echo "  Deaths (Merlin):   $DEATH_COUNT"
echo ""

# Show sample death records
if [ "$DEATH_COUNT" -gt 0 ]; then
    echo -e "${GREEN}Sample Death Records:${NC}"
    grep "^D" "$OUTPUT_DIR/trace_with_deaths" | head -5
    echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Analysis Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "View the enhanced trace:"
echo "  less $OUTPUT_DIR/trace_with_deaths"
echo ""
echo "Compare original vs enhanced:"
echo "  diff $OUTPUT_DIR/trace $OUTPUT_DIR/trace_with_deaths | less"
echo ""
