#!/bin/bash

# Test ET3+Merlin on all test programs and analyze traces

set -e

ET3_AGENT="./javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
TEST_DIR="./test_traces"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ET3+Merlin Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check agent exists
if [ ! -f "$ET3_AGENT" ]; then
    echo "Building ET3 agent..."
    cd javassist-inst/et2-instrumenter
    mvn clean compile package -q
    cd ../..
fi

# Test programs
TESTS=("HelloWorld" "NewCall" "Methods" "LotsOfAllocs" "SimpleTrace")

for TEST in "${TESTS[@]}"; do
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Testing: $TEST${NC}"
    echo -e "${GREEN}======================================${NC}"
    
    # Create test directory
    TEST_OUT="${TEST_DIR}/${TEST}"
    rm -rf "$TEST_OUT"
    mkdir -p "$TEST_OUT"
    
    # Compile
    echo "Compiling $TEST.java..."
    javac -d "$TEST_OUT" java/$TEST.java java/FooClass.java 2>/dev/null || javac -d "$TEST_OUT" java/$TEST.java
    
    # Run with ET3
    echo "Running with ET3+Merlin..."
    cd "$TEST_OUT"
    timeout 30 java -javaagent:../../$ET3_AGENT $TEST 2>&1 | grep -E "(Loading|SHUTDOWN|ET3)" || true
    cd ../..
    
    # Analyze trace
    if [ -f "$TEST_OUT/trace" ]; then
        echo ""
        echo -e "${YELLOW}Trace Analysis:${NC}"
        
        TOTAL_LINES=$(wc -l < "$TEST_OUT/trace")
        ALLOCS=$(grep -c "^N " "$TEST_OUT/trace" || echo "0")
        ARRAYS=$(grep -c "^A " "$TEST_OUT/trace" || echo "0")
        METHODS=$(grep -c "^M " "$TEST_OUT/trace" || echo "0")
        EXITS=$(grep -c "^E " "$TEST_OUT/trace" || echo "0")
        UPDATES=$(grep -c "^U " "$TEST_OUT/trace" || echo "0")
        DEATHS=$(grep -c "^D " "$TEST_OUT/trace" || echo "0")
        
        echo "  Total records: $TOTAL_LINES"
        echo "  Object allocs (N): $ALLOCS"
        echo "  Array allocs (A): $ARRAYS"
        echo "  Method entries (M): $METHODS"
        echo "  Method exits (E): $EXITS"
        echo "  Field updates (U): $UPDATES"
        echo "  Deaths (D): $DEATHS"
        
        # Show first few records
        echo ""
        echo -e "${YELLOW}First 15 trace records:${NC}"
        head -15 "$TEST_OUT/trace" | cat -n
        
        # Show sample deaths if any
        if [ "$DEATHS" -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}Sample death records (first 5):${NC}"
            grep "^D " "$TEST_OUT/trace" | head -5
        fi
        
        # Validation
        echo ""
        echo -e "${YELLOW}Validation:${NC}"
        TOTAL_ALLOCS=$((ALLOCS + ARRAYS))
        
        if [ "$TOTAL_ALLOCS" -gt 0 ]; then
            echo "  ✓ Allocations recorded"
        else
            echo "  ⚠ No allocations (unusual)"
        fi
        
        if [ "$METHODS" -gt 0 ]; then
            echo "  ✓ Method calls tracked"
        fi
        
        if [ "$UPDATES" -gt 0 ]; then
            echo "  ✓ Field updates recorded (object graph data)"
        fi
        
        if [ "$DEATHS" -gt 0 ]; then
            echo "  ✓ Deaths detected by Merlin"
            if [ "$DEATHS" -le "$TOTAL_ALLOCS" ]; then
                echo "  ✓ Deaths ≤ Allocations (valid)"
            else
                echo "  ⚠ Deaths > Allocations (BUG!)"
            fi
        else
            if [ "$TOTAL_ALLOCS" -gt 0 ]; then
                echo "  ⚠ No deaths (objects still live at shutdown?)"
            fi
        fi
        
        echo ""
    else
        echo -e "${YELLOW}⚠ No trace file generated${NC}"
    fi
    
    echo ""
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "All test traces saved in: $TEST_DIR/"
echo ""
echo "To examine a specific trace:"
echo "  less $TEST_DIR/HelloWorld/trace"
echo "  less $TEST_DIR/NewCall/trace"
echo "  less $TEST_DIR/LotsOfAllocs/trace"
echo ""
echo "Trace format:"
echo "  N = Object allocation"
echo "  A = Array allocation"
echo "  M = Method entry"
echo "  E = Method exit"
echo "  U = Field update (object graph!)"
echo "  D = Object death (Merlin)"
echo ""
