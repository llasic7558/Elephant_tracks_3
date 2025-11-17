# Oracle Construction from ET Traces - Complete Guide

## Overview

This document describes the complete workflow for constructing an "oracle" from Elephant Tracks traces with Merlin death records. The oracle provides ground-truth allocation and deallocation events for memory allocator simulation in gem5.

## What is an Oracle?

An oracle is a chronologically-ordered sequence of memory events:

```
t5:  alloc(id=212628335, size=24, site=62, thread=1950409828)
t7:  free(id=212628335, size=24, site=62, thread=1950409828)
t16: alloc(id=1101288798, size=40, site=135, thread=1950409828)
t18: free(id=1101288798, size=40, site=135, thread=1950409828)
...
```

For each object, the oracle captures:
- **Allocation time** - Event index (logical time)
- **Death time** - When Merlin detected unreachability
- **Size** - Object size in bytes
- **Site** - Allocation site identifier
- **Thread** - Thread ID

## Three-Step Process

### Step 1: Generate ET Trace with Merlin Deaths

Run your Java program with the ET3 agent and Merlin offline analysis:

```bash
cd /Users/luka/Desktop/Honors_Thesis/et2-java

# Build the instrumenter
cd javassist-inst/et2-instrumenter
mvn clean package
cd ../..

# Run Java program with ET3
mkdir -p trace_output
javac -d trace_output java/YourProgram.java
cd trace_output
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar YourProgram
cd ..

# Run offline Merlin analysis
java -cp javassist-inst/et2-instrumenter/target/classes \
     veroy.research.et2.javassist.MerlinDeathTracker \
     trace_output/trace \
     trace_output/trace_offline \
     --verbose
```

**Output**: `trace_offline` - ET trace with death records appended at end

**Problem**: Death records are at the bottom but contain timestamps indicating when they should have occurred.

### Step 2: Reorder Death Records

Death records must be inserted at their correct temporal positions based on logical clock timestamps:

```bash
cd gem5-simulation/scripts

python3 reorder_deaths.py \
    ../../trace_output/trace_offline \
    ../../trace_output/trace_reordered \
    --verbose --validate
```

**Output**: `trace_reordered` - Trace with deaths in correct chronological order

**What it does**:
- Tracks logical clock (increments at M/E/X records)
- Extracts death timestamps from D records
- Inserts deaths at correct temporal positions
- Validates deaths occur after allocations

### Step 3: Build Oracle Event Stream

Convert the reordered trace into an oracle format suitable for gem5 simulation:

```bash
python3 build_oracle.py \
    ../../trace_output/trace_reordered \
    --output ../../trace_output/oracle.txt \
    --csv ../../trace_output/oracle.csv \
    --stats
```

**Output**: 
- `oracle.txt` - Human-readable oracle
- `oracle.csv` - Machine-readable CSV format
- Statistics printed to stderr

## Complete Example: SimpleTrace

```bash
# Already have traces in test_offline_fixed/SimpleTrace/
cd gem5-simulation/scripts

# Step 2: Reorder deaths
python3 reorder_deaths.py \
    ../../test_offline_fixed/SimpleTrace/trace_offline \
    ../../test_offline_fixed/SimpleTrace/trace_reordered \
    --validate

# Step 3: Build oracle
python3 build_oracle.py \
    ../../test_offline_fixed/SimpleTrace/trace_reordered \
    --output ../../test_offline_fixed/SimpleTrace/oracle.txt \
    --csv ../../test_offline_fixed/SimpleTrace/oracle.csv \
    --stats
```

**Results**:
```
=== Oracle Statistics ===
Total events: 32
Allocations: 16
Frees: 16
Live objects (not freed): 0
Total bytes allocated: 440
Total bytes freed: 440
Live bytes: 0

Allocation sites: 7
Most active sites:
  Site 151: 9 allocations
  Site 135: 2 allocations
```

