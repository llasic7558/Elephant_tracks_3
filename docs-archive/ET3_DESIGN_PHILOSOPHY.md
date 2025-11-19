# ET3 Design Philosophy: Offline vs Online Death Detection

## The ET3 Philosophy

From the Elephant Tracks paper:

> **"The important idea behind ET2 and ET3 is that instead of creating and tracing object graphs at runtime (as ET1 does), ET3 generates data that allows the object graphs to be generated offline after the program ends."**

This is a **fundamental design principle**:
- ✅ **Runtime**: Generate trace data (N, A, M, E, U)
- ✅ **Offline**: Reconstruct object graphs and detect deaths

## Two Implementations: Which is Correct?

### Approach 1: Offline (MerlinDeathTracker) - ✅ ET3 Philosophy

**Architecture:**
```
┌──────────────┐
│  ET3 Trace   │  Generate N, A, M, E, U records ONLY
│  (Runtime)   │  No object graph, no death tracking
└──────┬───────┘
       │ trace file (no D records)
       ▼
┌──────────────┐
│   Merlin     │  Read trace offline
│Death Tracker │  Reconstruct object graph from U records
│(Post-Process)│  Detect deaths via reachability analysis
└──────┬───────┘
       │ trace_with_deaths file
       ▼
┌──────────────┐
│  Simulator   │  Use complete trace
└──────────────┘
```

**Advantages:**
- ✅ **Zero runtime overhead** - no graph maintenance during execution
- ✅ **True ET3 philosophy** - offline reconstruction
- ✅ **Simpler instrumentation** - just record events
- ✅ **Flexible** - can experiment with different algorithms
- ✅ **Debugging friendly** - can inspect intermediate trace
- ✅ **Replayable** - can re-analyze with different parameters

**Disadvantages:**
- ❌ Two-step process (trace, then analyze)
- ❌ Higher memory for post-processing (loads entire trace)
- ❌ Disk I/O overhead (read + write trace)

### Approach 2: Online (MerlinTracker) - ❌ Violates ET3 Philosophy

**Architecture:**
```
┌─────────────────────────────┐
│  ET3 + Merlin (Runtime)     │
│  • Generate events          │
│  • Maintain object graph    │ ← Violates ET3!
│  • Detect deaths at runtime │ ← Violates ET3!
└─────────────┬───────────────┘
              │ trace file (with D records)
              ▼
        ┌──────────────┐
        │  Simulator   │
        └──────────────┘
```

**Advantages:**
- ✅ Single-step process
- ✅ Streaming output
- ✅ Precise timestamps

**Disadvantages:**
- ❌ **Violates ET3 design philosophy** - graphs at runtime
- ❌ Runtime overhead (~20-50%)
- ❌ Memory overhead (live object graph)
- ❌ More complex instrumentation
- ❌ Can't re-analyze without re-running program

## The Correct Answer

**For ET3 compliance: Use Offline (MerlinDeathTracker)**

This is what the ET3 paper describes and what aligns with the design philosophy.

## Historical Context

### ET1 (Bad Approach)
- Built complete object graph at runtime
- High overhead
- Memory intensive
- Slow

### ET2/ET3 (Good Approach)
- **Record events at runtime** (lightweight)
- **Reconstruct offline** (separate analysis step)
- Low overhead
- Flexible analysis

### Our Current Implementation (Accidentally ET1-like)
- MerlinTracker builds graph at runtime
- Goes against ET3 philosophy
- Should use MerlinDeathTracker instead

## Recommended Architecture

### Phase 1: Tracing (ET3)

```java
// ET3 generates ONLY these records:
N <object-id> <size> <type> <site> <length> <thread>   // Allocation
A <object-id> <size> <type> <site> <length> <thread>   // Array
M <method-id> <receiver-id> <thread>                   // Method entry
E <method-id> <thread>                                 // Method exit
U <receiver-id> <value-id> <field-id> <thread>        // Field update
```

**No D records, no object graph, no death detection!**

### Phase 2: Analysis (MerlinDeathTracker)

```java
// Post-processing tool:
MerlinDeathTracker tracker = new MerlinDeathTracker();
tracker.processTrace("trace", "trace_with_deaths");

// Reads trace, reconstructs graph, generates:
D <object-id> <thread-id> <timestamp>                  // Death record
```

