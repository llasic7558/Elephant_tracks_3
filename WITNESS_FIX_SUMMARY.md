# Witness Record Bug Fix - Complete Summary

**Date**: November 16, 2025  
**Status**: ✅ FIXED AND VERIFIED

## Problem Discovered

User identified that object `1031980531` in SimpleTrace showed a **Witness (W) record AFTER its death record** in the reordered trace, which is impossible since dead objects cannot be accessed.

### Timeline (BEFORE FIX - BUGGY)
```
Clock 11: N 1031980531... ← Allocated
Clock 12: D 1031980531... ← DIED (too early!)
Clock 15: W 1031980531... ← Accessed (IMPOSSIBLE!)
```

## Root Cause

The offline `MerlinDeathTracker.java` performed reachability analysis **sequentially** without considering future witness records:

1. Object allocated → added to `liveObjects`
2. Method exit triggers reachability analysis → object not on stack → **marked DEAD**
3. Later W record encountered → tries to add to stack but already removed

The algorithm didn't look ahead to see if objects would be accessed later.

## Solution: Two-Pass Algorithm

### Pass 1: Collect Witness Times
```java
private void buildWitnessMap(String inputTraceFile) {
    // Scan entire trace first
    // Record last access time for each object via W records
    lastWitnessTime.put(objectId, clock);
}
```

### Pass 2: Witness-Aware Death Detection
```java
private void performReachabilityAnalysis() {
    // Check if object has future witness before marking dead
    Long lastWitness = lastWitnessTime.get(objectId);
    if (lastWitness != null && lastWitness > logicalClock) {
        continue; // Don't mark dead yet - still has future accesses
    }
    // Safe to mark as dead
}
```

## Implementation Changes

### Modified File: MerlinDeathTracker.java

1. **Added witness tracking field**:
   ```java
   private Map<Integer, Long> lastWitnessTime;
   ```

2. **Refactored `processTrace()` to use two passes**:
   - `buildWitnessMap()` - Pass 1: Collect all W record times
   - `processTraceWithWitnesses()` - Pass 2: Process with witness awareness

3. **Enhanced `performReachabilityAnalysis()`**:
   - Checks `lastWitnessTime` before marking objects dead
   - Delays death until after last witness

### Modified File: run_all_tests_pipeline.sh

Fixed NewCall compilation to include FooClass dependency:
```bash
elif [ "$test" == "NewCall" ]; then
    # NewCall also requires FooClass
    javac -d "$TEST_DIR" "$BASE_DIR/java/NewCall.java" "$BASE_DIR/java/FooClass.java" 2>/dev/null
```

## Verification Results

### Timeline for Object 1031980531 (AFTER FIX - CORRECT)
```
Clock 11: N 1031980531... ← Allocated
Clock 15: W 1031980531... ← Last accessed
Clock 16: D 1031980531... ← DIED (after last access) ✅
```

### Verbose Output Shows Fix Working
```
MerlinDeathTracker: Found witness records for 26 objects
Delaying death of object 1031980531 (current=12, last_witness=15)
Delaying death of object 1031980531 (current=14, last_witness=15)
```

### All Tests Pass Validation
```
✅ SimpleTrace: No witness-after-death violations
✅ HelloWorld: No witness-after-death violations
✅ Methods: No witness-after-death violations
✅ NewCall: No witness-after-death violations
✅ LotsOfAllocs: No witness-after-death violations
```

## Pipeline Results

### Test Statistics

| Test | Allocations | Deaths | Oracle Events | Witnesses |
|------|------------|--------|---------------|-----------|
| SimpleTrace | 16 (14N + 2A) | 16 | 32 | 50 |
| HelloWorld | 4 (3N + 1A) | 4 | 8 | 21 |
| Methods | 4 (3N + 1A) | 4 | 8 | 21 |
| NewCall | 7 (6N + 1A) | 7 | 14 | 69 |
| LotsOfAllocs | 1005 (1004N + 1A) | 1005 | 2010 | 31 |

### Generated Files (per test)

Each test in `pipeline_results/<test>/` contains:
- **trace**: Runtime trace (no deaths, offline mode)
- **trace_with_deaths**: Deaths appended at end with correct timestamps
- **trace_reordered**: Deaths inserted at correct temporal positions
- **oracle.txt**: Human-readable oracle event stream
- **oracle.csv**: Machine-readable oracle for gem5 simulation
- **SUMMARY.txt**: Test-specific statistics

## Impact

### Before Fix
- ❌ Objects marked dead before last use
- ❌ Invalid oracle files
- ❌ gem5 would free memory still being accessed
- ❌ All pipeline results were incorrect

### After Fix
- ✅ Objects only die after last witness
- ✅ Valid oracle files
- ✅ Correct temporal ordering
- ✅ Ready for gem5 memory allocator simulation

## Files Modified

1. `/Users/luka/Desktop/Honors_Thesis/et2-java/javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/MerlinDeathTracker.java`
   - Added two-pass algorithm
   - Added witness awareness to reachability analysis

2. `/Users/luka/Desktop/Honors_Thesis/et2-java/run_all_tests_pipeline.sh`
   - Fixed NewCall compilation to include FooClass

## Documentation Created

1. **WITNESS_RECORD_BUG.md**: Detailed analysis of the bug
2. **WITNESS_FIX_SUMMARY.md**: This document

## Next Steps

The pipeline is now complete and all oracle files are valid. Next steps:

1. ✅ Use oracle CSV files as input to gem5 memory allocator simulation
2. ✅ Compare allocator performance across workloads
3. ✅ Analyze memory allocation patterns

## Key Learnings

1. **Offline algorithms must consider future events**: Sequential processing can miss temporal dependencies
2. **Two-pass algorithms enable look-ahead**: First pass gathers metadata, second pass uses it
3. **Witness records are critical for correctness**: They prove liveness and prevent premature deaths
4. **Test-driven debugging**: User's observation of impossible state led to complete fix

## Conclusion

The two-pass algorithm successfully fixes the witness-after-death bug. All 5 test programs now generate correct traces and valid oracles ready for gem5 simulation.

**Bug Status**: RESOLVED ✅  
**Pipeline Status**: OPERATIONAL ✅  
**Oracle Files**: VALID ✅
