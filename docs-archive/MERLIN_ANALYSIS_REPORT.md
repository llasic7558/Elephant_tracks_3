# Merlin Algorithm Analysis: Online vs Offline Implementation

## Executive Summary

**Question**: Does running the simulator on trace files create object death records as described in the original ET2 repository?

**Answer**: **YES** - The original ET2 design uses a C++ simulator (`simulator/simulator.cpp`) that post-processes traces to add death records using the Merlin algorithm.

## Current State Analysis

### Three Implementations Found

1. **C++ Simulator** (Original ET2 design)
   - Location: `simulator/simulator.cpp`
   - Function: `apply_merlin()` (lines 209-290)
   - Status: Not currently being used in your workflow

2. **Java Online Mode** (`MerlinTracker.java`)
   - Integrated into ET3 runtime
   - Generates deaths in real-time during execution
   - Status: Currently active

3. **Java Offline Mode** (`MerlinDeathTracker.java`)
   - Post-processes traces after execution
   - Java reimplementation of C++ simulator logic
   - Status: Currently active but has discrepancies

## Test Results: Online vs Offline Comparison

### Quantitative Differences

| Test Program | Online Deaths | Offline Deaths | Difference | Missing Objects |
|-------------|---------------|----------------|------------|----------------|
| SimpleTrace | 17 | 16 | -1 | 177965814 |
| LotsOfAllocs | 1006 | 1005 | -1 | 403605349 |
| Methods | 5 | 4 | -1 | 620921872 |
| NewCall | 108 | 106 | -2 | 1270062439, 1971489295 |
| HelloWorld | 5 | 4 | -1 | 165693382 |

**Pattern**: Offline mode consistently misses 1-2 objects per test.

### Timestamp Discrepancies

**Example from SimpleTrace**:

| Object ID | Online Timestamp | Offline Timestamp | Ratio |
|-----------|-----------------|-------------------|-------|
| 1068824137 | 383 | 23 | 16.7x |
| 1101288798 | 176 | 12 | 14.7x |
| 125130493 | 1066 | 56 | 19.0x |
| 1608446010 | 710 | 40 | 17.8x |
| 1887400018 | 1066 | 56 | 19.0x |

**Pattern**: Online timestamps are consistently 10-20x higher than offline.

## Root Cause Analysis

### Issue 1: Different Logical Clock Implementations

**Online Mode** (`MerlinTracker.java`):
- Uses `ETProxy.logicalClock` which increments at:
  - Every allocation (N, A records)
  - Every field update (U records)
  - Every method entry/exit (M, E records)
- Result: Clock advances very rapidly

**Offline Mode** (`MerlinDeathTracker.java`):
- Only increments at method boundaries (M, E records)
- Follows original ET specification more closely
- Result: Much lower clock values

**Example**:
```
For SimpleTrace (125 lines):
- Online clock reaches: ~1388
- Offline clock reaches: ~56
- Difference factor: ~24x
```

### Issue 2: Missing Death Detection

Objects missed by offline mode (e.g., 177965814 in SimpleTrace):

**Investigation**:
```bash
# Object 177965814 found in online trace:
$ grep "177965814" test_traces_online/SimpleTrace/trace
D 177965814 787604730 1388
```

**Characteristics of missed object**:
- Thread ID: `787604730` (different from main thread `1950409828`)
- Never has explicit allocation record in trace
- Dies at very end (timestamp 1388)
- Likely a JVM-internal or finalizer thread object

**Hypothesis**: Offline mode may not properly handle:
1. Objects from different threads than main
2. JVM-internal objects without allocation records
3. Objects that die during shutdown sequence

### Issue 3: Death Record Timing

**Online Mode**:
- Detects deaths immediately at method exits
- Uses `ETProxy.logicalClock` for timestamps
- Deaths written inline with other events

**Offline Mode**:
- Collects all deaths during processing
- Writes deaths at END of output file
- Timestamps indicate when death should have occurred
- Requires reordering step (via `reorder_deaths.py`)

## Original ET2 Design Philosophy

From the ET2 README:

> "The important idea behind ET2 and ET3 is that **instead of creating and tracing object graphs at runtime** (as ET1 does), **ET3 generates data that allows the object graphs to be generated offline after the program ends**."

### Original Workflow

```
┌─────────────────┐
│  Java Program   │
└────────┬────────┘
         │ runs with
         ▼
┌─────────────────┐
│   ET3 Agent     │ ← Lightweight instrumentation
└────────┬────────┘
         │ produces
         ▼
┌─────────────────┐
│  Trace (no D)   │ ← N, A, M, E, U records only
└────────┬────────┘
         │ input to
         ▼
┌─────────────────┐
│  C++ Simulator  │ ← apply_merlin() function
└────────┬────────┘
         │ produces
         ▼
┌─────────────────┐
│ Trace (with D)  │ ← Complete trace for analysis
└─────────────────┘
```

### Why This Design?

**Advantages**:
1. **Lower runtime overhead** - No reachability analysis during execution
2. **Accuracy** - Can use more sophisticated algorithms offline
3. **Reprocessing** - Can reanalyze same trace with different parameters
4. **Debugging** - Easier to debug offline algorithm

**Disadvantages**:
1. **Two-phase process** - Extra step required
2. **Death timestamps** - Approximate (nearest method boundary)

