#!/bin/bash

echo "Rebuilding ET3 with fixed Merlin integration..."
cd /Users/luka/Desktop/Honors_Thesis/et2-java/javassist-inst/et2-instrumenter
mvn clean compile package -q

echo "Testing..."
cd /Users/luka/Desktop/Honors_Thesis/et2-java
rm -rf trace_output_integrated
mkdir -p trace_output_integrated
javac -d trace_output_integrated java/SimpleTrace.java
cd trace_output_integrated
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar SimpleTrace > /dev/null 2>&1
cd ..

echo ""
echo "Trace Analysis:"
echo "==============="
echo "Total lines: $(wc -l < trace_output_integrated/trace)"
echo ""
echo "First 30 lines of trace (should show allocations, methods, updates, deaths in order):"
head -30 trace_output_integrated/trace
echo ""
echo "Deaths found: $(grep -c "^D" trace_output_integrated/trace || echo 0)"
echo ""
echo "Check deaths are interspersed (not all at beginning):"
echo "  Line numbers of first 5 deaths:"
grep -n "^D" trace_output_integrated/trace | head -5 | cut -d: -f1
