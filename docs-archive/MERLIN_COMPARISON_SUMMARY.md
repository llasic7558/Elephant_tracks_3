# Merlin Algorithm: Quick Comparison

## Two Implementations

### 1. MerlinDeathTracker (Post-Processing)
```
┌──────────┐     ┌───────────┐     ┌─────────────┐
│   Run    │────→│   Read    │────→│   Write     │
│  ET3     │     │   Trace   │     │  Trace+D    │
│          │     │  + Merlin │     │             │
└──────────┘     └───────────┘     └─────────────┘
   2 seconds        2 seconds           Done
   
Total: 4 seconds, 2-step process
```

### 2. MerlinTracker (Integrated)
```
┌────────────────────────────────┐
│   Run ET3 with Merlin          │
│   (deaths detected live)       │
└────────────────────────────────┘
   3 seconds, 1-step process
   
Total: 3 seconds, complete trace ready
```

## Quick Decision Matrix

| Need | Use |
|------|-----|
| Analyze existing traces | Post-Processing |
| Generate new traces | **Integrated** ✓ |
| Minimal runtime overhead | Post-Processing |
| Accurate death timestamps | **Integrated** ✓ |
| Feed to simulator | **Integrated** ✓ |
| Experiment with algorithms | Post-Processing |
| Production workflow | **Integrated** ✓ |

## Key Differences

| Feature | Post-Processing | Integrated |
|---------|----------------|------------|
| **Steps** | 2 (trace + analyze) | 1 (trace with deaths) |
| **Runtime overhead** | 0% | 20-50% |
| **Total time** | Slower (trace + parse) | Faster overall |
| **Memory** | High (full trace) | Medium (live heap) |
| **Timestamp precision** | Approximate | Nanosecond |
| **Sorting needed** | Yes | No |
| **Output** | New trace file | Complete trace file |

## Example Output

### Post-Processing
```bash
# First run: no D records
$ java -javaagent:et3.jar Program
$ cat trace
N 1234 ...
M 100 ...
E 100 ...

# Second run: add D records  
$ java MerlinDeathTracker trace
$ cat trace_with_deaths
N 1234 ...
M 100 ...
E 100 ...
D 1234 ...  ← Added by post-processing
```

### Integrated
```bash
# Single run: D records included
$ java -javaagent:et3-merlin.jar Program
$ cat trace
N 1234 ...
M 100 ...
E 100 ...
D 1234 ...  ← Written during execution
```

## Current Status

✅ **Integrated approach is default** - ready to use  
✅ **Post-processing still available** - for special cases  
✅ **Both use same Merlin algorithm** - same death detection logic  

## Recommendation

**Use Integrated (MerlinTracker)** unless you specifically need to analyze old traces or experiment with algorithms.

Files:
- Integrated: `MerlinTracker.java` + modified `ETProxy.java`
- Post-processing: `MerlinDeathTracker.java`
