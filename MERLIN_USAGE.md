# Merlin Death Tracker Usage Guide

## Overview

The `MerlinDeathTracker` implements the Merlin Algorithm to reconstruct object death records from Elephant Tracks 3 (ET3) traces. ET3 produces traces with allocation, method entry/exit, and field update records, but not death records. The Merlin algorithm analyzes these traces to determine when objects become unreachable and thus "dead."

## How the Merlin Algorithm Works

The Merlin algorithm tracks object reachability by:

1. **Maintaining Root Sets**: Tracks objects on thread stacks and in static fields
2. **Building Object Graphs**: Tracks pointer relationships between objects via field updates
3. **Reachability Analysis**: Periodically performs breadth-first search from roots to determine reachable objects
4. **Death Detection**: Any object that is no longer reachable is considered dead

## Trace File Format

### Input Records (ET3 Format)

- **N** - Object allocation: `N <object-id> <size> <type-id> <site-id> <length> <thread-id>`
- **A** - Array allocation: `A <object-id> <size> <type-id> <site-id> <length> <thread-id>`
- **U** - Field update: `U <obj-id> <new-tgt-obj-id> <field-id> <thread-id>`
- **M** - Method entry: `M <method-id> <receiver-object-id> <thread-id>`
- **E** - Method exit: `E <method-id> <thread-id>`
- **X** - Exception exit: `X <method-id> <receiver-object-id> <exception-id> <thread-id>`
- **T** - Exception throw: `T <method-id> <receiver-id> <exception-object-id> <thread-id>`
- **H** - Exception handled: `H <method-id> <receiver-id> <exception-object-id> <thread-id>`

### Output Records (Added by Merlin)

- **D** - Object death: `D <object-id> <thread-id>`

The output file contains all original trace records plus death records inserted at appropriate points.

## Usage

### Standalone Command Line

Compile and run the MerlinDeathTracker as a standalone program:

```bash
# Navigate to the project directory
cd /Users/luka/Desktop/Honors_Thesis/et2-java/javassist-inst/et2-instrumenter

# Compile
javac -d target/classes src/main/java/veroy/research/et2/javassist/MerlinDeathTracker.java

# Run
java -cp target/classes veroy.research.et2.javassist.MerlinDeathTracker \
    input_trace.txt \
    output_trace_with_deaths.txt \
    --verbose
```

### Integration with ET3

To automatically apply Merlin analysis to ET3 traces, you can modify the `ETProxy` to call the tracker at shutdown.

### Example Workflow

1. **Generate ET3 trace**:
```bash
cd /Users/luka/Desktop/Honors_Thesis/et2-java
mkdir -p trace_output
javac -d trace_output java/SimpleTrace.java
cd trace_output
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar SimpleTrace > /dev/null
```

2. **Apply Merlin analysis**:
```bash
java -cp ../javassist-inst/et2-instrumenter/target/classes \
    veroy.research.et2.javassist.MerlinDeathTracker \
    trace \
    trace_with_deaths \
    --verbose
```

3. **Analyze the enhanced trace**:
```bash
# The trace_with_deaths file now contains both original records and death records
head -100 trace_with_deaths
```

## Implementation Details

### Key Components

1. **Object Tracking**: Maintains a `liveObjects` map with all currently live objects
2. **Object Graph**: Tracks pointer relationships via `objectGraph` (forward) and `reverseGraph` (backward)
3. **Stack Tracking**: Maintains per-thread call stacks with local object references
4. **Static Roots**: Tracks objects stored in static fields (field updates with object-id 0)
5. **Reachability Analysis**: BFS from roots to identify all reachable objects

### Algorithm Characteristics

- **Incremental Analysis**: Performs reachability checks every 1000 trace records
- **Precision**: Conservative - an object is only dead when proven unreachable
- **Thread-Aware**: Tracks per-thread stacks and associates deaths with threads

### Performance Considerations

- For large traces (millions of records), consider increasing the analysis interval
- Memory usage grows with the number of live objects
- Processing time is O(n * m) where n = trace records, m = live objects

## References

1. **Original Merlin Paper**: "Merlin: Efficient and Enhanced Memory Leak Detection" by Hertz et al.
   - https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf

2. **Elephant Tracks Paper**: "Elephant Tracks: Portable Production of Complete and Precise GC Traces"
   - http://www.cs.tufts.edu/research/redline/elephantTracks/

## Limitations and Future Work

### Current Limitations

1. **Weak References**: Does not handle weak/soft/phantom references
2. **Native Objects**: Cannot track objects created by JNI
3. **Finalizers**: Does not account for finalization delays
4. **Approximation**: May over-approximate object lifetimes in complex scenarios

### Potential Enhancements

1. Add support for weak reference semantics
2. Implement more sophisticated escape analysis
3. Add visualization of object lifetime histograms
4. Optimize for large-scale trace analysis

## Troubleshooting

### Issue: Too many false deaths

**Solution**: The analysis interval might be too frequent. Objects may still be used but temporarily not in active frames. Consider increasing the reachability check interval or implementing a grace period.

### Issue: Missing death records

**Solution**: Check that all field updates are captured in the trace. Incomplete traces will result in incomplete death information.

### Issue: Memory exhaustion

**Solution**: For very large traces, consider processing in chunks or implementing a sliding window approach.

## Example Output

```
# Original trace
N 12345 32 100 200 0 1001
M 200 12345 1001
U 12345 67890 5 1001
E 200 1001
# After Merlin analysis
D 12345 1001
```

In this example, object 12345 is allocated, used as a method receiver, has a field update, and then becomes dead after the method exits (if no other references exist).
