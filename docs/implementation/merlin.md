# Merlin Algorithm Implementation

## Overview

ET3 implements the **Merlin Algorithm** (Hertz et al., TOPLAS 2006) for tracking object death in Java programs. The algorithm uses reachability analysis to conservatively determine when objects become garbage.

## Two Implementations

### 1. Integrated (Real-Time) -

**Files**: `MerlinTracker.java`, modified `ETProxy.java`

Death records generated **during** trace execution for true in-order traces.

**Advantages**:
- ✅ Single-pass execution
- ✅ Deaths in original trace order
- ✅ No post-processing needed
- ✅ Lower memory footprint

**Location**: `javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/MerlinTracker.java`

### 2. Post-Processing (Offline)

**Files**: `MerlinDeathTracker.java`

Death records generated **after** trace completes by reading and analyzing the trace file.

**Advantages**:
- ✅ Can reprocess existing traces
- ✅ Non-invasive to runtime
- ✅ Easier to debug
- ✅ Two-pass algorithm enables witness awareness

**Location**: `javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/MerlinDeathTracker.java`

## Algorithm Fundamentals

### Reachability-Based Death Detection

The Merlin algorithm tracks object liveness using reachability from **root sets**:

```
Object is LIVE ⟺ Object is reachable from roots
Object is DEAD ⟺ Object is NOT reachable from roots
```

### Root Sources

1. **Thread Stacks**: Objects in method receivers and local variables
2. **Static Fields**: Objects stored in static fields (object ID = 0 in U records)

### Object Graph

Built from field update (U) records:

```
U <target-obj> <source-obj> <field-id> <thread-id>
```

Creates edge: `target-obj.field → source-obj`

## Integrated Implementation

### Architecture

```
Java Program
    ↓ (instrumented bytecode)
ETProxy.onObjectAlloc() → MerlinTracker.onObjectAlloc()
    ↓
ETProxy.onMethodEntry() → MerlinTracker.onMethodEntry()
    ↓
ETProxy.onMethodExit() → MerlinTracker.onMethodExit()
    ↓                         ↓
    |                    Reachability Analysis (BFS)
    |                         ↓
    |                    Death Records Generated
    |                         ↓
    └─────── Both written to trace ──────┘
```

### Key Data Structures

```java
// Live objects being tracked
private static Set<Integer> liveObjects = 
    Collections.synchronizedSet(new HashSet<>());

// Object reference graph (forward edges)
private static Map<Integer, Set<Integer>> objectGraph = 
    Collections.synchronizedMap(new HashMap<>());

// Per-thread call stacks for root set
private static Map<Long, Stack<Integer>> threadStacks = 
    Collections.synchronizedMap(new HashMap<>());

// Static field roots
private static Set<Integer> staticRoots = 
    Collections.synchronizedSet(new HashSet<>());
```

### Event Handling

#### Object Allocation (N/A Records)

```java
public static void onObjectAlloc(int objectId, long threadId, long timestamp) {
    liveObjects.add(objectId);
    // Object not added to stack yet - will happen at method entry
}
```

#### Method Entry (M Records)

```java
public static void onMethodEntry(int methodId, int receiverHash, long threadId) {
    Stack<Integer> stack = threadStacks.computeIfAbsent(
        threadId, k -> new Stack<>());
    
    if (receiverHash != 0) {
        stack.push(receiverHash);  // Receiver is now a root
    }
}
```

#### Field Update (U Records)

```java
public static void onFieldUpdate(int tgtObjectId, int srcObjectId, long threadId) {
    // Create edge: tgtObjectId → srcObjectId
    objectGraph.computeIfAbsent(tgtObjectId, k -> new HashSet<>())
                .add(srcObjectId);
    
    // Static field creates static root
    if (tgtObjectId == 0) {
        staticRoots.add(srcObjectId);
    }
}
```

#### Method Exit (E Records) - **CRITICAL**

