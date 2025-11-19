# Oracle Construction for gem5 Simulation

## Overview

Oracle files provide a **deterministic event stream** for gem5 memory allocator simulation. They contain allocation and death events with logical timestamps, allowing gem5 to replay the exact memory behavior of a Java program.

## Purpose

gem5 memory allocator simulator needs:
- When to allocate memory (time, size, object ID)
- When to free memory (time, object ID)
- Deterministic replay (same events every time)

ET3 traces → Oracle builder → Oracle files → gem5 simulation

## Oracle File Formats

### Human-Readable (oracle.txt)

```
# Oracle for SimpleTrace
# Generated from trace with 16 allocations, 16 deaths

Time   Event  ObjectID    Size
-----------------------------------
1      ALLOC  1001        32
1      ALLOC  1002        48
2      ALLOC  1003        24
4      DEATH  1001        32
6      DEATH  1002        48
8      DEATH  1003        24
```

### Machine-Readable (oracle.csv)

```csv
time,event_type,object_id,size
1,alloc,1001,32
1,alloc,1002,48
2,alloc,1003,24
4,death,1001,32
6,death,1002,48
8,death,1003,24
```

## Construction Process

### Input: ET3 Trace

```
N 1001 32 100 200 0 1       # Allocation at time 1, size 32
N 1002 48 101 200 0 1       # Allocation at time 1, size 48
M 200 1001 2                # Method entry at time 2
N 1003 24 100 200 0 2       # Allocation at time 2, size 24
E 200 4                     # Method exit at time 4
D 1001 5001 4               # Death at time 4
D 1002 5001 6               # Death at time 6
D 1003 5001 8               # Death at time 8
```

### Processing Steps

1. **Extract allocations** (N/A records)
   ```python
   if line.startswith('N') or line.startswith('A'):
       parts = line.split()
       obj_id = int(parts[1])
       size = int(parts[2])
       time = int(parts[-1])  # Last field is timestamp
       
       oracle.append({
           'time': time,
           'event': 'alloc',
           'object_id': obj_id,
           'size': size
       })
   ```

2. **Extract deaths** (D records)
   ```python
   if line.startswith('D'):
       parts = line.split()
       obj_id = int(parts[1])
       time = int(parts[-1])  # Last field is timestamp
       
       # Look up size from allocation
       size = allocation_sizes[obj_id]
       
       oracle.append({
           'time': time,
           'event': 'death',
           'object_id': obj_id,
           'size': size
       })
   ```

3. **Sort by time**
   ```python
   oracle.sort(key=lambda x: x['time'])
   ```

4. **Write outputs**
   ```python
   # CSV for gem5
   with open('oracle.csv', 'w') as f:
       f.write('time,event_type,object_id,size\n')
       for event in oracle:
           f.write(f"{event['time']},{event['event']},{event['object_id']},{event['size']}\n")
   
   # Human-readable
   with open('oracle.txt', 'w') as f:
       f.write('Time   Event  ObjectID    Size\n')
       for event in oracle:
           f.write(f"{event['time']:6d} {event['event']:6s} {event['object_id']:10d} {event['size']:6d}\n")
   ```

### Output: Oracle Files

See formats above.

## Builder Script

### build_oracle.py

```python
#!/usr/bin/env python3
"""Build oracle files from ET3 traces for gem5 simulation."""

import sys
import csv

def build_oracle(trace_file, oracle_txt, oracle_csv):
    allocations = {}  # object_id → size
    events = []
    
    with open(trace_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            
            record_type = parts[0]
            
            if record_type == 'N' or record_type == 'A':
                # N/A <obj-id> <size> <type> <site> <length> <thread> <time>
                obj_id = int(parts[1])
                size = int(parts[2])
                time = int(parts[-1])
                
                allocations[obj_id] = size
                events.append({
                    'time': time,
                    'event': 'alloc',
                    'object_id': obj_id,
                    'size': size
                })
            
            elif record_type == 'D':
                # D <obj-id> <thread> <time>
                obj_id = int(parts[1])
                time = int(parts[-1])
                
                if obj_id in allocations:
                    size = allocations[obj_id]
                    events.append({
                        'time': time,
                        'event': 'death',
                        'object_id': obj_id,
                        'size': size
                    })
    
    # Sort by time
    events.sort(key=lambda x: x['time'])
    
    # Write human-readable
    with open(oracle_txt, 'w') as f:
        f.write('Time   Event  ObjectID    Size\n')
        f.write('-' * 40 + '\n')
        for e in events:
            f.write(f"{e['time']:6d} {e['event']:6s} {e['object_id']:10d} {e['size']:6d}\n")
    
    # Write CSV
    with open(oracle_csv, 'w') as f:
        writer = csv.DictWriter(f, fieldnames=['time', 'event_type', 'object_id', 'size'])
        writer.writeheader()
        for e in events:
            writer.writerow({
                'time': e['time'],
                'event_type': e['event'],
                'object_id': e['object_id'],
                'size': e['size']
            })
    
    return len(events)

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print('Usage: build_oracle.py <trace_file> <oracle.txt> <oracle.csv>')
        sys.exit(1)
    
    count = build_oracle(sys.argv[1], sys.argv[2], sys.argv[3])
    print(f'Generated oracle with {count} events')
```

