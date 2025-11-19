# DaCapo Benchmark Usage with ET3

## Overview

DaCapo is a benchmark suite for Java programs. ET3 can trace DaCapo benchmarks to analyze real-world application behavior.

## Basic Usage

```bash
java -javaagent:instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     -jar dacapo-9.12-bach.jar \
     --no-validation \
     -t <threads> \
     <benchmark>
```

### Required Flags

- `--no-validation`: **REQUIRED** - DaCapo flags runs as invalid due to bytecode rewriting
- `-t <threads>`: Number of threads (start with 1, increase carefully)

## Working Benchmarks (No-Hang Set)

These benchmarks run successfully with ET3:

- **avrora** - Real-time embedded system simulator
- **batik** - SVG graphics toolkit
- **eclipse** - Eclipse IDE workbench
- **fop** - XSL-FO print formatter
- **h2** - H2 database
- **jython** - Python interpreter
- **luindex** - Lucene indexing
- **lusearch** - Lucene search
- **pmd** - Source code analyzer
- **sunflow** - Ray tracer
- **xalan** - XSLT processor

## Example Commands

### Single-Threaded Run

```bash
java -javaagent:./instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     -jar dacapo-9.12-bach.jar \
     --no-validation \
     -t 1 \
     avrora
```

### Multi-Threaded Run

```bash
java -javaagent:./instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     -jar dacapo-9.12-bach.jar \
     --no-validation \
     -t 4 \
     h2
```

### Batch Testing

```bash
#!/bin/bash
# test_dacapo.sh

BENCHMARKS="avrora batik fop h2 luindex lusearch pmd sunflow xalan"
AGENT="./instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar"
DACAPO="dacapo-9.12-bach.jar"

for bench in $BENCHMARKS; do
    echo "Running $bench..."
    java -javaagent:$AGENT \
         -jar $DACAPO \
         --no-validation \
         -t 1 \
         $bench
    
    # Move trace
    mv trace "trace_${bench}"
    
    # Generate statistics
    echo "$bench:"
    grep -c "^N" "trace_${bench}"  # Allocations
    grep -c "^D" "trace_${bench}"  # Deaths
done
```

## Known Issues

### Multi-Threading

Earlier ET3 versions had issues with high thread counts. Current version is more stable but:

- **Recommended**: Start with `-t 1`
- **Testing**: Gradually increase to `-t 4`, `-t 8`
- **Production**: Monitor for race conditions

### Validation Flag

DaCapo validation **will fail** with ET3 because:
- ET3 rewrites bytecode
- DaCapo detects modified classes
- Always use `--no-validation`

### Memory Requirements

Large benchmarks generate large traces:

```bash
# Set heap size for heavy benchmarks
java -Xmx4g \
     -javaagent:./instrumenter.jar \
     -jar dacapo.jar \
     --no-validation \
     -t 1 \
     eclipse
```

## Trace Analysis

### Basic Statistics

```bash
BENCH="avrora"

echo "=== $BENCH Statistics ==="
echo "Allocations:    $(grep -c '^N' trace_$BENCH)"
echo "Arrays:         $(grep -c '^A' trace_$BENCH)"
echo "Deaths:         $(grep -c '^D' trace_$BENCH)"
echo "Method entries: $(grep -c '^M' trace_$BENCH)"
echo "Method exits:   $(grep -c '^E' trace_$BENCH)"
echo "Field updates:  $(grep -c '^U' trace_$BENCH)"
echo "Total records:  $(wc -l < trace_$BENCH)"
echo "File size:      $(du -h trace_$BENCH | cut -f1)"
```

### Object Lifetime Analysis