## Oracle Output Formats

### Text Format (oracle.txt)

```
# Oracle Event Stream
# Format: t<event_index>: <event_type>(id=<obj_id>, size=<bytes>, site=<site_id>, thread=<thread_id>)
# Total events: 32
# Allocations: 16
# Frees: 16

t5: alloc(id=212628335, size=24, site=62, thread=1950409828)
t7: free(id=212628335, size=24, site=62, thread=1950409828)
t16: alloc(id=1101288798, size=40, site=135, thread=1950409828)
```

### CSV Format (oracle.csv)

```csv
timestamp,event_type,object_id,size,site_id,thread_id,type_id
5,alloc,212628335,24,62,1950409828,3
7,free,212628335,24,62,1950409828,3
16,alloc,1101288798,40,135,1950409828,23
```

## Using the Oracle

### gem5 Memory Allocator Simulation

```python
# In gem5 configuration
oracle_file = "trace_output/oracle.csv"
replayer = TraceReplayer(oracle_file)
replayer.set_allocator(FirstFitAllocator())
replayer.run()
```

### Python Analysis

```python
import pandas as pd

df = pd.read_csv('oracle.csv')

# Calculate object lifetimes
allocs = df[df['event_type'] == 'alloc'].set_index('object_id')
frees = df[df['event_type'] == 'free'].set_index('object_id')
lifetimes = frees['timestamp'] - allocs['timestamp']

print(f"Average lifetime: {lifetimes.mean():.2f} events")
print(f"Max lifetime: {lifetimes.max()} events")

# Track heap size over time
df_sorted = df.sort_values('timestamp')
heap_size = 0
max_heap = 0

for _, row in df_sorted.iterrows():
    if row['event_type'] == 'alloc':
        heap_size += row['size']
    else:
        heap_size -= row['size']
    max_heap = max(max_heap, heap_size)

print(f"Maximum heap size: {max_heap} bytes")
```

## Validation

### Verify Complete Workflow

```bash
# Check death records are properly ordered
grep -n "^D" trace_reordered | head -10

# Compare original vs reordered
diff trace_offline trace_reordered | grep "^>" | head -5

# Verify oracle event counts
wc -l oracle.txt
grep -c "alloc" oracle.txt
grep -c "free" oracle.txt
```

### Example Validation Output

```
# Deaths properly interspersed (not all at end)
8:D 212628335 1950409828 4
19:D 1101288798 1950409828 12
32:D 1068824137 1950409828 23

# Oracle matches allocations/deaths
39 oracle.txt            (header + 32 events + blank)
16 allocations
16 frees
```

## Directory Structure

```
et2-java/
├── gem5-simulation/
│   ├── scripts/
│   │   ├── reorder_deaths.py      # Step 2: Reorder death records
│   │   ├── build_oracle.py        # Step 3: Build oracle
│   │   └── oracle_events.csv      # Example oracle output
│   └── docs/
│       ├── REORDERING_DEATHS.md   # Death reordering details
│       ├── ORACLE_BUILDER.md      # Oracle builder details
│       └── TRACE_FORMAT.md        # ET trace format spec
├── test_offline_fixed/
│   ├── SimpleTrace/
│   │   ├── trace_offline          # Step 1 output (deaths at end)
│   │   ├── trace_reordered        # Step 2 output (deaths ordered)
│   │   ├── oracle.txt             # Step 3 output (text)
│   │   └── oracle.csv             # Step 3 output (CSV)
│   └── LotsOfAllocs/
│       ├── trace_offline
│       ├── trace_reordered
│       ├── oracle.txt
│       └── oracle.csv
└── ORACLE_CONSTRUCTION.md         # This file
```

## Key Concepts

### Logical Time

The Elephant Tracks logical clock increments at:
- **M records** (method entry)
- **E records** (method exit)
- **X records** (exception exit)

Death timestamps use this logical clock value, not wall-clock time.

