# Logical Clock vs Real Time in Elephant Tracks

## The Problem with Real Time

### Why System.nanoTime() is Wrong

From the Elephant Tracks paper:

> "Real time is a bad choice, since it is dependent on many factors, including the virtual machine, the operating system, and the hardware. In addition, tracing tends to slow programs down significantly, so the real times are likely to be significantly different from uninstrumented runs. Real time is also, in some sense, too precise: we do not want the trace to reflect the time it takes to actually perform a timestamp or record a trace record."

### Issues:
- ❌ **VM/OS/Hardware dependent** - timestamps vary across systems
- ❌ **Tracing overhead** - instrumentation slows program, distorts times
- ❌ **Too precise** - includes time to write trace records
- ❌ **Non-deterministic** - same program gives different times each run
- ❌ **Simulation problems** - simulators need logical time, not wall-clock

## The Solution: Logical Clock

### What is a Logical Clock?

A **logical clock** is simply a counter that increments at specific program events, independent of real time.

```java
// Logical clock (what ET uses)
private static AtomicInteger logicalClock = new AtomicInteger(0);

// Method entry: clock TICKS
public static void onEntry(int methodId, Object receiver) {
    long timestamp = logicalClock.incrementAndGet();  // Tick!
    // ... record M event with timestamp
}

// Method exit: clock TICKS
public static void onExit(int methodId) {
    long timestamp = logicalClock.incrementAndGet();  // Tick!
    // ... record E event with timestamp
}

// Allocation: use CURRENT time (no tick)
public static void onObjectAlloc(Object obj, ...) {
    long timestamp = logicalClock.get();  // No tick
    // ... record N event with timestamp
}

// Field update: use CURRENT time (no tick)
public static void onPutField(Object tgt, Object src, int fieldId) {
    long timestamp = logicalClock.get();  // No tick
    // ... record U event with timestamp
}
```

### The Key Insight

From the paper:
> "We do not actually output the time value, but **it can be derived by knowing which events 'tick' the clock**."

This means:
- **Method entry/exit are the ONLY events that tick the clock**
- **All other events (alloc, update) use the current clock value**
- Timestamps in the trace can be reconstructed by counting M/E records

## Clock Behavior

### Example Trace with Logical Clock

```
Time | Event | Description
-----|-------|-------------
  0  | Start | Program begins (clock = 0)
  1  | M 100 | Method entry (clock ticks: 0→1)
  1  | N 123 | Object allocated (uses time 1, no tick)
  1  | N 456 | Another object (uses time 1, no tick)
  2  | E 100 | Method exit (clock ticks: 1→2)
  2  | D 123 | Object died (death time = 2)
  3  | M 200 | Method entry (clock ticks: 2→3)
  3  | U ... | Field update (uses time 3, no tick)
  4  | E 200 | Method exit (clock ticks: 3→4)
```

### Properties:
✅ **Deterministic** - same program, same timestamps  
✅ **VM-independent** - works on any JVM  
✅ **No overhead bias** - doesn't include tracing time  
✅ **Simulation-ready** - simulators replay events at logical time  
✅ **Comparable** - can compare runs across machines  

## Implementation in ET3

### Before (WRONG - using real time):
```java
// ETProxy.java - OLD
public static void onEntry(int methodId, Object receiver) {
    long timestamp = System.nanoTime();  // ❌ Real time
    // ...
}

public static void onObjectAlloc(Object obj, ...) {
    long timestamp = System.nanoTime();  // ❌ Real time
    // ...
}

// MerlinTracker.java - OLD
long currentTime = System.nanoTime();  // ❌ Real time
deaths.add(new DeathRecord(objId, threadId, currentTime));
```

### After (CORRECT - using logical clock):
```java
// ETProxy.java - NEW
private static AtomicInteger logicalClock = new AtomicInteger(0);

public static void onEntry(int methodId, Object receiver) {
    long timestamp = logicalClock.incrementAndGet();  // ✅ Tick clock
    // ...
}

public static void onExit(int methodId) {
    long timestamp = logicalClock.incrementAndGet();  // ✅ Tick clock
    // ...
}

public static void onObjectAlloc(Object obj, ...) {
    long timestamp = logicalClock.get();  // ✅ Current time (no tick)
    // ...
}

public static long getLogicalTime() {
    return logicalClock.get();  // ✅ Accessor for Merlin
}

// MerlinTracker.java - NEW
long currentTime = ETProxy.getLogicalTime();  // ✅ Logical time
deaths.add(new DeathRecord(objId, threadId, currentTime));
```

## Why This Matters for Merlin

### Death Timestamps Must Be Logical

