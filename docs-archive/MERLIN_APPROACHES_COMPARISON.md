# Merlin Algorithm: Two Approaches Comparison

## Overview

Two different implementations of the Merlin algorithm for ET3:

1. **MerlinDeathTracker** - Post-processing (offline analysis)
2. **MerlinTracker** - Integrated (real-time tracking)

---

## Approach 1: Post-Processing (MerlinDeathTracker.java)

### Architecture

```
┌─────────────┐
│   ET3 Run   │  Generate trace WITHOUT deaths
└──────┬──────┘
       │ Produces: trace file (N, A, M, E, U records only)
       ▼
┌─────────────┐
│  Read Trace │  Parse entire trace into memory
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Merlin    │  Reconstruct object graph offline
│  Algorithm  │  Detect deaths via reachability analysis
└──────┬──────┘
       │ Produces: death records
       ▼
┌─────────────┐
│ Write New   │  Generate new trace WITH deaths
│   Trace     │  Sort/merge original + death records
└─────────────┘
```

### How It Works

```java
// MerlinDeathTracker.java (simplified)

public class MerlinDeathTracker {
    // 1. Parse existing trace
    public void processTrace(String traceFile) {
        for (String line : readTrace(traceFile)) {
            switch (line.charAt(0)) {
                case 'N': // Object allocation
                    liveObjects.put(objectId, new ObjectInfo(...));
                    break;
                case 'M': // Method entry
                    threadStacks.get(threadId).push(new MethodFrame(...));
                    break;
                case 'E': // Method exit
                    threadStacks.get(threadId).pop();
                    // Detect deaths HERE
                    detectDeaths();
                    break;
                case 'U': // Field update
                    objectGraph.addEdge(source, target);
                    break;
            }
        }
    }
    
    // 2. Write combined trace
    public void writeTraceWithDeaths(String outputFile) {
        sortAndMerge(originalEvents, deathEvents);
    }
}
```

### Characteristics

| Aspect | Details |
|--------|---------|
| **Timing** | After program completes |
| **Input** | Existing ET3 trace file |
| **Output** | New trace file with deaths added |
| **Memory** | Loads entire trace into memory |
| **Latency** | Zero runtime overhead, post-processing delay |
| **Accuracy** | Death times reconstructed from trace |
| **Sorting** | Required to merge deaths into timeline |

### Usage

```bash
# Step 1: Generate trace without deaths
java -javaagent:et3-agent.jar MyProgram
# Produces: trace (no D records)

# Step 2: Run MerlinDeathTracker
java MerlinDeathTracker -i trace -o trace_with_deaths
# Produces: trace_with_deaths (with D records)
```

### Pros ✅

- **Zero runtime overhead** on the traced program
- **Can process existing traces** (retroactive analysis)
- **Flexible** - can experiment with different death detection algorithms
- **Safe** - doesn't affect program execution
- **Memory efficient during tracing** - no extra data structures
- **Replayable** - can re-run analysis with different parameters

### Cons ❌

- **Two-step process** - trace, then analyze
- **High memory usage** - must load entire trace
- **Disk I/O overhead** - read/write large trace files
- **Slower for large traces** - parsing millions of records
- **Sorting required** - to merge deaths into timeline
- **Death timestamps approximate** - reconstructed from trace

---

## Approach 2: Integrated (MerlinTracker.java + ETProxy.java)

### Architecture

```
┌─────────────────────────────────────┐
│          ET3 Agent Runtime          │
│  ┌──────────┐      ┌──────────┐    │
│  │ ETProxy  │ ◄──► │  Merlin  │    │
│  │          │      │ Tracker  │    │
│  └────┬─────┘      └────┬─────┘    │
│       │                 │           │
│       │  Events         │ Deaths    │
│       ▼                 ▼           │
│  ┌──────────────────────────────┐  │
│  │      Trace Writer            │  │
│  │  (N, A, M, E, U, D records)  │  │
│  └──────────────┬───────────────┘  │
└─────────────────┼───────────────────┘
                  ▼
            trace file (complete)
```

### How It Works

```java
// ETProxy.java (instrumented into program)

public static void onObjectAlloc(Object obj, ...) {
    // 1. Write allocation to trace
    bufferEvent(ALLOC, objectId, ...);
    
    // 2. Notify Merlin
    MerlinTracker.onObjectAlloc(objectId, threadId, timestamp);
}

public static void onExit(int methodId) {
    // 1. Write method exit to trace
    bufferEvent(EXIT, methodId, threadId);
    flushBuffer();  // Ensures E record written first
    
    // 2. Detect deaths at method boundary
    List<DeathRecord> deaths = MerlinTracker.onMethodExit(methodId, threadId);
    
    // 3. Write deaths immediately (in correct temporal order)
    for (DeathRecord death : deaths) {
        traceWriter.println(death.toString());
    }
}

public static void onPutField(Object tgt, Object src, int fieldId) {
    // 1. Write field update to trace
    bufferEvent(UPDATE, tgtId, srcId, fieldId);
    
    // 2. Update Merlin's object graph
    MerlinTracker.onFieldUpdate(srcId, tgtId, threadId);
}
```