### Merlin Algorithm

Merlin tracks object reachability:
1. Maintains object graph from field updates (U records)
2. Tracks stack roots (method frames with receivers/locals)
3. Tracks static roots (field updates with source=0)
4. Performs BFS from roots at method exits
5. Objects not reachable = dead

### Death Detection Timing

Deaths are detected at **method exit boundaries** when Merlin performs reachability analysis. This means:
- Death timestamp = logical time when unreachability was detected
- Not necessarily the exact moment object became unreachable
- Conservative but correct approximation

## Tools Reference

### reorder_deaths.py

```bash
python3 reorder_deaths.py <input_trace> <output_trace> [OPTIONS]

Options:
  --verbose, -v     Print detailed progress
  --validate        Validate output trace ordering
```

Reorders death records from end of trace into correct temporal positions.

### build_oracle.py

```bash
python3 build_oracle.py <input_trace> [OPTIONS]

Options:
  --output, -o FILE   Output file (default: stdout)
  --csv FILE          Export CSV format
  --stats, -s         Print statistics
  --verbose, -v       Print detailed progress
```

Constructs oracle event stream from reordered trace.

## Performance

### SimpleTrace (16 objects, 125 lines)
- Reordering: < 0.1s
- Oracle building: < 0.1s
- Total: < 0.2s

### LotsOfAllocs (1005 objects, 5093 lines)
- Reordering: < 0.5s
- Oracle building: < 0.5s
- Total: < 1s

### Scaling
- **10K lines**: ~1 second
- **100K lines**: ~10 seconds  
- **1M lines**: ~1-2 minutes

## Troubleshooting

### Issue: No death records in trace_offline

**Cause**: Merlin analysis not run or failed
**Fix**: Re-run `MerlinDeathTracker.java` with `--verbose`

### Issue: Deaths appear at wrong positions after reordering

**Cause**: Logical clock calculation mismatch
**Fix**: Verify M/E/X records increment clock; check trace format

### Issue: More deaths than allocations in oracle

**Cause**: Invalid trace or parsing error
**Fix**: Run with `--validate` flag; check for malformed records

### Issue: Oracle shows negative heap sizes

**Cause**: Deaths before allocations (ordering error)
**Fix**: Re-run reordering step; validate trace integrity

## Next Steps

1. **Integrate with gem5**: Feed oracle CSV to TraceReplayer
2. **Compare allocators**: Run same oracle with different allocation policies
3. **Analyze results**: Compare fragmentation, cache behavior, performance
4. **Scale up**: Process larger benchmarks (DaCapo suite)

## References

- **Merlin Paper**: Hertz et al., "Generating object lifetime traces with Merlin"
  - https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf
- **Elephant Tracks**: Ricci et al., "Portable Production of Complete GC Traces"
  - http://www.cs.tufts.edu/research/redline/elephantTracks/
- **gem5**: http://www.gem5.org/

## Documentation Index

- [REORDERING_DEATHS.md](gem5-simulation/docs/REORDERING_DEATHS.md) - Detailed death reordering algorithm
- [ORACLE_BUILDER.md](gem5-simulation/docs/ORACLE_BUILDER.md) - Oracle construction details and use cases
- [TRACE_FORMAT.md](gem5-simulation/docs/TRACE_FORMAT.md) - ET trace format specification
- [MERLIN_README.md](MERLIN_README.md) - Merlin implementation overview
- [MERLIN_USAGE.md](MERLIN_USAGE.md) - Merlin usage guide

## Summary

You now have a complete pipeline:

1. ✅ **ET3 + Merlin** generates traces with death records
2. ✅ **reorder_deaths.py** sorts deaths into correct temporal positions
3. ✅ **build_oracle.py** constructs alloc/free event stream
4. ✅ **Oracle formats** ready for gem5 simulation and analysis

All necessary information is captured: allocation time, death time, size, site, and thread for every object.