From the paper:
> "For Merlin to produce precise death times, the timestamp on an object must always be **the time at which the object last lost an incoming reference**."

With logical clock:
```
Time 5: M entry (clock: 4→5)
Time 5: N 1234 ... (object allocated)
Time 5: U 1234 ... (reference created)
Time 6: E exit (clock: 5→6)
Time 6: D 1234 ... (object died at logical time 6)
```

With real time (WRONG):
```
Time 1638473827391: M entry
Time 1638473827392: N 1234 ... (object allocated)
Time 1638473827393: U 1234 ...
Time 1638473827450: E exit (real time includes tracing overhead!)
Time 1638473827451: D 1234 ... (death time meaningless for simulation)
```

## Benefits for Simulation

### gem5 Replay

A simulator like gem5 can replay the trace at logical time:

```python
# Simulator replays trace
current_time = 0

for record in trace:
    if record.type == 'M':  # Method entry
        current_time += 1  # Tick
        execute_method_entry(record)
        
    elif record.type == 'E':  # Method exit
        current_time += 1  # Tick
        execute_method_exit(record)
        
    elif record.type == 'N':  # Allocation
        # Use current_time (no tick)
        allocate_object(record, at_time=current_time)
        
    elif record.type == 'D':  # Death
        # Death at the logical time recorded
        free_object(record, at_time=record.timestamp)
```

The simulator doesn't care about real time - it cares about **event ordering** and **logical time**.

## Comparison: Real Time vs Logical Clock

| Aspect | Real Time (nanoTime) | Logical Clock |
|--------|---------------------|---------------|
| **Value** | Wall-clock nanoseconds | Counter |
| **Determinism** | Non-deterministic | Deterministic |
| **Machine dependent** | Yes | No |
| **Includes overhead** | Yes | No |
| **Simulation ready** | No | Yes |
| **Comparable across runs** | No | Yes |
| **What it measures** | Elapsed wall time | Program progress |

## Example: SimpleTrace Program

### With Real Time (OLD):
```
M 40 752848266 1950409828 174837450676400
E 40 1950409828 174837450676401
N 1830908236 40 6 58 0 174837450676402
E 41 1950409828 174837450676450
D 1830908236 1950409828 174837450676400
```
Timestamps are random nanoseconds, meaningless for analysis.

### With Logical Clock (NEW):
```
M 40 752848266 1950409828 1
E 40 1950409828 2
N 1830908236 40 6 58 0 2
E 41 1950409828 3
D 1830908236 1950409828 3
```
Timestamps are logical events: Method entry (1), Method exit (2), Allocation at time 2, Exit at time 3, Death at time 3.

## Quote from the Paper

> "The most important [advantage] is that it works correctly for **any granularity of time**. In addition, it gives the trace generator explicit control over the model of variable liveness. Finally, it is amenable to an instrumentation-time optimization that eliminates redundant timestamping operations."

**Any granularity of time** = Logical clock works whether clock ticks are coarse (per method) or fine (per instruction).

## Implementation Details

### Thread Safety

```java
// AtomicInteger ensures thread-safe increment
private static AtomicInteger logicalClock = new AtomicInteger(0);

// Thread 1: onEntry() increments
long t1 = logicalClock.incrementAndGet();  // 1

// Thread 2: onEntry() increments
long t2 = logicalClock.incrementAndGet();  // 2

// No race conditions, monotonically increasing
```

### Clock Semantics

- **Global clock** - one clock for entire program (not per-thread)
- **Monotonic** - always increasing, never goes backward
- **Atomic** - thread-safe increments
- **Starts at 0** - first event is time 1

## Verification

To verify logical clock is working:

```bash
# Run test
java -javaagent:et3-agent.jar SimpleTrace

# Check timestamps are small integers (not nanoseconds)
head -20 trace
# Should see timestamps like 1, 2, 3, 4... not 174837450676400

# Count method events (should equal max timestamp)
method_count=$(grep -c "^[ME]" trace)
max_time=$(grep "^[NMEUAD]" trace | awk '{print $NF}' | sort -n | tail -1)
echo "Methods: $method_count, Max time: $max_time"
# max_time should be ≈ method_count (since M/E tick the clock)
```

## Summary

✅ **Changed**: `System.nanoTime()` → Logical clock  
✅ **Why**: Real time is VM/OS/hardware dependent, includes overhead, non-deterministic  
✅ **How**: Counter that ticks at method entry/exit  
✅ **Benefit**: Deterministic, simulation-ready, comparable traces  
✅ **Paper compliance**: Follows Elephant Tracks specification exactly  

This change makes ET3 traces **truly portable and suitable for simulation**.
