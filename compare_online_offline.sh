#!/bin/bash

# Compare Online (MerlinTracker) vs Offline (MerlinDeathTracker) implementations
# Tests if both produce equivalent death records

set -e

echo "========================================================================"
echo "ET3 + Merlin: Online vs Offline Comparison"
echo "========================================================================"
echo ""
echo "This script compares two implementations:"
echo "  1. Online (MerlinTracker) - Real-time death tracking"
echo "  2. Offline (MerlinDeathTracker) - Post-processing"
echo ""
echo "Goal: Verify both produce equivalent death records"
echo "========================================================================"
echo ""

# Configuration
AGENT_JAR="javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
TESTS=("SimpleTrace" "LotsOfAllocs" "Methods" "NewCall" "HelloWorld")

# Check agent exists
if [ ! -f "$AGENT_JAR" ]; then
    echo "Building ET3 agent..."
    cd javassist-inst/et2-instrumenter
    mvn clean package -q
    cd ../..
fi

# Clean old results
rm -rf test_traces_online test_traces_offline comparison_results
mkdir -p comparison_results

# Function to run a test in online mode
run_online() {
    local test_name=$1
    local test_dir="test_traces_online/$test_name"
    
    echo "  Running with online MerlinTracker..."
    mkdir -p "$test_dir"
    
    # Compile
    if [ "$test_name" == "LotsOfAllocs" ]; then
        javac -d "$test_dir" java/LotsOfAllocs.java java/FooClass.java 2>/dev/null
    else
        javac -d "$test_dir" java/$test_name.java 2>/dev/null
    fi
    
    # Run with online Merlin (current implementation)
    cd "$test_dir"
    java -javaagent:../../$AGENT_JAR $test_name >/dev/null 2>&1 || true
    cd ../..
    
    if [ -f "$test_dir/trace" ]; then
        echo "    ✓ Online trace generated: $(wc -l < $test_dir/trace | tr -d ' ') lines"
        return 0
    else
        echo "    ✗ Failed to generate online trace"
        return 1
    fi
}

# Function to run a test in offline mode
run_offline() {
    local test_name=$1
    local test_dir="test_traces_offline/$test_name"
    
    echo "  Running with offline MerlinDeathTracker..."
    mkdir -p "$test_dir"
    
    # Compile
    if [ "$test_name" == "LotsOfAllocs" ]; then
        javac -d "$test_dir" java/LotsOfAllocs.java java/FooClass.java 2>/dev/null
    else
        javac -d "$test_dir" java/$test_name.java 2>/dev/null
    fi
    
    # Run WITHOUT Merlin (would need to modify ETProxy, but for now we'll process the trace)
    cd "$test_dir"
    java -javaagent:../../$AGENT_JAR $test_name >/dev/null 2>&1 || true
    
    # Now run MerlinDeathTracker on the trace
    if [ -f "trace" ]; then
        echo "    ✓ ET3 trace generated: $(wc -l < trace | tr -d ' ') lines"
        
        # Remove existing D records from input (since online mode is still active)
        grep -v "^D " trace > trace_no_deaths 2>/dev/null || cp trace trace_no_deaths
        
        # Run offline Merlin
        java -cp ../../$AGENT_JAR \
             veroy.research.et2.javassist.MerlinDeathTracker \
             trace_no_deaths \
             trace_with_offline_deaths \
             >/dev/null 2>&1 || true
        
        if [ -f "trace_with_offline_deaths" ]; then
            echo "    ✓ Offline deaths added: $(wc -l < trace_with_offline_deaths | tr -d ' ') lines"
            cd ../..
            return 0
        else
            echo "    ✗ Failed to generate offline deaths"
            cd ../..
            return 1
        fi
    else
        echo "    ✗ Failed to generate trace"
        cd ../..
        return 1
    fi
}

