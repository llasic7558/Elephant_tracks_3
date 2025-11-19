# Logical Clock Implementation

## Overview

ET3 uses a **logical clock** for time measurement instead of real time (e.g., `System.nanoTime()`). This ensures traces are deterministic, portable, and suitable for simulation.

## Why Logical Time?

### Problems with Real Time

From the Elephant Tracks paper:
> "Real time is a bad choice, since it is dependent on many factors, including the virtual machine, the operating system, and the hardware."

**Issues**:
- ❌ Non-deterministic (varies across runs)
- ❌ Machine-dependent (different on different hardware)
- ❌ Includes tracing overhead
- ❌ Not suitable for gem5 simulation
- ❌ Huge numbers (nanoseconds)

### Benefits of Logical Time

- ✅ **Deterministic**: Same program → same timestamps
- ✅ **Portable**: Works on any VM/OS/hardware
- ✅ **Simulation-ready**: gem5 can replay at logical time
- ✅ **Comparable**: Can compare traces across machines
- ✅ **No overhead bias**: Doesn't measure tracing time
- ✅ **Small integers**: Easy to read and analyze

## Implementation

### Clock State

```java
// In ETProxy.java
private static AtomicInteger logicalClock = new AtomicInteger(0);
```

### Clock Semantics

The logical clock **ticks only at method boundaries**:

| Event Type | Action | Example |
|------------|--------|---------|
| Method entry (M) | **Tick** (increment) | 5 → 6 |
| Method exit (E) | **Tick** (increment) | 6 → 7 |
| Object allocation (N/A) | Use current (no tick) | stays 7 |
| Field update (U) | Use current (no tick) | stays 7 |
| Object death (D) | Use current (no tick) | stays 7 |

### Method Entry

```java
public static void onEntry(int methodId, int receiverHash, long threadId) {
    // TICK the clock
    long timestamp = logicalClock.incrementAndGet();
    
    // Write M record with logical time
    String record = String.format("M %d %d %d", methodId, receiverHash, timestamp);
    traceWriter.println(record);
    
    // Update Merlin tracker
    MerlinTracker.onMethodEntry(methodId, receiverHash, threadId);
}
```

### Method Exit

```java
public static void onExit(int methodId, long threadId) {
    // Get deaths before ticking (they occur at current time)
    List<MerlinTracker.DeathRecord> deaths = 
        MerlinTracker.onMethodExit(methodId, threadId);
    
    // TICK the clock
    long timestamp = logicalClock.incrementAndGet();
    
    // Write E record with logical time
    String record = String.format("E %d %d", methodId, timestamp);
    traceWriter.println(record);
    
    // Write death records (use timestamp from method exit)
    for (MerlinTracker.DeathRecord death : deaths) {
        String deathRecord = String.format("D %d %d %d", 
            death.objectId, death.threadId, timestamp);
        traceWriter.println(deathRecord);
    }
}
```

### Other Events (No Tick)

```java
public static void onObjectAlloc(...) {
    // Use current time (no tick)
    long timestamp = logicalClock.get();
    
    String record = String.format("N %d %d %d %d %d %d", 
        objectId, size, typeId, siteId, 0, timestamp);
    traceWriter.println(record);
}

public static void onPutField(...) {
    // Use current time (no tick)
    long timestamp = logicalClock.get();
    
    String record = String.format("U %d %d %d %d", 
        tgtObjectId, srcObjectId, fieldId, timestamp);
    traceWriter.println(record);
}
```

### Accessor for Merlin

```java
public static long getLogicalTime() {
    return logicalClock.get();
}
```

## Example Trace Flow

### Before (Real Time - WRONG ❌)

```
M 100 1001 174837450676400    ← Nanoseconds!
N 1002 32 200 100 0 174837450676450
E 100 174837450680000
D 1002 5001 174837450680000
```

**Problems**:
- Huge numbers
- Non-deterministic
- Includes overhead

### After (Logical Time - CORRECT ✅)

```
M 100 1001 1        ← Clock ticked 0→1
N 1002 32 200 100 0 1    ← Time 1 (no tick)
U 1001 1002 3 1     ← Time 1 (no tick)
E 100 2             ← Clock ticked 1→2
D 1002 5001 2       ← Death at time 2
M 200 0 3           ← Clock ticked 2→3
E 200 4             ← Clock ticked 3→4
```

**Benefits**:
- Small integers (1, 2, 3, 4)
- Deterministic
- Easy to read

## Complete Example

### Java Program

```java
public class Example {
    public static void main(String[] args) {
        Object obj = new Object();  // Allocation
        useObject(obj);             // Method call
    }
    
    static void useObject(Object o) {
        // Use object
    }
}
```

### Generated Trace with Logical Time

```
# Initial state: clock = 0

M 100 0 1          # main() entry: clock 0→1
N 1001 16 200 100 0 1   # new Object() at time 1
M 200 1001 2       # useObject() entry: clock 1→2
E 200 3            # useObject() exit: clock 2→3
E 100 4            # main() exit: clock 3→4
D 1001 5001 4      # obj dies at time 4 (after main exits)
```

## Temporal Ordering

Logical time preserves **happens-before relationships**:

```
event1 → event2  ⟹  timestamp1 ≤ timestamp2
```

**Examples**:
- Allocation before death: `N(t=1) → D(t=4)` ✅
- Method entry before exit: `M(t=2) → E(t=3)` ✅
- Field update before death: `U(t=2) → D(t=4)` ✅

## Integration with Merlin

### Death Timestamps

```java
// In MerlinTracker.java
public static List<DeathRecord> onMethodExit(...) {
    // Perform reachability analysis
    Set<Integer> deadObjects = findDeadObjects();
    
    // Use current logical time for deaths
    long currentTime = ETProxy.getLogicalTime();
    
    List<DeathRecord> deaths = new ArrayList<>();
    for (Integer objId : deadObjects) {
        deaths.add(new DeathRecord(objId, threadId, currentTime));
    }
    
    return deaths;
}
```

### Reachability Analysis Timing

Reachability analysis happens **at method exit** (when clock is about to tick):

```
1. Method execution
2. Stack frame about to pop
3. Reachability analysis (uses current time)
4. Deaths detected (stamped with current time)
5. Clock ticks for method exit
6. E record written (new time)
7. D records written (with time from step 4)
```

## Verification

### Check Logical Time is Working

```bash
# Run a test
java -javaagent:instrumenter.jar SimpleTrace

# Check death timestamps
grep "^D" trace

# Good output (logical time):
# D 1001 5001 12
# D 1002 5001 15
# D 1003 5001 20

# Bad output (real time):
# D 1001 5001 174837450676400
# D 1002 5001 174837450680000
# D 1003 5001 174837450685000
```

### Verify Monotonicity

```bash
# Extract all timestamps
awk '{print $NF}' trace | sort -n | uniq -c

# Should see small, sequential integers
# 1   1
# 5   2
# 3   3
# 2   4
# ...
```

### Test Determinism

```bash
# Run twice
java -javaagent:instrumenter.jar SimpleTrace > /dev/null
cp trace trace1

java -javaagent:instrumenter.jar SimpleTrace > /dev/null  
cp trace trace2

# Compare
diff trace1 trace2

# Should be identical!
```

## Historical Context

### Original Bug (Fixed)

**Before**: Used `System.nanoTime()` everywhere

```java
// WRONG - non-deterministic
long timestamp = System.nanoTime();
```

**Death records**: `D 1001 5001 174837450676400`

**Problems**:
- Different on every run
- Different on every machine
- Can't compare traces
- Not suitable for simulation

### Fix

Changed to logical clock that ticks at method boundaries:

```java
// CORRECT - deterministic
long timestamp = logicalClock.incrementAndGet(); // for M/E
long timestamp = logicalClock.get();             // for N/A/U/D
```

**Death records**: `D 1001 5001 12`

See `LOGICAL_CLOCK_EXPLAINED.md` (archived) for detailed explanation.

## Performance Impact

### Overhead

Logical clock has **minimal overhead**:

```java
// AtomicInteger increment/get is very fast
logicalClock.incrementAndGet();  // ~10 nanoseconds
logicalClock.get();              // ~5 nanoseconds
```

Compared to:
- Method call overhead: ~100-1000 nanoseconds
- Trace writing: ~1000-10000 nanoseconds

**Conclusion**: Negligible (<1% of total overhead)

### Thread Safety

`AtomicInteger` ensures thread-safe clock updates without locking:

```java
private static AtomicInteger logicalClock = new AtomicInteger(0);
```

Multiple threads can safely tick the clock concurrently.

## Simulation Benefits

### gem5 Integration

Logical time enables **deterministic replay** in gem5:

1. Parse trace with logical timestamps
2. Execute allocation/death events at logical time
3. No real-time dependencies
4. Reproducible simulations

### Oracle Files

Oracle CSV files use logical time:

```csv
time,event_type,object_id,size
1,alloc,1001,32
2,alloc,1002,48
4,death,1001,32
6,death,1002,48
```

gem5 memory allocator can process these events in order.

## Summary

### What Changed

| Aspect | Before (Real Time) | After (Logical Time) |
|--------|-------------------|---------------------|
| Timestamps | Nanoseconds (~10^15) | Small integers (1,2,3...) |
| Determinism | ❌ Non-deterministic | ✅ Deterministic |
| Portability | ❌ Machine-dependent | ✅ Portable |
| Simulation | ❌ Not suitable | ✅ Ready for gem5 |
| Overhead | Measures tracing | No overhead bias |

### Clock Rules

1. **Tick at method entry** (M records)
2. **Tick at method exit** (E records)
3. **Don't tick for other events** (N, A, U, D records)
4. **Use current time for non-method events**

### Result

✅ **ET3 now uses logical time as specified in the Elephant Tracks paper**  
✅ **Traces are deterministic and simulation-ready**  
✅ **Death timestamps are meaningful for analysis**

## References

- Original Elephant Tracks paper (describes logical time motivation)
- Merlin paper (method-boundary timing)
- gem5 simulation documentation

## Next Steps

- See [Merlin Implementation](merlin.md) for death detection details
- Read [Architecture Overview](architecture.md) for system design
- Review [Oracle Construction](../development/oracle.md) for simulation files