## Usage in Pipeline

### Automated Pipeline

```bash
./run_all_tests_pipeline.sh
```

For each test:
1. Generate trace (with deaths)
2. Reorder deaths to temporal positions
3. Build oracle from reordered trace
4. Validate no witness-after-death violations

Results in `pipeline_results/<test>/`:
- `oracle.txt` - Human-readable
- `oracle.csv` - For gem5

### Manual Oracle Construction

```bash
# From trace with deaths
python3 build_oracle.py \
    trace_with_deaths \
    oracle.txt \
    oracle.csv

# From reordered trace (better)
python3 build_oracle.py \
    trace_reordered \
    oracle.txt \
    oracle.csv
```

## Oracle Properties

### Completeness

Every allocation has a corresponding death:

```python
allocs = {e['object_id'] for e in events if e['event'] == 'alloc'}
deaths = {e['object_id'] for e in events if e['event'] == 'death'}

assert allocs == deaths, "All allocated objects must die"
```

### Temporal Ordering

Events are sorted by logical time:

```python
times = [e['time'] for e in events]
assert times == sorted(times), "Events must be in temporal order"
```

### No Use-After-Death

Deaths come after last access (witness):

```python
for obj_id in all_objects:
    last_witness = max_witness_time(obj_id)
    death_time = death_time(obj_id)
    assert death_time > last_witness, "Death must be after last access"
```

## gem5 Integration

### Reading Oracle in gem5

```cpp
// gem5 memory allocator simulator
class OracleReader {
    struct Event {
        uint64_t time;
        enum { ALLOC, DEATH } type;
        uint64_t object_id;
        uint64_t size;
    };
    
    std::vector<Event> events;
    
    void loadOracle(const char* csv_file) {
        // Parse CSV
        // Store events sorted by time
    }
    
    void simulate() {
        for (const Event& e : events) {
            if (e.type == ALLOC) {
                allocator.allocate(e.object_id, e.size);
            } else {
                allocator.free(e.object_id);
            }
            
            // Advance simulation time
            tick(e.time);
        }
    }
};
```

### Allocator Comparison

gem5 can compare different allocators using the same oracle:

```cpp
// Test different allocators with same workload
oracle.loadOracle("SimpleTrace_oracle.csv");

// Test allocator 1
FirstFitAllocator alloc1;
oracle.simulate(alloc1);
stats1 = alloc1.getStats();

// Test allocator 2
BestFitAllocator alloc2;
oracle.simulate(alloc2);
stats2 = alloc2.getStats();

// Compare
compare(stats1, stats2);
```

## Validation

### Statistics Check

```bash
# Count allocations in trace
ALLOCS=$(grep -c "^[NA]" trace)

# Count deaths in trace
DEATHS=$(grep -c "^D" trace)

# Count alloc events in oracle
ORACLE_ALLOCS=$(grep -c ",alloc," oracle.csv)

# Count death events in oracle
ORACLE_DEATHS=$(grep -c ",death," oracle.csv)

# Verify
[ $ALLOCS -eq $ORACLE_ALLOCS ] && echo "✅ Allocations match"
[ $DEATHS -eq $ORACLE_DEATHS ] && echo "✅ Deaths match"
```

### Temporal Ordering Check

```python
def verify_temporal_order(oracle_csv):
    with open(oracle_csv, 'r') as f:
        reader = csv.DictReader(f)
        prev_time = -1
        
        for row in reader:
            time = int(row['time'])
            assert time >= prev_time, f"Time went backwards: {prev_time} → {time}"
            prev_time = time
    
    print("✅ Temporal ordering valid")
```

### Completeness Check

```python
def verify_completeness(oracle_csv):
    allocs = set()
    deaths = set()
    
    with open(oracle_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            obj_id = int(row['object_id'])
            if row['event_type'] == 'alloc':
                allocs.add(obj_id)
            else:
                deaths.add(obj_id)
    
    assert allocs == deaths, "All objects must die"
    print(f"✅ Completeness valid ({len(allocs)} objects)")
```

## Test Results

### SimpleTrace Oracle

```
Allocations: 16
Deaths: 16
Oracle events: 32 (16 allocs + 16 deaths)
Time range: 1 to 242
```

### LotsOfAllocs Oracle

```
Allocations: 1005
Deaths: 1005
Oracle events: 2010 (1005 allocs + 1005 deaths)
Time range: 1 to 3500
```

## Next Steps

### gem5 Simulation

1. Load oracle CSV in gem5
2. Replay allocation/death events
3. Measure allocator performance:
   - Fragmentation
   - Allocation time
   - Memory overhead
4. Compare allocators (first-fit, best-fit, buddy, slab, etc.)

### Analysis

Oracle files enable:
- Memory footprint analysis
- Object lifetime distribution
- Allocation pattern study
- Allocator stress testing

## References

- See [Witness Fix](witness-fix.md) for death ordering correctness
- See [Implementation Guide](../implementation/merlin.md) for death detection
- See gem5 documentation for simulator integration

## Related Documentation

- `ORACLE_CONSTRUCTION.md` (archived) - Original implementation notes
- `gem5-simulation/docs/ORACLE_BUILDER.md` - gem5-specific details
- `reorder_deaths.py` - Temporal reordering script