# Function to compare traces
compare_traces() {
    local test_name=$1
    local online_trace="test_traces_online/$test_name/trace"
    local offline_trace="test_traces_offline/$test_name/trace_with_offline_deaths"
    local result_file="comparison_results/${test_name}_comparison.txt"
    
    echo "  Comparing death records..." > "$result_file"
    echo "" >> "$result_file"
    
    # Extract death records
    local online_deaths="comparison_results/${test_name}_online_deaths.txt"
    local offline_deaths="comparison_results/${test_name}_offline_deaths.txt"
    
    if [ -f "$online_trace" ]; then
        grep "^D " "$online_trace" | sort > "$online_deaths" || touch "$online_deaths"
    else
        touch "$online_deaths"
    fi
    
    if [ -f "$offline_trace" ]; then
        grep "^D " "$offline_trace" | sort > "$offline_deaths" || touch "$offline_deaths"
    else
        touch "$offline_deaths"
    fi
    
    # Count deaths
    local online_count=$(wc -l < "$online_deaths" | tr -d ' ')
    local offline_count=$(wc -l < "$offline_deaths" | tr -d ' ')
    
    echo "Death Record Counts:" >> "$result_file"
    echo "  Online:  $online_count deaths" >> "$result_file"
    echo "  Offline: $offline_count deaths" >> "$result_file"
    echo "" >> "$result_file"
    
    # Extract just object IDs (ignore timestamps which may differ slightly)
    if [ -f "$online_deaths" ]; then
        awk '{print $2}' "$online_deaths" | sort > "${online_deaths}.ids"
    else
        touch "${online_deaths}.ids"
    fi
    
    if [ -f "$offline_deaths" ]; then
        awk '{print $2}' "$offline_deaths" | sort > "${offline_deaths}.ids"
    else
        touch "${offline_deaths}.ids"
    fi
    
    # Compare object IDs that died
    local only_online=$(comm -23 "${online_deaths}.ids" "${offline_deaths}.ids" | wc -l | tr -d ' ')
    local only_offline=$(comm -13 "${online_deaths}.ids" "${offline_deaths}.ids" | wc -l | tr -d ' ')
    local common=$(comm -12 "${online_deaths}.ids" "${offline_deaths}.ids" | wc -l | tr -d ' ')
    
    echo "Object Death Comparison:" >> "$result_file"
    echo "  Both modes agree: $common objects" >> "$result_file"
    echo "  Only online:      $only_online objects" >> "$result_file"
    echo "  Only offline:     $only_offline objects" >> "$result_file"
    echo "" >> "$result_file"
    
    # Determine status
    if [ "$online_count" -eq "$offline_count" ] && [ "$only_online" -eq 0 ] && [ "$only_offline" -eq 0 ]; then
        echo "✓ IDENTICAL - Both implementations produce the same death records" >> "$result_file"
        echo "    ✓ IDENTICAL"
        return 0
    else
        echo "⚠ DIFFERENCES FOUND" >> "$result_file"
        echo "" >> "$result_file"
        
        if [ "$only_online" -gt 0 ]; then
            echo "Objects that died only in ONLINE mode:" >> "$result_file"
            comm -23 "${online_deaths}.ids" "${offline_deaths}.ids" | head -10 >> "$result_file"
            if [ "$only_online" -gt 10 ]; then
                echo "  ... and $((only_online - 10)) more" >> "$result_file"
            fi
            echo "" >> "$result_file"
        fi
        
        if [ "$only_offline" -gt 0 ]; then
            echo "Objects that died only in OFFLINE mode:" >> "$result_file"
            comm -13 "${online_deaths}.ids" "${offline_deaths}.ids" | head -10 >> "$result_file"
            if [ "$only_offline" -gt 10 ]; then
                echo "  ... and $((only_offline - 10)) more" >> "$result_file"
            fi
            echo "" >> "$result_file"
        fi
        
        # Check timestamp differences for common objects
        echo "Timestamp Comparison (first 5 common objects):" >> "$result_file"
        for obj_id in $(comm -12 "${online_deaths}.ids" "${offline_deaths}.ids" | head -5); do
            online_ts=$(grep "^D $obj_id " "$online_deaths" | awk '{print $4}')
            offline_ts=$(grep "^D $obj_id " "$offline_deaths" | awk '{print $4}')
            if [ "$online_ts" != "$offline_ts" ]; then
                echo "  Object $obj_id: online=$online_ts, offline=$offline_ts" >> "$result_file"
            fi
        done
        
        echo "    ⚠ DIFFERENCES (see comparison_results/${test_name}_comparison.txt)"
        return 1
    fi
}

# Run tests for each program
echo "Running tests..."
echo ""

summary_identical=0
summary_different=0

for test in "${TESTS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing: $test"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Run online
    if run_online "$test"; then
        # Run offline
        if run_offline "$test"; then
            # Compare
            if compare_traces "$test"; then
                ((summary_identical++))
            else
                ((summary_different++))
            fi
        else
            echo "  ✗ Offline test failed"
            ((summary_different++))
        fi
    else
        echo "  ✗ Online test failed"
        ((summary_different++))
    fi
    
    echo ""
done

# Summary
echo "========================================================================"
echo "SUMMARY"
echo "========================================================================"
echo ""
echo "Tests run: ${#TESTS[@]}"
echo "Identical: $summary_identical"
echo "Different: $summary_different"
echo ""

if [ "$summary_identical" -eq "${#TESTS[@]}" ]; then
    echo "✓ SUCCESS: All tests show online and offline produce identical results!"
    echo ""
    echo "Conclusion: Both MerlinTracker (online) and MerlinDeathTracker (offline)"
    echo "           are valid implementations that produce equivalent death records."
    echo ""
    echo "Recommendation: Use offline (MerlinDeathTracker) for ET3 compliance"
    echo "               and lower runtime overhead."
else
    echo "⚠ Some differences found between online and offline modes."
    echo ""
    echo "Check comparison_results/ for detailed analysis."
fi

echo ""
echo "Detailed results saved in: comparison_results/"
echo ""

# Create summary report
SUMMARY_FILE="comparison_results/SUMMARY.txt"
echo "=======================================================================" > "$SUMMARY_FILE"
echo "Online vs Offline Comparison Summary" >> "$SUMMARY_FILE"
echo "Generated: $(date)" >> "$SUMMARY_FILE"
echo "=======================================================================" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

for test in "${TESTS[@]}"; do
    if [ -f "comparison_results/${test}_comparison.txt" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$SUMMARY_FILE"
        echo "$test" >> "$SUMMARY_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$SUMMARY_FILE"
        cat "comparison_results/${test}_comparison.txt" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    fi
done

echo "Summary report: $SUMMARY_FILE"
