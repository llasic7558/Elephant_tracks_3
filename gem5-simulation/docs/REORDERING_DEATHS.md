# Reordering Death Records in Offline Merlin Traces

## Problem

The offline Merlin algorithm (`MerlinDeathTracker.java`) appends all death records to the end of the trace file after processing is complete. However, each death record contains a **timestamp** (3rd field) indicating the **logical clock value** when the object became unreachable.

For accurate temporal analysis and oracle construction, death records must be reordered into their correct chronological positions within the trace.

## Understanding Logical Time in ET Traces

### Logical Clock Definition

The Elephant Tracks logical clock increments at:
- **Method Entry (M records)**: Clock increments by 1
- **Method Exit (E records)**: Clock increments by 1  
- **Exception Exit (X records)**: Clock increments by 1

All other record types (N, A, U, etc.) do NOT increment the logical clock.

### Example Trace with Logical Times

```
Line  Record                          Logical Time
----  -----------------------------   ------------
1     M 35 0 1950409828               1
2     M 25 0 1950409828               2
3     U 0 897697267 2 1950409828      2 (no change)
4     E 25 1950409828                 3
5     U 0 932583850 4 1950409828      3 (no change)
6     N 212628335 24 3 62 0 1950...   3 (no change)
7     E 35 1950409828                 4
...
109   D 212628335 1950409828 4       (should be at time 4)
```

The death record at line 109 has timestamp=4, meaning object 212628335 became unreachable at logical time 4 (after line 7).

## Merlin Death Timestamp Semantics

From `MerlinDeathTracker.java`:

```java
// Line 289-290: Method entry increments logical clock
logicalClock++;

// Line 316-317: Method exit increments logical clock  
logicalClock++;

// Line 411: Death timestamp = current logical clock when unreachable
deathRecords.add(new DeathRecord(objectId, obj.threadId, logicalClock));
```

**Key Insight**: Death timestamp represents the logical clock value AT THE TIME the object was detected as unreachable (typically at a method exit boundary).

## The Reordering Script

### Usage

```bash
cd gem5-simulation/scripts

# Reorder a single trace
python3 reorder_deaths.py <input_trace> <output_trace> [--verbose] [--validate]

# Example
python3 reorder_deaths.py \
    ../../test_offline_fixed/SimpleTrace/trace_offline \
    ../../test_offline_fixed/SimpleTrace/trace_reordered \
    --verbose --validate
```

### Algorithm

1. **Parse the trace** line by line
2. **Track logical clock** by counting M, E, X records
3. **Separate death records** from other records, extracting their timestamps
4. **Merge death records** back into trace at correct temporal positions
5. **Validate** that deaths occur after allocations and at correct times

### Validation

The script validates:
- ✓ All deaths occur at or before current logical time
- ✓ All deaths occur after their object's allocation
- ✓ Total death count matches

### Example Output

```
Read 124 lines from trace_offline
Found 108 trace records
Found 16 death records to reorder
Max logical time: 79
Wrote 124 lines to trace_reordered

=== Validation Results ===
Deaths correctly ordered: 16
Deaths after allocation: 16
Total objects allocated: 16
```

## Complete Workflow

### 1. Generate Offline Trace with Merlin

```bash
# Run Java program with ET3 agent
java -javaagent:path/to/instrumenter.jar YourProgram

# Run offline Merlin analysis
java -cp target/classes \
     veroy.research.et2.javassist.MerlinDeathTracker \
     trace_output/trace \
     trace_output/trace_offline \
     --verbose
```

This produces `trace_offline` with death records at the end.

### 2. Reorder Death Records

```bash
cd gem5-simulation/scripts

python3 reorder_deaths.py \
    ../../trace_output/trace_offline \
    ../../trace_output/trace_reordered \
    --validate
```

This produces `trace_reordered` with deaths in correct temporal positions.

### 3. Build Oracle

```bash
python3 build_oracle.py \
    ../../trace_output/trace_reordered \
    --output ../../trace_output/oracle.txt \
    --csv ../../trace_output/oracle.csv \
    --stats
```

This produces the oracle event stream with properly interleaved alloc/free events.

## Verification

### Check Death Positions

```bash
# See where deaths were inserted
grep -n "^D" trace_reordered | head -10

# Compare original vs reordered
diff -u trace_offline trace_reordered | less
```

### Verify Temporal Correctness

For each death record `D <obj-id> <thread-id> <timestamp>`:

1. **Death appears at correct position**: After logical time reaches `timestamp`
2. **Death after allocation**: Object was allocated before death
3. **No post-mortem references**: Object not referenced after death

### Example Validation

```bash
# Object 212628335 allocated at line 6, died at timestamp 4
# Should see death after line 7 (when logical time becomes 4)

$ grep -n "212628335" trace_reordered
6:N 212628335 24 3 62 0 1950409828
8:D 212628335 1950409828 4
```

✓ Allocation at line 6, death at line 8 (after line 7 where logical time became 4)

## Testing

### SimpleTrace Results

```
Total events: 32
Allocations: 16
Frees: 16
Live objects: 0
Total bytes: 440
```

All 16 allocations matched with 16 deaths, properly ordered.

### LotsOfAllocs Results

```
Total events: 2010
Allocations: 1005
Frees: 1005
Live objects: 0
Total bytes: 24160
```

All 1005 allocations matched with 1005 deaths, properly ordered.

## Common Issues

### Issue: Deaths appear too early

**Cause**: Logical clock calculation error
**Fix**: Verify M, E, X records all increment clock

### Issue: Deaths appear too late

**Cause**: Death timestamp may represent detection time, not actual death time
**Solution**: This is expected behavior - Merlin detects deaths at method exits

### Issue: Missing deaths

**Cause**: Objects never became unreachable (still live at program end)
**Solution**: This is correct - only unreachable objects get death records

## Implementation Notes

### Why Reordering is Necessary

1. **Oracle accuracy**: gem5 simulation needs temporal ordering
2. **Lifetime analysis**: Calculate accurate object lifetimes
3. **Memory simulation**: Track heap size over time correctly

### Performance

- **SimpleTrace (125 lines)**: < 0.1 seconds
- **LotsOfAllocs (5000+ lines)**: < 0.5 seconds
- **Large traces (1M+ lines)**: ~5-10 seconds

Time complexity: O(n log n) for sorting deaths, O(n) for merging

### Memory Usage

Script loads entire trace into memory. For very large traces (>1GB), consider streaming approach.

## References

- **Merlin Algorithm**: Hertz et al., "Generating object lifetime traces with Merlin"
- **Elephant Tracks**: Ricci et al., "Portable Production of Complete and Precise GC Traces"
- **MerlinDeathTracker.java**: Implementation of offline Merlin analysis
- **ETProxy.java**: Logical clock implementation (lines 38-46, 80-82)

## See Also

- [ORACLE_BUILDER.md](ORACLE_BUILDER.md) - Building oracle from reordered traces
- [TRACE_FORMAT.md](TRACE_FORMAT.md) - ET trace format specification
- [MERLIN_README.md](../../MERLIN_README.md) - Merlin implementation overview
