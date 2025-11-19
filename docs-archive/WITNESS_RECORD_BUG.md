# Critical Bug: Witness Records After Death

## Issue Discovered

Object `1031980531` in SimpleTrace shows a **Witness (W) record AFTER its death record** in the reordered trace.

## Timeline

```
Clock 11: N 1031980531... ← Object allocated
Clock 12: (death detected) ← Merlin marks object as dead
Clock 15: W 1031980531... ← Object accessed (IMPOSSIBLE!)
```

## Root Cause Analysis

### Problem 1: Merlin Death Tracker Timing

The offline `MerlinDeathTracker.java` performs reachability analysis **only at method exits** (E records):

```java
// Line 141-143 in processTraceRecord()
case "E": // Method exit: E <method-id> <thread-id>
    handleMethodExit(parts);
    performReachabilityAnalysis();  // ← Death detection happens here
    break;
```

**What happens:**
1. Object allocated at line 18 (clock 11)
2. Method exit at line 20 → reachability analysis runs → object marked dead (clock 12)
3. Later, W record at line 25 (clock 15) tries to mark object alive
4. But it's too late - death already recorded!

### Problem 2: W Records Don't Prevent Early Deaths

When a W record is processed:

```java
private void handleWitness(String[] parts) {
    int objectId = Integer.parseInt(parts[1]);
    long threadId = Long.parseLong(parts[3]);
    // Adds to stack frame - but reachability already ran!
    addToCurrentStackFrame(threadId, objectId);
}
```

**The object is added to the stack AFTER** it was already marked dead in an earlier reachability check.

## Why This Happens

The Merlin algorithm processes the trace **sequentially** in file order:

```
Line 18: N 1031980531  → Added to liveObjects
Line 19: E 62          → Reachability analysis runs
                       → Object not reachable → MARKED DEAD
                       → Death record created with timestamp=12
Line 25: W 1031980531  → Tries to add to stack
                       → But already removed from liveObjects!
```

The W record proves the object was STILL ALIVE at clock 15, but Merlin incorrectly determined it died at clock 12.

## The Actual Problem

**Objects that are accessed (W records) should NOT be marked as dead until AFTER their last access.**

The current algorithm:
1. ✗ Checks reachability at method exits
2. ✗ Doesn't look ahead for future W records
3. ✗ Marks objects dead too early

## Impact

- **Incorrect death timestamps**: Objects marked dead before their last use
- **Invalid oracle**: Free events occur while object is still being accessed
- **Simulation errors**: gem5 would try to free memory still in use

## Solutions

### Option 1: Two-Pass Algorithm (RECOMMENDED)

**Pass 1**: Collect all witness information
```java
// Scan entire trace first
Map<Integer, Long> lastAccessTime = new HashMap<>();
for (record : trace) {
    if (record is W) {
        lastAccessTime.put(objectId, currentLogicalClock);
    }
}
```

**Pass 2**: Perform reachability with witness constraints
```java
// Don't mark object dead if it has future witness records
if (lastAccessTime.get(objectId) > currentLogicalClock) {
    continue; // Object still alive - will be accessed later
}
```

### Option 2: Buffered Reachability Analysis

Delay death detection until we're sure no more W records will appear:

```java
// Don't immediately write death records
// Buffer them and verify no W records exist after death time
```

### Option 3: Remove W Records from Death Consideration

Treat W records as "hints" only, don't use for death detection:
```java
// Ignore W records in Merlin - use only stack/static roots
// But this loses valuable liveness information!
```

## Recommended Fix: Two-Pass Algorithm

```java
public void processTrace(String inputTraceFile, String outputTraceFile) throws IOException {
    // PASS 1: Build witness map
    Map<Integer, Long> lastWitnessTime = buildWitnessMap(inputTraceFile);
    
    // PASS 2: Process with witness-aware death detection
    processWithWitnesses(inputTraceFile, outputTraceFile, lastWitnessTime);
}

private boolean canDieNow(int objectId, long currentClock, Map<Integer, Long> witnesses) {
    Long lastWitness = witnesses.get(objectId);
    if (lastWitness == null) return true;  // No future witnesses
    return currentClock >= lastWitness;     // Past last witness
}
```

## Test Case

SimpleTrace object 1031980531:
- **Current (WRONG)**: Dies at clock 12, accessed at clock 15
- **Correct**: Should die AFTER clock 15 (its last witness)

## Verification Needed

Check all test programs for this pattern:
```bash
for dir in pipeline_results/*/; do
    echo "=== $(basename $dir) ==="
    # Find objects with W records after their death
    # This would require parsing and comparing timestamps
done
```

## Files Affected

1. **MerlinDeathTracker.java** - Needs two-pass algorithm
2. **reorder_deaths.py** - Works correctly (reorders by timestamp)
3. **build_oracle.py** - Will produce incorrect free times
4. **All oracle CSV files** - Currently invalid due to premature deaths

## Priority

**CRITICAL** - This invalidates all current oracle files for gem5 simulation.

## Next Steps

1. Implement two-pass algorithm in MerlinDeathTracker.java
2. Re-run all tests through pipeline
3. Verify no W records appear after deaths
4. Validate oracles for correctness

---

**Discovered**: November 16, 2025
**Status**: CRITICAL BUG - Needs immediate fix
**Impact**: All current oracle files are invalid
