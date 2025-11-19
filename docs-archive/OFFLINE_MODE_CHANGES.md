# ET3 Offline Mode Implementation - Changes Summary

## Date
November 16, 2025

## Overview
Implemented the recommended offline-only mode following the original ET2 design philosophy, plus fixed missing W (witness) records for getfield operations.

## Changes Made

### 1. Disabled Online MerlinTracker (ETProxy.java)

**Rationale**: Follow original ET2 design where traces are generated without death records, then post-processed offline.

**Changes**:
- Commented out all `MerlinTracker` method calls:
  - `MerlinTracker.onMethodEntry()` (line 109)
  - `MerlinTracker.onMethodExit()` (line 148)
  - `MerlinTracker.onObjectAlloc()` (lines 192, 283)
  - `MerlinTracker.onFieldUpdate()` (line 237)
  - `MerlinTracker.onShutdown()` (line 397)

**Result**: 
- Runtime traces now contain NO death records (D records)
- Shutdown message: "ET3 trace complete (offline Merlin mode - no death records yet)"
- Lower runtime overhead
- Traces ready for offline Merlin processing

### 2. Implemented Case 8: Witness Records (W) for GetField

**Problem**: Case 8 in `flushBuffer()` existed but was never triggered because getfield operations weren't instrumented.

**Changes**:

#### A. Added `onGetField` method to ETProxy.java (lines 240-280)
```java
public static void onGetField(Object obj, int classId) {
    // Generates W records: W <object-id> <class-id> <thread-id>
    // Shows object was accessed (proving liveness)
    eventTypeBuffer[currPtr] = 8; // Case 8: witness with get field
}
```

#### B. Instrumented field reads in MethodInstrumenter.java (lines 151-164)
```java
} else {
    // GETFIELD: Instrument object reference field reads
    if (!fieldType.isPrimitive() && !expr.isStatic()) {
        int classId = getClassId(fieldClassName);
        expr.replace("{ veroy.research.et2.javassist.ETProxy.onGetField($0, " + classId + "); $_ = $proceed($$); }");
    }
}
```

**Result**:
- W records now generated for all non-primitive instance field reads
- Test shows 50 W records in SimpleTrace
- Provides witness information for object liveness tracking

### 3. Added W Record Support to MerlinDeathTracker.java

**Problem**: Offline processor didn't recognize W records, causing "Unknown record type" warnings.

**Changes**:

#### A. Added case in processTraceRecord() (line 194-196)
```java
case "W": // Witness (getfield): W <object-id> <class-id> <thread-id>
    handleWitness(parts);
    break;
```

#### B. Implemented handleWitness() method (lines 375-389)
```java
private void handleWitness(String[] parts) {
    int objectId = Integer.parseInt(parts[1]);
    long threadId = Long.parseLong(parts[3]);
    // Object accessed = still alive - add to current stack frame
    addToCurrentStackFrame(threadId, objectId);
}
```

**Result**:
- MerlinDeathTracker now processes W records without warnings
- W records reinforce object reachability during analysis
- More accurate death detection

## Complete Workflow (Offline Mode)

### Step 1: Generate Trace (No Deaths)
```bash
javac -d trace_output java/YourProgram.java
cd trace_output
java -javaagent:../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar YourProgram
# Output: trace (contains N, A, M, E, U, W - NO D records)
```

### Step 2: Add Deaths Offline
```bash
java -cp ../javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     veroy.research.et2.javassist.MerlinDeathTracker \
     trace \
     trace_with_deaths \
     --verbose
# Output: trace_with_deaths (deaths appended at end)
```

### Step 3: Reorder Deaths (Optional - for gem5)
```bash
cd ../gem5-simulation/scripts
python3 reorder_deaths.py \
    ../../trace_output/trace_with_deaths \
    ../../trace_output/trace_reordered
# Output: trace_reordered (deaths in correct temporal order)
```