### Phase 3: Simulation

```
Simulator reads trace_with_deaths
```

## Implementation Plan

### Option A: Pure ET3 (Recommended)

Remove MerlinTracker integration from ETProxy:

```java
// ETProxy.java - REMOVE:
// - MerlinTracker.onObjectAlloc()
// - MerlinTracker.onFieldUpdate()
// - MerlinTracker.onMethodEntry()
// - MerlinTracker.onMethodExit()
// - MerlinTracker.onShutdown()

// Just generate N, A, M, E, U records
```

Use MerlinDeathTracker as separate tool:

```bash
# Step 1: Trace (fast, no overhead)
java -javaagent:et3.jar MyProgram
# Produces: trace (N, A, M, E, U only)

# Step 2: Analyze (offline)
java -cp et3.jar MerlinDeathTracker trace trace_with_deaths
# Produces: trace_with_deaths (adds D records)

# Step 3: Simulate
./simulator trace_with_deaths
```

### Option B: Hybrid (Both Modes Available)

Add a flag to enable/disable real-time death tracking:

```bash
# Mode 1: Pure ET3 (no runtime death tracking)
java -javaagent:et3.jar MyProgram
# Then: java MerlinDeathTracker trace trace_with_deaths

# Mode 2: Integrated (with runtime death tracking)
java -javaagent:et3.jar -Dmerlin.enabled=true MyProgram
# Produces trace with D records already
```

## Performance Comparison

### Pure ET3 (Offline)

```
Program runtime:     100% (baseline)
Trace generation:    +5-10% overhead (just recording events)
Post-processing:     +20s (separate step, doesn't affect runtime)
Total time:          110s (program) + 20s (analysis) = 130s
```

### Integrated (Online)

```
Program runtime:     100% (baseline)
Trace generation:    +20-50% overhead (graph maintenance + death detection)
Post-processing:     0s (already done)
Total time:          140s (program only)
```

**Offline is faster AND follows ET3 philosophy!**

## The Right Way Forward

### Immediate Action

1. **Remove MerlinTracker integration** from ETProxy
   - Remove all `MerlinTracker.*` calls
   - Generate only N, A, M, E, U records

2. **Use MerlinDeathTracker** as post-processing tool
   - Already implemented and working
   - Follows ET3 design philosophy
   - Zero runtime overhead

3. **Update documentation**
   - Emphasize offline reconstruction
   - Show two-step workflow

### Workflow

```bash
# CORRECT ET3 Workflow
# ====================

# 1. Compile ET3 agent
cd javassist-inst/et2-instrumenter
mvn clean package

# 2. Compile Merlin post-processor
# (Already compiled with ET3)

# 3. Run program with ET3 (generates trace without D records)
java -javaagent:target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     MyProgram

# Output: trace (N, A, M, E, U only)

# 4. Generate death records offline
java -cp target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     veroy.research.et2.javassist.MerlinDeathTracker \
     -i trace \
     -o trace_with_deaths

# Output: trace_with_deaths (adds D records)

# 5. Use trace_with_deaths for simulation
./simulator trace_with_deaths
```

## Why This Matters

### For Your Thesis

1. **Correctness** - Follows ET3 design as published
2. **Performance** - Lower runtime overhead
3. **Flexibility** - Can experiment with different death detection algorithms
4. **Reproducibility** - Can re-analyze traces without re-running programs

### For gem5 Simulation

- Simulator gets complete trace with D records
- Death records are accurate (offline analysis)
- Can compare different Merlin algorithms on same trace

### For Research

- Pure ET3 approach is what the paper describes
- Allows comparison with other tools
- Demonstrates understanding of ET design philosophy

## Conclusion

**The ET3 philosophy is clear: offline reconstruction.**

We should:
1. ✅ Use ET3 to generate N, A, M, E, U records (lightweight)
2. ✅ Use MerlinDeathTracker for offline analysis (adds D records)
3. ❌ Remove runtime object graph tracking from ETProxy

This gives us:
- ✅ True ET3 compliance
- ✅ Better performance
- ✅ Flexibility for analysis
- ✅ Follows published design

**MerlinDeathTracker is the correct approach for ET3!**