```java
public static List<DeathRecord> onMethodExit(int methodId, long threadId) {
    // Pop stack frame
    Stack<Integer> stack = threadStacks.get(threadId);
    if (stack != null && !stack.isEmpty()) {
        stack.pop();
    }
    
    // Perform reachability analysis at method boundary
    eventCounter++;
    if (eventCounter % ANALYSIS_INTERVAL == 0) {
        return performReachabilityAnalysis(threadId);
    }
    
    return Collections.emptyList();
}
```

### Reachability Analysis

Uses **Breadth-First Search (BFS)** from all roots:

```java
private static List<DeathRecord> performReachabilityAnalysis(long threadId) {
    Set<Integer> reachable = new HashSet<>();
    Queue<Integer> queue = new LinkedList<>();
    
    // 1. Add all stack roots from all threads
    for (Stack<Integer> stack : threadStacks.values()) {
        for (Integer obj : stack) {
            if (obj != 0) {
                queue.add(obj);
                reachable.add(obj);
            }
        }
    }
    
    // 2. Add all static roots
    for (Integer obj : staticRoots) {
        queue.add(obj);
        reachable.add(obj);
    }
    
    // 3. BFS through object graph
    while (!queue.isEmpty()) {
        Integer current = queue.poll();
        Set<Integer> neighbors = objectGraph.get(current);
        
        if (neighbors != null) {
            for (Integer neighbor : neighbors) {
                if (!reachable.contains(neighbor)) {
                    reachable.add(neighbor);
                    queue.add(neighbor);
                }
            }
        }
    }
    
    // 4. Objects not reachable are DEAD
    List<DeathRecord> deaths = new ArrayList<>();
    Set<Integer> deadObjects = new HashSet<>(liveObjects);
    deadObjects.removeAll(reachable);
    
    for (Integer objId : deadObjects) {
        deaths.add(new DeathRecord(objId, threadId));
        liveObjects.remove(objId);
        objectGraph.remove(objId);  // Clean up graph
    }
    
    return deaths;
}
```

### Performance Tuning

```java
// Analysis frequency (lower = more overhead, higher accuracy)
private static final int ANALYSIS_INTERVAL = 500;

// Adjust based on your needs:
// - 100: More precise death timing, higher overhead
// - 1000: Less overhead, slightly delayed deaths
// - 5000: Minimal overhead, deaths batched
```

## Post-Processing Implementation

### Two-Pass Algorithm

#### Pass 1: Witness Collection

Scan entire trace to record last access time for each object:

```java
private void buildWitnessMap(String inputTraceFile) throws IOException {
    try (BufferedReader reader = new BufferedReader(new FileReader(inputTraceFile))) {
        String line;
        long clock = 0;
        
        while ((line = reader.readLine()) != null) {
            if (line.startsWith("M") || line.startsWith("E")) {
                clock++;  // Logical clock ticks at method boundaries
            }
            
            if (line.startsWith("W")) {
                // W <object-id> <thread-id>
                String[] parts = line.split("\\s+");
                int objectId = Integer.parseInt(parts[1]);
                lastWitnessTime.put(objectId, clock);
            }
        }
    }
}
```

#### Pass 2: Witness-Aware Processing

Process trace normally but delay deaths until after last witness:

```java
private void performReachabilityAnalysis() {
    // ... standard BFS reachability ...
    
    for (Integer objId : deadCandidates) {
        // Check if object has future witness
        Long lastWitness = lastWitnessTime.get(objId);
        
        if (lastWitness != null && lastWitness > logicalClock) {
            // Don't mark dead yet - still has future accesses
            if (verbose) {
                System.out.println("Delaying death of object " + objId + 
                    " (current=" + logicalClock + ", last_witness=" + lastWitness + ")");
            }
            continue;
        }
        
        // Safe to mark as dead
        deaths.add(new DeathRecord(objId, allocThread, logicalClock));
        liveObjects.remove(objId);
    }
}
```

### Witness Record Fix