```python
#!/usr/bin/env python3
"""Analyze object lifetimes from DaCapo traces."""

import sys

def analyze_lifetimes(trace_file):
    allocations = {}  # obj_id → (time, size)
    lifetimes = []
    
    with open(trace_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            
            if parts[0] == 'N' or parts[0] == 'A':
                obj_id = int(parts[1])
                size = int(parts[2])
                time = int(parts[-1])
                allocations[obj_id] = (time, size)
            
            elif parts[0] == 'D':
                obj_id = int(parts[1])
                death_time = int(parts[-1])
                
                if obj_id in allocations:
                    alloc_time, size = allocations[obj_id]
                    lifetime = death_time - alloc_time
                    lifetimes.append((obj_id, lifetime, size))
    
    # Statistics
    lifetimes.sort(key=lambda x: x[1])  # Sort by lifetime
    
    print(f"Total objects: {len(lifetimes)}")
    print(f"Shortest lifetime: {lifetimes[0][1]}")
    print(f"Longest lifetime: {lifetimes[-1][1]}")
    print(f"Average lifetime: {sum(l[1] for l in lifetimes) / len(lifetimes):.2f}")
    
    # Lifetime distribution
    buckets = [0, 10, 100, 1000, 10000, float('inf')]
    counts = [0] * (len(buckets) - 1)
    
    for _, lifetime, _ in lifetimes:
        for i in range(len(buckets) - 1):
            if buckets[i] <= lifetime < buckets[i+1]:
                counts[i] += 1
                break
    
    print("\nLifetime distribution:")
    for i in range(len(counts)):
        if buckets[i+1] == float('inf'):
            print(f"  {buckets[i]}+: {counts[i]}")
        else:
            print(f"  {buckets[i]}-{buckets[i+1]}: {counts[i]}")

if __name__ == '__main__':
    analyze_lifetimes(sys.argv[1])
```

## Performance Considerations

### Overhead

ET3 adds ~10-30% overhead depending on:
- Allocation rate
- Method call frequency
- Field update frequency

DaCapo benchmarks vary:

| Benchmark | Allocation Rate | ET3 Overhead |
|-----------|----------------|--------------|
| avrora | Low | ~10% |
| h2 | Medium | ~20% |
| sunflow | High | ~30% |

### Disk Space

Trace files can be very large:

| Benchmark | Runtime | Trace Size |
|-----------|---------|------------|
| avrora (small) | 30s | ~500 MB |
| h2 (medium) | 60s | ~2 GB |
| eclipse (large) | 120s | ~10 GB |

**Recommendation**: Use compression or streaming analysis for large benchmarks.

## Troubleshooting

### Benchmark Hangs

If a benchmark hangs:

1. Try with fewer threads: `-t 1`
2. Increase heap: `-Xmx4g`
3. Check for deadlock in instrumented code
4. Use timeout: `timeout 300 java ...`

### Out of Memory

```bash
# Increase heap size
java -Xmx8g -javaagent:instrumenter.jar ...

# Or reduce trace size by disabling features
# (requires rebuilding with modified InstrumentFlag.java)
```

### Trace Corruption

If trace appears corrupted:

```bash
# Check for incomplete records
grep -v "^[NAUMEXD]" trace | head

# Verify buffer was flushed
tail -100 trace  # Should see final events
```

## Research Use Cases

### Memory Allocator Studies

1. Run DaCapo benchmark with ET3
2. Generate oracle from trace
3. Replay in gem5 with different allocators
4. Compare fragmentation, performance

### GC Algorithm Analysis

1. Collect traces from multiple benchmarks
2. Analyze object lifetimes
3. Identify GC pressure points
4. Optimize GC parameters

### Program Behavior Study

1. Compare allocation patterns across benchmarks
2. Identify common idioms
3. Optimize instrumentation strategies

## Validation

After running DaCapo:

```bash
TRACE="trace_avrora"

# Verify trace integrity
echo "Checking $TRACE..."

# Count allocations
ALLOCS=$(grep -c "^[NA]" $TRACE)

# Count deaths  
DEATHS=$(grep -c "^D" $TRACE)

echo "Allocations: $ALLOCS"
echo "Deaths: $DEATHS"
echo "Still alive: $((ALLOCS - DEATHS))"

# Check for corruption
TOTAL=$(wc -l < $TRACE)
VALID=$(grep -c "^[NAUMEXD]" $TRACE)

if [ $TOTAL -eq $VALID ]; then
    echo "✅ Trace valid"
else
    echo "❌ Found $((TOTAL - VALID)) invalid records"
fi
```

## Next Steps

- See [Getting Started](../getting-started/) for basic ET3 usage
- See [Implementation](../implementation/merlin.md) for technical details
- See [Oracle Construction](../development/oracle.md) for gem5 integration

## References

- DaCapo: http://dacapobench.sourceforge.net/
- ET3 compatibility notes: `DACAPO_NO_HANG.md` (archived)