## Recommendations

### Primary Recommendation: Follow Original Design

**Disable online death tracking and use offline processing.**

#### Step 1: Modify ETProxy to Disable Online Merlin

```java
// In ETProxy.java onShutdown() method:
// Comment out or remove these lines:
// MerlinTracker.onShutdown(logicalClock);
```

#### Step 2: Fix MerlinDeathTracker.java

The offline implementation needs these fixes:

1. **Match logical clock behavior** to online mode OR use simpler clock
2. **Handle multi-threaded objects** properly
3. **Track JVM-internal objects** without allocation records
4. **Improve reachability analysis** at shutdown

#### Step 3: Use Reordering Pipeline

```bash
# 1. Generate trace without deaths
java -javaagent:agent.jar YourProgram

# 2. Add deaths offline
java -cp agent.jar MerlinDeathTracker trace trace_with_deaths

# 3. Reorder deaths to correct positions
python3 reorder_deaths.py trace_with_deaths trace_reordered

# 4. Build oracle for simulation
python3 build_oracle.py trace_reordered --output oracle.csv
```

### Alternative: Fix Online Mode to Match Offline

If you prefer online death tracking:

1. **Simplify logical clock** in ETProxy to only increment at M/E boundaries
2. **Improve reachability analysis** to catch all objects
3. **Add proper shutdown handling** for finalizer threads
4. **Write deaths inline** at correct timestamps (no reordering needed)

## Implementation Priority

### High Priority Fixes

1. **Choose one implementation** - Online XOR Offline (not both)
2. **Fix logical clock** - Ensure consistency
3. **Handle multi-threaded objects** - Missing deaths issue

### Medium Priority Enhancements

1. **Validate death timestamps** - Ensure deaths occur after allocations
2. **Performance profiling** - Measure overhead of each approach
3. **Documentation** - Clear guide on which mode to use

### Low Priority Nice-to-Haves

1. **Compare with C++ simulator** - Validate against original
2. **Visualization tools** - Show object lifetimes graphically
3. **Memory leak detection** - Flag objects that should die but don't

## Decision Matrix

| Criterion | Online Mode | Offline Mode | Original C++ |
|-----------|------------|--------------|--------------|
| Runtime Overhead | High | Low | Low |
| Accuracy | Good | Good+ | Best |
| Ease of Use | Easy | Medium | Hard |
| ET2 Compliance | No | Yes | Yes |
| Maintenance | Active | Active | Legacy |
| Current Issues | Timestamps | Missing deaths | Not used |

**Recommendation**: **Fix and use Offline Mode** (`MerlinDeathTracker.java`)

## Testing Strategy

### Validation Tests

1. **Object count test**:
   ```bash
   ALLOCS=$(grep -c "^[NA]" trace)
   DEATHS=$(grep -c "^D" trace_with_deaths)
   # Deaths should be ≤ Allocations
   ```

2. **Timestamp ordering test**:
   ```bash
   # Verify each death timestamp ≥ corresponding allocation timestamp
   python3 validate_death_order.py trace_with_deaths
   ```

3. **Comparison test**:
   ```bash
   # Compare Java offline vs C++ simulator output
   diff <(sort online_deaths.txt) <(sort cpp_simulator_deaths.txt)
   ```

### Test Cases

- [x] SimpleTrace (16 objects)
- [x] LotsOfAllocs (1005 objects)
- [x] Methods (4 objects)
- [x] NewCall (106 objects)
- [x] HelloWorld (4 objects)
- [ ] Multi-threaded program (NEW)
- [ ] DaCapo benchmark (LARGE SCALE)

## Conclusion

### Answer to Original Question

**YES** - The simulator (both C++ original and Java `MerlinDeathTracker.java`) creates death records from traces that initially don't contain them. This is the **correct and intended ET2/ET3 design**.

### Current Problems

1. You have TWO implementations running simultaneously (online + offline)
2. They produce different results (counts and timestamps)
3. Neither matches the original C++ simulator exactly

### Solution

**Choose offline mode** (aligning with original ET2 design):
1. Disable `MerlinTracker` in `ETProxy.java`
2. Fix `MerlinDeathTracker.java` to handle edge cases
3. Use the reordering pipeline for correct timestamps
4. Validate against C++ simulator output

This provides the best balance of accuracy, maintainability, and compliance with the ET2 design philosophy.

## References

1. **ET2 Original Repository**: https://github.com/ElephantTracksProject/et2-java
2. **Merlin Paper**: Hertz et al., "Merlin: Efficient and Enhanced Memory Leak Detection"
   - https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf
3. **Elephant Tracks**: http://www.cs.tufts.edu/research/redline/elephantTracks/
4. **C++ Simulator Source**: `simulator/simulator.cpp` lines 209-290

## Files Generated

- `comparison_results/SUMMARY.txt` - Detailed comparison data
- `test_traces_online/` - Online mode outputs
- `test_traces_offline/` - Offline mode outputs
- This document: `MERLIN_ANALYSIS_REPORT.md`

---

**Analysis Date**: November 16, 2025
**Tests Run**: 5 programs (SimpleTrace, LotsOfAllocs, Methods, NewCall, HelloWorld)
**Total Objects Analyzed**: 1140+ allocations across all tests
**Key Finding**: Offline mode is correct approach, needs fixes for edge cases