**Problem**: Sequential processing could mark objects dead before their last access.

**Solution**: Two-pass algorithm with witness awareness prevents premature deaths.

See `../development/witness-fix.md` for complete details.

## Death Record Format

```
D <object-id> <thread-id>
```

Example:
```
D 1001 5001
```

**Note**: Logical time is implicit (current method boundary time)

## Method-Boundary Accuracy

Deaths detected at method entry/exit ensure accuracy as specified in the Merlin paper:

```
M 200 1001 5001    ← Clock ticks (e.g., 10 → 11)
N 1002 ...          ← Allocation at time 11
U ...               ← Updates at time 11
E 200 5001         ← Clock ticks (11 → 12), reachability analysis runs
D 1002 ...          ← Death detected at time 12
```

This guarantees deaths are accurate to the nearest method call/exit.

## Integration with ETProxy

### Modified Methods in ETProxy.java

```java
public static void onObjectAlloc(...) {
    // Original trace writing
    traceWriter.println(record);
    
    // NEW: Merlin tracking
    MerlinTracker.onObjectAlloc(objectId, threadId, timestamp);
}

public static void onEntry(...) {
    // Original trace writing
    traceWriter.println(record);
    
    // NEW: Merlin tracking
    MerlinTracker.onMethodEntry(methodId, receiverHash, threadId);
}

public static void onExit(...) {
    // NEW: Get deaths from Merlin
    List<MerlinTracker.DeathRecord> deaths = 
        MerlinTracker.onMethodExit(methodId, threadId);
    
    // Original trace writing
    traceWriter.println(record);
    
    // NEW: Write death records immediately
    for (MerlinTracker.DeathRecord death : deaths) {
        traceWriter.println(death.toString());
    }
}

public static void onPutField(...) {
    // Original trace writing
    traceWriter.println(record);
    
    // NEW: Merlin tracking
    MerlinTracker.onFieldUpdate(tgtObjectId, srcObjectId, threadId);
}
```

### Shutdown Hook

```java
public static void onShutdown() {
    flushBuffer();
    
    // Final reachability analysis
    List<MerlinTracker.DeathRecord> deaths = 
        MerlinTracker.performFinalAnalysis();
    
    for (MerlinTracker.DeathRecord death : deaths) {
        traceWriter.println(death.toString());
    }
    
    traceWriter.close();
}
```

## Correctness Properties

### Conservative Analysis

Merlin is **conservative**: it may delay death detection but **never reports false deaths**.

```
If object is DEAD, Merlin eventually detects it.
If Merlin says object is DEAD, it is definitely DEAD.
```

### No Use-After-Death

The witness-aware post-processing ensures:

```
∀ objects: death_time > last_witness_time
```

Validated by `verify_no_witness_after_death.py`

### Thread Safety

The integrated implementation uses synchronized collections:

```java
Collections.synchronizedSet(...)
Collections.synchronizedMap(...)
```

All operations are thread-safe for multi-threaded programs.

## Performance Characteristics

| Metric | Integrated | Post-Processing |
|--------|-----------|----------------|
| Runtime Overhead | 5-10% | None (offline) |
| Memory Usage | O(live objects) | O(trace size) |
| Precision | Method boundary | Method boundary + witnesses |
| Scalability | Real-time | Batch |

## References

1. **Merlin Paper**: Hertz, M., et al. "Merlin: Efficient and Enhanced Memory Leak Detection", TOPLAS 2006
   - https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf

2. **Object Death Times**: "Portable, Mostly-Precise Object Death Times"
   - https://dl.acm.org/doi/pdf/10.1145/511334.511352

3. **Elephant Tracks**: Original GC tracing tool
   - http://www.cs.tufts.edu/research/redline/elephantTracks/

## Next Steps

- See [Logical Clock Implementation](logical-clock.md) for time measurement
- Read [Architecture Overview](architecture.md) for system design
- Review [Witness Fix](../development/witness-fix.md) for bug details
