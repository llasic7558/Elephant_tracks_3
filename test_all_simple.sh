#!/bin/bash

# Test ET3+Merlin on all simple test programs

set -e

ET3_AGENT="./javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
TEST_DIR="./test_traces"

echo "========================================"
echo "ET3+Merlin Test Suite"
echo "========================================"
echo ""

# Rebuild if needed
if [ ! -f "$ET3_AGENT" ]; then
    echo "Building ET3 agent..."
    cd javassist-inst/et2-instrumenter
    mvn clean compile package -q
    cd ../..
fi

# Test programs (small ones that won't hang)
TESTS=("HelloWorld" "NewCall" "Methods" "SimpleTrace")

for TEST in "${TESTS[@]}"; do
    echo "========================================"
    echo "Testing: $TEST"
    echo "========================================"
    
    TEST_OUT="${TEST_DIR}/${TEST}"
    rm -rf "$TEST_OUT"
    mkdir -p "$TEST_OUT"
    
    # Compile
    javac -d "$TEST_OUT" java/$TEST.java java/FooClass.java 2>/dev/null || javac -d "$TEST_OUT" java/$TEST.java
    
    # Run with ET3
    cd "$TEST_OUT"
    java -javaagent:../../$ET3_AGENT $TEST 2>&1 | grep -E "(Loading|Hello|SHUTDOWN|ET3)" || true
    cd ../..
    
    # Analyze trace
    if [ -f "$TEST_OUT/trace" ]; then
        ALLOCS=$(grep -c "^N " "$TEST_OUT/trace" || echo "0")
        ARRAYS=$(grep -c "^A " "$TEST_OUT/trace" || echo "0")
        METHODS=$(grep -c "^M " "$TEST_OUT/trace" || echo "0")
        EXITS=$(grep -c "^E " "$TEST_OUT/trace" || echo "0")
        UPDATES=$(grep -c "^U " "$TEST_OUT/trace" || echo "0")
        DEATHS=$(grep -c "^D " "$TEST_OUT/trace" || echo "0")
        
        echo ""
        echo "Trace Statistics:"
        echo "  Objects: $ALLOCS | Arrays: $ARRAYS | Methods: $METHODS/$EXITS | Updates: $UPDATES | Deaths: $DEATHS"
        
        echo ""
        echo "First 20 records:"
        head -20 "$TEST_OUT/trace"
        
        if [ "$DEATHS" -gt 0 ]; then
            echo ""
            echo "Death records (first 3):"
            grep "^D " "$TEST_OUT/trace" | head -3
        fi
        
    else
        echo "⚠ No trace generated"
    fi
    
    echo ""
    echo ""
done

echo "========================================"
echo "Testing: LotsOfAllocs (1000 objects)"
echo "========================================"

TEST_OUT="${TEST_DIR}/LotsOfAllocs"
rm -rf "$TEST_OUT"
mkdir -p "$TEST_OUT"

javac -d "$TEST_OUT" java/LotsOfAllocs.java java/FooClass.java

cd "$TEST_OUT"
echo "Running (this creates 1000 FooClass objects)..."
java -javaagent:../../$ET3_AGENT LotsOfAllocs 2>&1 | grep -E "(Loading|SHUTDOWN|ET3|Merlin)" || true
cd ../..

if [ -f "$TEST_OUT/trace" ]; then
    ALLOCS=$(grep -c "^N " "$TEST_OUT/trace" || echo "0")
    UPDATES=$(grep -c "^U " "$TEST_OUT/trace" || echo "0")
    DEATHS=$(grep -c "^D " "$TEST_OUT/trace" || echo "0")
    
    echo ""
    echo "Trace Statistics:"
    echo "  Objects allocated: $ALLOCS"
    echo "  Field updates (setNext calls): $UPDATES"
    echo "  Deaths detected: $DEATHS"
    
    echo ""
    echo "Sample allocation records (first 5):"
    grep "^N " "$TEST_OUT/trace" | head -5
    
    echo ""
    echo "Sample field update records (first 5):"
    grep "^U " "$TEST_OUT/trace" | head -5 || echo "  (none found)"
    
    echo ""
    echo "Sample death records (first 5):"
    grep "^D " "$TEST_OUT/trace" | head -5 || echo "  (none found)"
    
else
    echo "⚠ No trace generated"
fi

echo ""
echo ""
echo "========================================"
echo "Summary - Object Graph Reconstruction"
echo "========================================"
echo ""
echo "ET3 generates traces that allow OFFLINE object graph reconstruction:"
echo ""
echo "1. ALLOCATIONS (N/A records):"
echo "   - Create nodes in the object graph"
echo "   - Format: N <obj-id> <class-id> <site-id> <size> <alloc-count> <thread-id>"
echo ""
echo "2. FIELD UPDATES (U records):"
echo "   - Create edges in the object graph"
echo "   - Format: U <obj-id> <target-id> <field-id> <thread-id>"
echo "   - This is the POINTER GRAPH data!"
echo ""
echo "3. METHOD CALLS (M/E records):"
echo "   - Track execution timeline"
echo "   - Needed for stack roots in reachability"
echo ""
echo "4. DEATHS (D records):"
echo "   - Remove nodes from graph"
echo "   - Format: D <obj-id> <thread-id> <timestamp>"
echo ""
echo "A simulator can replay these events to:"
echo "  • Reconstruct object graph at any point in time"
echo "  • Compute heap size evolution"
echo "  • Analyze object lifetimes"
echo "  • Track reachability paths"
echo ""
echo "All traces saved in: $TEST_DIR/"
echo ""
