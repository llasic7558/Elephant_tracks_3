#!/bin/bash

# Test ET3 Offline Mode with MerlinDeathTracker
# This demonstrates the CORRECT ET3 approach: offline reconstruction

set -e

echo "========================================"
echo "ET3 Offline Mode Test"
echo "Testing MerlinDeathTracker (Post-Processing)"
echo "========================================"
echo ""

# Configuration
AGENT_JAR="javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
TEST_DIR="test_offline_mode"

# Check agent exists
if [ ! -f "$AGENT_JAR" ]; then
    echo "Building ET3 agent..."
    cd javassist-inst/et2-instrumenter
    mvn clean package -q
    cd ../..
fi

# Clean and setup
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Compile test program
echo "=== Compiling SimpleTrace ==="
javac -d "$TEST_DIR" java/SimpleTrace.java
echo "✓ Compiled"
echo ""

# Step 1: Generate trace WITHOUT death records (pure ET3)
echo "=== Step 1: Generate ET3 Trace (Offline Mode) ==="
echo "Running: java -javaagent:$AGENT_JAR SimpleTrace"
echo ""

cd "$TEST_DIR"
java -javaagent:../$AGENT_JAR SimpleTrace 2>&1 | grep -E "(ET3|SHUTDOWN|Merlin)" | tail -5

echo ""
echo "Trace generated:"
echo "  File: trace"
echo "  Lines: $(wc -l < trace | tr -d ' ')"
echo "  Allocations (N): $(grep -c '^N' trace || echo 0)"
echo "  Arrays (A): $(grep -c '^A' trace || echo 0)"
echo "  Method entries (M): $(grep -c '^M' trace || echo 0)"
echo "  Method exits (E): $(grep -c '^E' trace || echo 0)"
echo "  Field updates (U): $(grep -c '^U' trace || echo 0)"
echo "  Deaths (D): $(grep -c '^D' trace || echo 0) ← Should have deaths from online mode"
echo ""

# For this test, we need to disable online mode
# Let's check if deaths are present
DEATH_COUNT=$(grep -c '^D' trace || echo 0)
if [ "$DEATH_COUNT" -gt 0 ]; then
    echo "⚠️  NOTE: Trace contains $DEATH_COUNT death records"
    echo "   This means online MerlinTracker is still enabled"
    echo "   For pure ET3, deaths should be 0 at this step"
    echo ""
    echo "   To disable online mode, modify ETProxy.java to remove MerlinTracker calls"
    echo ""
else
    echo "✓ Pure ET3 trace (no D records - correct!)"
    echo ""
fi

# Step 2: Add death records using offline MerlinDeathTracker
echo "=== Step 2: Generate Deaths Offline (MerlinDeathTracker) ==="
echo "Running: java MerlinDeathTracker trace trace_with_deaths --verbose"
echo ""

java -cp ../$AGENT_JAR \
     veroy.research.et2.javassist.MerlinDeathTracker \
     trace \
     trace_with_deaths \
     --verbose 2>&1 | tail -20

echo ""
echo "Death records generated:"
echo "  Input file: trace ($(wc -l < trace | tr -d ' ') lines)"
echo "  Output file: trace_with_deaths ($(wc -l < trace_with_deaths | tr -d ' ') lines)"
echo "  Deaths added: $(grep -c '^D' trace_with_deaths || echo 0)"
echo ""

# Step 3: Verify and compare
echo "=== Step 3: Verification ==="
echo ""

echo "Original trace (first 20 lines):"
head -20 trace | nl
echo ""

echo "With deaths (showing D records):"
grep '^D' trace_with_deaths | head -10 | nl
echo ""

echo "=== Summary ==="
echo ""

ORIGINAL_LINES=$(wc -l < trace | tr -d ' ')
FINAL_LINES=$(wc -l < trace_with_deaths | tr -d ' ')
DEATHS=$(grep -c '^D' trace_with_deaths || echo 0)
ALLOCS=$(grep -c '^[NA]' trace || echo 0)

echo "Statistics:"
echo "  Original trace: $ORIGINAL_LINES events"
echo "  Final trace: $FINAL_LINES events"
echo "  Deaths added: $DEATHS"
echo "  Allocations: $ALLOCS"
echo ""

if [ "$DEATHS" -gt 0 ]; then
    echo "✓ MerlinDeathTracker working!"
    echo "✓ Offline reconstruction successful"
    echo ""
    echo "This is the CORRECT ET3 approach:"
    echo "  1. Generate lightweight trace at runtime (N, A, M, E, U)"
    echo "  2. Reconstruct object graph offline"
    echo "  3. Generate death records via reachability analysis"
    echo ""
else
    echo "⚠️  No deaths generated - check MerlinDeathTracker"
fi

echo "=== Files Generated ==="
ls -lh trace*
echo ""

echo "=== Test Complete ==="
echo "Output files:"
echo "  - trace: Original ET3 trace"
echo "  - trace_with_deaths: Complete trace for simulation"
echo ""
echo "Use trace_with_deaths for gem5 simulation"

cd ..