### Step 4: Build Oracle (for gem5 simulation)
```bash
python3 build_oracle.py \
    ../../trace_output/trace_reordered \
    --output ../../trace_output/oracle.csv
# Output: oracle.csv (alloc/free event stream)
```

## Test Results

### SimpleTrace with Offline Mode

**Runtime trace** (no deaths):
- Total lines: 158
- Method entries (M): 40
- Method exits (E): 39
- Allocations (N): 14
- Arrays (A): 2
- Field updates (U): 13
- **Witness/GetField (W): 50** ✓ NEW
- **Deaths (D): 0** ✓ Offline mode active

**After MerlinDeathTracker**:
- Total lines: 174
- **Deaths added (D): 16** ✓ Post-processing works

## Benefits of Offline Mode

### Advantages
1. **Lower runtime overhead** - No reachability analysis during execution
2. **ET2 compliance** - Matches original design philosophy
3. **Reprocessability** - Can re-analyze same trace with different parameters
4. **Debugging ease** - Easier to debug offline algorithm
5. **Witness records** - Additional liveness information from getfield

### Alignment with ET2 Design

From ET2 README:
> "The important idea behind ET2 and ET3 is that **instead of creating and tracing object graphs at runtime** (as ET1 does), **ET3 generates data that allows the object graphs to be generated offline after the program ends**."

Our implementation now follows this exactly.

## Record Types Generated

| Type | Format | Source | Description |
|------|--------|--------|-------------|
| M | `M <method-id> <receiver-id> <thread-id>` | Runtime | Method entry |
| E | `E <method-id> <thread-id>` | Runtime | Method exit |
| N | `N <obj-id> <size> <type-id> <site-id> 0 <thread-id>` | Runtime | Object allocation |
| A | `A <obj-id> <size> <type-id> <site-id> <length> <thread-id>` | Runtime | Array allocation |
| U | `U <obj-id> <target-id> <field-id> <thread-id>` | Runtime | Field update (putfield) |
| **W** | `W <obj-id> <class-id> <thread-id>` | Runtime | **Witness/getfield** ✓ NEW |
| D | `D <obj-id> <thread-id> <timestamp>` | Offline | Object death |

## Files Modified

1. **ETProxy.java**
   - Disabled MerlinTracker calls (6 locations)
   - Added `onGetField()` method for W records
   - Updated shutdown message

2. **MethodInstrumenter.java**
   - Added getfield instrumentation (else clause)
   - Generates W records for field reads

3. **MerlinDeathTracker.java**
   - Added W case in switch statement
   - Implemented `handleWitness()` method

## Verification Commands

```bash
# Check trace has no deaths
grep -c '^D' trace
# Should output: 0

# Check W records present
grep -c '^W' trace
# Should output: > 0

# Run offline Merlin
java -cp agent.jar veroy.research.et2.javassist.MerlinDeathTracker trace trace_with_deaths

# Verify deaths added
grep -c '^D' trace_with_deaths
# Should output: > 0
```

## Next Steps

1. **Test with DaCapo benchmarks** - Verify scalability
2. **Performance profiling** - Measure overhead reduction
3. **Compare with C++ simulator** - Validate against original
4. **Integrate with gem5** - Use oracle for memory simulation

## References

- **ET2 Repository**: https://github.com/ElephantTracksProject/et2-java
- **Merlin Paper**: Hertz et al., "Merlin: Efficient and Enhanced Memory Leak Detection"
- **Analysis Report**: See `MERLIN_ANALYSIS_REPORT.md`
- **Oracle Construction**: See `ORACLE_CONSTRUCTION.md`

## Summary

✅ **Offline mode active** - No runtime death tracking  
✅ **W records working** - Case 8 now generates witness records  
✅ **MerlinDeathTracker updated** - Processes all record types  
✅ **ET2 compliant** - Follows original design philosophy  
✅ **Complete pipeline** - trace → add deaths → reorder → oracle  

The system now operates exactly as the original ET2 designers intended: lightweight runtime tracing followed by offline analysis.
