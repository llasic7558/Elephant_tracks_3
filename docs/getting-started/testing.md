# ET3 Testing Guide

## Quick Test Scripts

### Integrated Merlin Test

Tests the real-time Merlin death tracking:

```bash
cd /path/to/et2-java
./test_integrated_merlin.sh
```

This will:
1. Build the ET3 agent
2. Run SimpleTrace program
3. Validate death records were generated
4. Show statistics

### Full Pipeline Test

Tests the complete offline pipeline with all test programs:

```bash
cd /path/to/et2-java
./run_all_tests_pipeline.sh
```

This tests 5 programs:
- **SimpleTrace**: Linked list operations (16 allocations, 16 deaths)
- **HelloWorld**: Minimal program (4 allocations, 4 deaths)
- **Methods**: Method calls (4 allocations, 4 deaths)
- **NewCall**: Object construction (7 allocations, 7 deaths)
- **LotsOfAllocs**: Stress test (1005 allocations, 1005 deaths)

### Offline Merlin Test

Tests the post-processing Merlin analyzer:

```bash
cd /path/to/et2-java
./run_merlin_analysis.sh SimpleTrace --verbose
```

## Test Programs

### SimpleTrace.java

Basic linked list operations:
```bash
# Compile and run
mkdir -p trace_output
javac -d trace_output java/SimpleTrace.java
cd trace_output
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar SimpleTrace

# View results
grep "^D" trace
```

Expected: 15-16 death records

### LotsOfAllocs.java

Stress test with many allocations:
```bash
mkdir -p trace_output
javac -d trace_output java/LotsOfAllocs.java
cd trace_output
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar LotsOfAllocs

# Count allocations and deaths
grep -c "^[NA]" trace  # Should be ~1005
grep -c "^D" trace     # Should be ~1005
```

## Validation

### Check Death Records

```bash
# Count allocations
ALLOCS=$(grep -c "^[NA]" trace)

# Count deaths
DEATHS=$(grep -c "^D" trace)

echo "Allocated: $ALLOCS objects"
echo "Died: $DEATHS objects"
echo "Still alive: $((ALLOCS - DEATHS)) objects"
```

### Verify No Use-After-Death

The pipeline includes validation to ensure objects aren't accessed after death:

```bash
./run_all_tests_pipeline.sh
# Look for: "No witness-after-death violations"
```

### Check Logical Time Ordering

```bash
# Extract death records with timestamps
grep "^D" trace

# Verify timestamps are monotonically increasing
# and are small integers (not nanoseconds)
```

Good timestamps: `D 1001 5001` (implicit logical time)
Bad timestamps: `D 1001 5001 174837450676400` (nanoseconds - old bug)

## DaCapo Benchmark Testing

### Single Benchmark

```bash
java -javaagent:./instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     -jar dacapo-9.12-bach.jar \
     --no-validation \
     -t 1 \
     avrora
```

### All Benchmarks (No-Hang Set)

Working benchmarks (see `DACAPO_NO_HANG.md` in development docs):
- avrora
- batik
- eclipse
- fop
- h2
- jython
- luindex
- lusearch
- pmd
- sunflow
- xalan

## Manual Testing Workflow

### 1. Build Agent

```bash
cd javassist-inst/et2-instrumenter
mvn clean compile package
```

### 2. Prepare Test Program

```bash
mkdir -p test_output
javac -d test_output YourProgram.java
```

### 3. Run with ET3

```bash
cd test_output
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar YourProgram
```

### 4. Analyze Results

```bash
# View trace
less trace

# Count records
grep -c "^N" trace   # Object allocations
grep -c "^A" trace   # Array allocations
grep -c "^M" trace   # Method entries
grep -c "^E" trace   # Method exits
grep -c "^U" trace   # Field updates
grep -c "^D" trace   # Object deaths
```

## Oracle Generation

For gem5 simulation, generate oracle files:

```bash
# Using the pipeline
./run_all_tests_pipeline.sh

# Results in pipeline_results/<test>/
# - trace: Original runtime trace
# - trace_with_deaths: With death records appended
# - trace_reordered: Deaths in temporal order
# - oracle.txt: Human-readable oracle
# - oracle.csv: Machine-readable for gem5
```

## Debugging

### Enable Verbose Output

For offline Merlin:
```bash
./run_merlin_analysis.sh SimpleTrace --verbose
```

### Check for Common Issues

**Missing deaths**:
```bash
# Should see periodic analysis messages
grep "Reachability analysis" trace 2>&1
```

**Premature deaths**:
```bash
# Look for witness-after-death violations
python3 verify_no_witness_after_death.py trace_reordered
```

**Build failures**:
```bash
# Clean rebuild
cd javassist-inst/et2-instrumenter
mvn clean
mvn compile package
```

## Expected Test Results

### SimpleTrace
- Allocations: 15-16
- Deaths: 15-16
- Method entries: ~23
- Field updates: ~9

### HelloWorld
- Allocations: 4
- Deaths: 4
- Minimal trace

### LotsOfAllocs
- Allocations: 1005
- Deaths: 1005
- Large trace file

## Continuous Integration

For automated testing:

```bash
#!/bin/bash
# test_et3.sh

set -e

echo "Building ET3..."
cd javassist-inst/et2-instrumenter
mvn clean compile package
cd ../..

echo "Running tests..."
./test_integrated_merlin.sh

echo "Running full pipeline..."
./run_all_tests_pipeline.sh

echo "All tests passed!"
```

## Performance Testing

### Measure Overhead

```bash
# Without instrumentation
time java YourProgram

# With ET3 instrumentation
time java -javaagent:instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar YourProgram

# Calculate overhead percentage
```

Expected overhead: 5-15% depending on allocation rate

### Trace Size

```bash
# Check trace file size
ls -lh trace

# Count records
wc -l trace
```

For large programs, traces can be several GB.

## Next Steps

- Review [Implementation Guide](../implementation/merlin.md) for algorithm details
- See [Development Notes](../development/witness-fix.md) for bug fixes
- Read [DaCapo Usage](../reference/dacapo.md) for benchmark testing
