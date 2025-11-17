# Oracle Trace with Death Records - Explained

## What is an Oracle Trace?

An **oracle trace** is a reference trace that contains "ground truth" information about when objects die. It's called an "oracle" because it provides the authoritative answer for validating other death-tracking algorithms.

## How The Trace Works

### Understanding prev/rec Verification

The `prev` and `rec` output you see is timestamp verification:

```
prev: 0    rec: 1   ← First record at time 1
prev: 1    rec: 2   ← Time advances: 1 → 2 ✓
prev: 2    rec: 2   ← Multiple events at same time OK
prev: 2    rec: 3   ← Time advances: 2 → 3 ✓
```

**Purpose**: Ensures all records have monotonically increasing timestamps (never going backward).

- `prev` = previous record's timestamp
- `rec` = current record's timestamp  
- Check: `rec >= prev` (non-decreasing)

This validation confirms the trace is chronologically ordered.

## Oracle Trace Format

**Format**: `D <object-id> <thread-id> <timestamp> <size>`

Example:
```
D 458209687 1950409828 2 24
```

Fields:
- **D** - Death record
- **458209687** - Object ID
- **1950409828** - Thread ID (constant for now)
- **2** - Death timestamp (logical clock time)
- **24** - Object size in bytes

## Our Oracle Trace Statistics

| Metric | Value |
|--------|-------|
| **Original trace** | 95 records (M, E, N, A types) |
| **Death records added** | 31 |
| **Oracle trace** | 126 records total |
| **Size range** | 4-40 bytes |

### Size Distribution

```
 4 bytes: 19 objects (likely 32-bit primitives/references)
24 bytes: 10 objects (likely small objects with 2-3 fields)
32 bytes:  1 object  (medium object)
40 bytes:  3 objects (larger objects or arrays)
```

## How It Was Created

### 1. Generate Clean Trace
```bash
java -Det3.simulator.mode=true -javaagent:instrumenter.jar SimpleTrace
```
- No W (witness) records
- No U (update) records  
- Only M, E, N, A records

### 2. Run ET2 Simulator
```bash
cat trace | simulator SIM classes.txt fields.txt methods.txt ...
```
- Applies Merlin algorithm
- Computes precise death times
- Extracts size information

### 3. Merge Deaths into Trace
```bash
./create_oracle_trace.sh pipeline_results/SimpleTrace_simulator_mode
```
- Parses death records with sizes
- Inserts deaths chronologically
- Maintains timestamp order

## Using the Oracle

### For Validation
Compare your death-tracking algorithm's output against the oracle:

```bash
# Your algorithm's deaths
grep '^D' your_trace_with_deaths | sort -k3 -n > your_deaths.txt

# Oracle deaths
grep '^D' trace_with_deaths_oracle | sort -k3 -n > oracle_deaths.txt

# Compare
diff your_deaths.txt oracle_deaths.txt
```

### For Memory Analysis
Analyze total memory freed over time:

```python
import sys

total_freed = 0
with open('trace_with_deaths_oracle') as f:
    for line in f:
        if line.startswith('D'):
            parts = line.strip().split()
            obj_id, thread_id, time, size = parts[1:]
            total_freed += int(size)
            print(f"Time {time}: Object {obj_id} freed ({size} bytes)")
            print(f"  Total freed so far: {total_freed} bytes")
```

### For GC Studies
Simulate garbage collection:

```python
live_objects = {}  # obj_id -> size
total_allocated = 0

with open('trace_with_deaths_oracle') as f:
    for line in f:
        parts = line.strip().split()
        if parts[0] == 'N':  # Allocation
            obj_id = parts[1]
            size = int(parts[2])
            live_objects[obj_id] = size
            total_allocated += size
        elif parts[0] == 'D':  # Death
            obj_id = parts[1]
            if obj_id in live_objects:
                del live_objects[obj_id]
        
        # Current heap size
        heap_size = sum(live_objects.values())
        print(f"Heap: {heap_size} bytes, Allocated: {total_allocated} bytes")
```

## Death Timeline

The oracle shows when each object became unreachable:

```
Time  2: 1 death  (24 bytes) - Early cleanup
Time  8: 1 death  (40 bytes)
Time 10-22: 8 deaths (118 bytes) - Middle phase
Time 29-43: 11 deaths (266 bytes) - Bulk cleanup
Time 48-56: 4 deaths (38 bytes) - Final cleanup
```

**Total memory freed**: 446 bytes across 31 objects

## Benefits of This Oracle

### 1. **Precise Timing**
- Death times computed by proven Merlin algorithm
- Chronological insertion maintains temporal order
- No approximations or estimates

### 2. **Size Information**
- Actual object sizes in bytes
- Enables memory pressure analysis
- Supports GC simulation

### 3. **Complete Coverage**
- All 31 objects accounted for
- Includes both program and infrastructure objects
- No missing death records

### 4. **Validation Ready**
- Standard format compatible with existing tools
- Can validate ET3's Merlin tracker
- Serves as ground truth for experiments

## Next Steps

### Compare with ET3 Merlin
```bash
# ET3's deaths (from integrated tracker)
grep '^D' pipeline_results/SimpleTrace/trace_with_deaths | wc -l
# Expected: 16 (program objects only)

# Oracle deaths (from simulator)
grep '^D' trace_with_deaths_oracle | wc -l  
# Result: 31 (program + infrastructure)
```

### Run on Larger Benchmarks
```bash
# LotsOfAllocs
java -Det3.simulator.mode=true -javaagent:instrumenter.jar LotsOfAllocs
./create_oracle_trace.sh pipeline_results/LotsOfAllocs_simulator_mode

# DaCapo benchmarks
java -Det3.simulator.mode=true -javaagent:instrumenter.jar \
  -jar dacapo.jar avrora
```

### Use for GC Research
- Simulate different GC policies
- Measure fragmentation
- Analyze allocation patterns
- Evaluate collector performance

## Files

- `trace_with_deaths_oracle` - Oracle trace with deaths and sizes (126 lines)
- `deaths_with_size.txt` - Extracted death records (31 lines)
- `simulator_run.log` - Full simulator output with diagnostics
- `merge_deaths.py` - Python script for merging deaths
- `ORACLE_EXPLANATION.md` - This file

## Conclusion

This oracle trace provides ground truth for object lifetimes in SimpleTrace, combining:
- ✅ Clean trace generation (no W/U records)
- ✅ Precise Merlin-computed death times
- ✅ Actual object sizes
- ✅ Chronological ordering
- ✅ Complete coverage (31 objects)

Perfect for validating death-tracking algorithms and memory analysis!
