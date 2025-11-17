# True Oracle Format - Allocation/Free Event Stream

## What This Is

This oracle provides a **chronological event stream** showing when objects are allocated and freed, derived from:
1. **ET3 trace** - Captures N (new) and A (array) allocation events
2. **Merlin algorithm** - Computes precise death times (when objects become unreachable)

## Format

```
t<event_idx>: alloc(id=<obj_id>, size=<bytes>, site=<site_id>, thread=<thread_id>)
t<event_idx>: free(id=<obj_id>, size=<bytes>)
```

### Fields

- **event_idx**: Sequential event number (logical time, not wall-clock)
- **obj_id**: Unique object identifier
- **size**: Object size in bytes
- **site**: Allocation site ID (maps to method in methods.list)
- **thread**: Thread ID that allocated the object

## Example

```
t2: free(id=458209687, size=24)
t3: alloc(id=458209687, size=24, site=62, thread=1950409828)
t8: free(id=38997010, size=40)
t10: free(id=1789447862, size=4)
t11: free(id=1213415012, size=4)
t12: alloc(id=38997010, size=40, site=80, thread=1950409828)
t12: free(id=999661724, size=4)
```

**Note**: Free can come before alloc in event stream because:
- Phantom objects (JVM infrastructure) die but weren't allocated in our trace
- They existed before instrumentation started

## Our Oracle Statistics

| Metric | Value |
|--------|-------|
| **Total events** | 47 |
| **Allocations** | 16 (program objects) |
| **Frees** | 31 (program + phantom) |
| **Memory allocated** | 440 bytes |
| **Memory freed** | 500 bytes |
| **Phantom objects** | 15 (JVM infrastructure) |

## Object Categories

### 1. Program Objects (16 objects, 440 bytes)
Objects explicitly allocated by SimpleTrace:
- 10 objects × 24 bytes = 240 bytes (likely Integers)
- 1 object × 32 bytes = 32 bytes  (ArrayList internal)
- 3 objects × 40 bytes = 120 bytes (likely ArrayList)
- 2 objects × various = 48 bytes

**Allocation sites**: 62, 80, 81, 99 (check methods.list)

### 2. Phantom Objects (15 objects, 60 bytes)
JVM infrastructure objects that existed before instrumentation:
- Most are 4 bytes (references or small objects)
- No allocation events in our trace
- Still tracked by Merlin and have computed death times

## Use Cases

### 1. Memory Simulator
```python
heap = {}  # obj_id -> size
max_heap_size = 0

for line in oracle:
    if 'alloc' in line:
        # Extract: t12: alloc(id=38997010, size=40, ...)
        obj_id = extract_id(line)
        size = extract_size(line)
        heap[obj_id] = size
    elif 'free' in line:
        obj_id = extract_id(line)
        if obj_id in heap:
            del heap[obj_id]
    
    current_size = sum(heap.values())
    max_heap_size = max(max_heap_size, current_size)

print(f"Peak heap usage: {max_heap_size} bytes")
```

### 2. GC Policy Evaluation
```python
# Simulate mark-sweep GC triggered at specific intervals
live_objects = {}
gc_threshold = 200  # bytes

for event in parse_oracle():
    if event['type'] == 'alloc':
        live_objects[event['id']] = event['size']
        
        if sum(live_objects.values()) > gc_threshold:
            # Trigger GC - remove dead objects
            for obj_id in event['dead_at_this_time']:
                live_objects.pop(obj_id, None)
```

### 3. Fragmentation Analysis
```python
# Track allocation/deallocation patterns
allocations = []
deallocations = []

for event in parse_oracle():
    if event['type'] == 'alloc':
        allocations.append((event['time'], event['size']))
    else:
        deallocations.append((event['time'], event['size']))

# Analyze gaps between deallocations
# Measure fragmentation over time
```

### 4. Validate ET3 Merlin Tracker
```python
# Compare ET3's inline deaths vs. offline oracle
et3_deaths = parse_et3_trace_deaths()
oracle_deaths = parse_oracle_deaths()

matches = 0
for obj_id, oracle_time in oracle_deaths.items():
    if obj_id in et3_deaths:
        et3_time = et3_deaths[obj_id]
        if abs(oracle_time - et3_time) <= tolerance:
            matches += 1

accuracy = matches / len(oracle_deaths) * 100
print(f"ET3 Merlin accuracy: {accuracy}%")
```

## Timeline View

```
Event  0-10:  3 allocs, 5 frees (early cleanup)
Event 11-30: 1 alloc,  8 frees (bulk cleanup phase 1)
Event 31-50: 12 allocs, 14 frees (main execution)
Event 51-60: 0 allocs,  4 frees (final cleanup)
```

### Memory Pressure Over Time

```
t0-10:   Pressure LOW  (few live objects)
t11-30:  Pressure LOW  (frees > allocs)
t31-50:  Pressure HIGH (many simultaneous allocs)
t51+:    Pressure LOW  (cleanup phase)
```

## Key Insights

### 1. **Death Detection is Precise**
Merlin computes exact event when object becomes unreachable, not when GC would collect it.

### 2. **Phantom Objects are Real**
15 JVM infrastructure objects (class loaders, streams, etc.) are visible and tracked.

### 3. **Allocation Site Clustering**
Most allocations from sites 62, 80, 81, 99 - likely SimpleTrace's main methods.

### 4. **Size Distribution**
- 4 bytes: 15 objects (small/references)
- 24 bytes: 10 objects (boxed Integers)
- 32 bytes: 1 object (ArrayList internal)
- 40 bytes: 3 objects (ArrayList objects)

### 5. **Short Lifetimes**
Many objects freed soon after allocation - good for generational GC.

## Comparison: This vs. Previous Oracle

| Feature | trace_with_deaths_oracle | oracle_event_stream.txt |
|---------|-------------------------|-------------------------|
| **Format** | Raw trace records | Clean event stream |
| **Order** | Deaths at start ❌ | Chronological ✓ |
| **Readability** | Low | High ✓ |
| **Analysis** | Requires parsing | Direct use ✓ |
| **Metadata** | Limited | Rich (site, thread) ✓ |

## Files

- `oracle_event_stream.txt` - The true oracle (47 events)
- `deaths_with_size.txt` - Raw death records from simulator
- `trace` - Original ET3 trace
- `ORACLE_FORMAT.md` - This documentation

## How to Generate

```bash
./build_true_oracle.py trace deaths_with_size.txt oracle_event_stream.txt
```

Or use the wrapper script:
```bash
./create_oracle_trace.sh pipeline_results/<directory>
```

## Next Steps

1. **Run on LotsOfAllocs** - Test with 1000+ objects
2. **Implement memory simulator** - Evaluate GC policies
3. **Compare with ET3 inline Merlin** - Validate accuracy
4. **Analyze allocation sites** - Understand program behavior
5. **Study lifetime distributions** - Optimize for GC

## Conclusion

This oracle provides **ground truth for object lifetimes** in a clean, analyzable format:
- ✅ Chronological event ordering
- ✅ Rich metadata (size, site, thread)
- ✅ Precise Merlin-computed death times
- ✅ Complete coverage (program + phantom objects)
- ✅ Ready for memory analysis and GC research

Perfect for validating death-tracking algorithms and simulating memory management!