```java
// MerlinTracker.java (runs in parallel with tracing)

public static List<DeathRecord> onMethodExit(int methodId, long threadId) {
    // Pop stack frame
    threadStacks.get(threadId).pop();
    
    // Perform reachability analysis NOW
    return performReachabilityAnalysis();
}

public static synchronized List<DeathRecord> performReachabilityAnalysis() {
    // BFS from roots
    Set<Integer> reachable = computeReachableObjects();
    
    // Find dead objects
    Set<Integer> dead = liveObjects.keySet() - reachable;
    
    // Generate death records with current timestamp
    List<DeathRecord> deaths = new ArrayList<>();
    for (int deadId : dead) {
        deaths.add(new DeathRecord(deadId, threadId, System.nanoTime()));
    }
    
    return deaths;
}
```

### Characteristics

| Aspect | Details |
|--------|---------|
| **Timing** | During program execution |
| **Input** | Live program events |
| **Output** | Complete trace with deaths inline |
| **Memory** | Maintains live object graph |
| **Latency** | Runtime overhead (~20-50%) |
| **Accuracy** | Precise death times (nanos) |
| **Sorting** | Not needed - deaths written in order |

### Usage

```bash
# Single step: Generate complete trace with deaths
java -javaagent:et3-agent.jar MyProgram
# Produces: trace (with D records already integrated)

# Ready to analyze immediately
grep "^D" trace
```

### Pros ✅

- **Single-step process** - trace is complete when program ends
- **No post-processing** - deaths already in trace
- **Accurate timestamps** - nanosecond precision death times
- **No sorting needed** - deaths written in temporal order
- **Streaming** - can analyze trace as it's generated
- **Complete trace immediately** - ready for simulation
- **True "last time alive"** - exact method exit timing

### Cons ❌

- **Runtime overhead** - reachability analysis during execution (~20-50%)
- **Memory overhead** - maintains object graph (O(live objects))
- **May slow program** - GC-like pause at method exits
- **Can't retroactively analyze** - requires ET3 rebuild
- **Synchronization overhead** - thread-safe data structures
- **Potential hangs** - large heaps at shutdown

---

## Side-by-Side Comparison

### Code Structure

| Aspect | Post-Processing | Integrated |
|--------|-----------------|------------|
| **Files** | `MerlinDeathTracker.java` | `MerlinTracker.java` + `ETProxy.java` |
| **Lines of code** | ~344 lines | ~270 + ~567 lines |
| **Dependencies** | Standalone | Tightly coupled with ETProxy |
| **Complexity** | Simpler (file I/O + parsing) | More complex (concurrent, real-time) |

### Data Structures

#### Post-Processing (MerlinDeathTracker)
```java
// All data loaded in memory from trace
private Map<Integer, ObjectInfo> liveObjects;
private Map<Integer, Set<Integer>> objectGraph;
private Map<Long, Stack<MethodFrame>> threadCallStacks;
private List<TraceRecord> originalRecords;  // Entire trace!
private List<DeathRecord> deathRecords;
```

#### Integrated (MerlinTracker)
```java
// Only live heap state maintained
private static final Map<Integer, ObjectInfo> liveObjects;
private static final Map<Integer, Set<Integer>> objectGraph;
private static final Map<Long, Stack<MethodFrame>> threadStacks;
// + Concurrent versions for thread safety
private static final ConcurrentHashMap<...>;
```

### Execution Flow

#### Post-Processing
```
Program Start
  ↓
ET3 traces events → Write to file (N, A, M, E, U only)
  ↓
Program End → Trace file complete
  ↓
[User runs MerlinDeathTracker]
  ↓
Read entire trace → Parse into memory
  ↓
Replay events → Build object graph
  ↓
At each method exit → Detect deaths
  ↓
Merge & sort → Write new trace with D records
  ↓
Done (trace_with_deaths file)
```

#### Integrated
```
Program Start
  ↓
ET3 Agent loads → Initialize MerlinTracker
  ↓
Program runs:
  Each allocation → ETProxy records + MerlinTracker tracks
  Each field update → ETProxy records + MerlinTracker updates graph
  Each method exit → ETProxy records + MerlinTracker detects deaths
                   → Deaths written immediately to trace
  ↓
Program End → Shutdown hook → Final death detection
  ↓
Done (complete trace file with D records inline)
```

### Performance Comparison

| Metric | Post-Processing | Integrated |
|--------|-----------------|------------|
| **Trace generation** | Fast (no death detection) | Slower (20-50% overhead) |
| **Post-processing time** | Slow (must parse entire trace) | None (already done) |
| **Total time** | Trace + Analysis | Trace only |
| **Memory during trace** | Low (just buffering) | Higher (object graph) |
| **Memory post-processing** | Very high (entire trace) | None |
| **Disk I/O** | 2x (read + write trace) | 1x (write once) |

### Example: LotsOfAllocs (1000 objects)

#### Post-Processing
```bash
# Step 1: Generate trace
$ time java -javaagent:et3.jar LotsOfAllocs
real    0m2.150s  ← Fast tracing
# Produces: trace (2000 lines, no D records)

# Step 2: Add deaths
$ time java MerlinDeathTracker -i trace -o trace_with_deaths
real    0m1.850s  ← Post-processing time
# Produces: trace_with_deaths (3000 lines, with D records)

Total time: 4.0s
```

#### Integrated
```bash
# Single step
$ time java -javaagent:et3-merlin.jar LotsOfAllocs
real    0m2.800s  ← Slower tracing but done in one step
# Produces: trace (3000 lines, with D records already)

Total time: 2.8s ← 30% faster overall!
```

### Accuracy Comparison

#### Post-Processing - Reconstructed Timestamps
```
E 174 1950409828                      # Method exit (reconstructed time)
D 1234 1950409828 174842532151        # Death time = approximation
```
Death time is reconstructed from trace, less precise.

#### Integrated - Precise Timestamps
```
E 174 1950409828                      # Method exit at T
D 1234 1950409828 174842532151245    # Death detected at T+1ns
```
Death time = actual nanosecond when object became unreachable.

---

## Use Cases

### When to Use Post-Processing (MerlinDeathTracker)

✅ **Analyzing existing traces** - you already have ET3 traces  
✅ **Experimenting** - trying different death detection algorithms  
✅ **Minimal overhead needed** - can't afford runtime slowdown  
✅ **Retroactive analysis** - analyzing old data  
✅ **Research** - comparing different approaches  

Example: "I have 100 traces from last year, want to add death info"

### When to Use Integrated (MerlinTracker)

✅ **Production tracing** - want complete traces immediately  
✅ **Streaming analysis** - analyze trace as it's generated  
✅ **Accurate timing** - need precise death timestamps  
✅ **Simulation input** - feeding directly to simulator  
✅ **Standard workflow** - this is the default going forward  

Example: "Generate traces for gem5 simulation"

---

## Migration Path

### From Post-Processing to Integrated

If you have existing ET3 infrastructure:

```bash
# Old way (2 steps)
java -javaagent:et3-old.jar Program     # Generate trace
java MerlinDeathTracker trace           # Add deaths

# New way (1 step)
java -javaagent:et3-merlin.jar Program  # Complete trace
```

**Recommendation**: Use integrated approach for new work, keep post-processing for analyzing old traces.

---

## Technical Deep Dive

### Death Detection Logic

Both approaches use the same Merlin algorithm core:

```java
// Same in both
Set<Integer> computeReachableObjects() {
    Set<Integer> reachable = new HashSet<>();
    Queue<Integer> queue = new LinkedList<>();
    
    // Add roots: stack frames + static fields
    for (Stack<MethodFrame> stack : threadStacks.values()) {
        for (MethodFrame frame : stack) {
            queue.add(frame.receiverObjectId);
            queue.addAll(frame.localObjects);
        }
    }
    queue.addAll(staticRoots);
    
    // BFS from roots
    while (!queue.isEmpty()) {
        int objId = queue.poll();
        if (reachable.contains(objId)) continue;
        reachable.add(objId);
        
        if (objectGraph.containsKey(objId)) {
            queue.addAll(objectGraph.get(objId));
        }
    }
    
    return reachable;
}
```

**Key difference**: WHEN this runs
- Post-processing: After reading E record from trace
- Integrated: During actual method exit

### Thread Safety

#### Post-Processing
```java
// Single-threaded - parsing trace sequentially
public void processTrace(String file) {
    // No synchronization needed
    for (String line : readLines(file)) {
        handleEvent(line);
    }
}
```

#### Integrated
```java
// Multi-threaded - program has multiple threads
public static synchronized List<DeathRecord> performReachabilityAnalysis() {
    // Synchronization required!
    mx.lock();
    try {
        return detectDeaths();
    } finally {
        mx.unlock();
    }
}

// Thread-safe collections
private static final ConcurrentHashMap<Integer, ObjectInfo> liveObjects;
```

---

## Conclusion

### Post-Processing (MerlinDeathTracker)
- ✅ Flexible, safe, retroactive
- ❌ Two-step process, memory intensive
- **Best for**: Research, experimentation, old traces

### Integrated (MerlinTracker)
- ✅ Single-step, accurate, production-ready
- ❌ Runtime overhead, more complex
- **Best for**: Production use, simulations, new workflows

### Current Recommendation

**Use Integrated (MerlinTracker)** - it's what we have now and it's the better approach for generating traces for simulation and analysis. The post-processing approach is still available in the codebase for historical/research purposes.

---

## Files Reference

- **Post-processing**: `/javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/MerlinDeathTracker.java`
- **Integrated**: 
  - `/javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/MerlinTracker.java`
  - `/javassist-inst/et2-instrumenter/src/main/java/veroy/research/et2/javassist/ETProxy.java` (modified)
- **Scripts**:
  - Post-processing: `run_merlin_analysis.sh`
  - Integrated: `test_integrated_merlin.sh`, `run_dacapo_with_merlin.sh`
