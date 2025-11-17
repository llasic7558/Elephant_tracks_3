# Oracle Builder

## Overview

The `build_oracle.py` script constructs an "oracle" event stream from Elephant Tracks traces with Merlin death records. The oracle provides ground-truth allocation and deallocation events for comparing GC simulation policies.

## Purpose

For each object in the trace, the oracle captures:
- **Allocation time** (event index / logical time)
- **Death time** (when Merlin detected unreachability)
- **Object size** (in bytes)
- **Allocation site** (source code location)
- **Thread ID**

The output is a chronological sequence of `alloc` and `free` events that can be used as ground truth for memory simulation experiments.

## Usage

### Basic Usage

```bash
python3 build_oracle.py <input_trace_file>
```

Outputs the oracle event stream to stdout.

### Save to File

```bash
python3 build_oracle.py trace_with_offline_deaths --output oracle.txt
```

### Export as CSV

```bash
python3 build_oracle.py trace_with_offline_deaths --csv oracle_events.csv
```

CSV format includes:
- `timestamp` - Event index (logical time)
- `event_type` - "alloc" or "free"
- `object_id` - Unique object identifier
- `size` - Object size in bytes
- `site_id` - Allocation site identifier
- `thread_id` - Thread that allocated the object
- `type_id` - Object type identifier

### Show Statistics

```bash
python3 build_oracle.py trace_with_offline_deaths --stats
```

Displays:
- Total events, allocations, frees
- Live objects (not freed)
- Total/freed/live bytes
- Allocation site activity

### Verbose Mode

```bash
python3 build_oracle.py trace_with_offline_deaths --verbose
```

Shows parsing progress and warnings.

## Output Format

### Text Format

```
t5: alloc(id=212628335, size=24, site=62, thread=1950409828)
t15: alloc(id=1101288798, size=40, site=135, thread=1950409828)
t108: free(id=824009085, size=24, site=151, thread=1950409828)
t109: free(id=212628335, size=24, site=62, thread=1950409828)
```

- `t<N>`: Event index (logical timestamp)
- `alloc`/`free`: Event type
- `id`: Object identifier
- `size`: Size in bytes
- `site`: Allocation site ID
- `thread`: Thread ID

### CSV Format

```csv
timestamp,event_type,object_id,size,site_id,thread_id,type_id
5,alloc,212628335,24,62,1950409828,3
108,free,824009085,24,151,1950409828,32
```

## Use Cases

### 1. Memory Allocator Comparison

Feed the oracle to gem5 with different allocator policies:
```bash
# Generate oracle
python3 build_oracle.py trace.txt --csv oracle.csv

# Run gem5 simulations
gem5 --oracle oracle.csv --allocator first-fit
gem5 --oracle oracle.csv --allocator best-fit
```

### 2. Lifetime Analysis

Analyze object lifetimes:
```python
import pandas as pd

df = pd.read_csv('oracle_events.csv')
allocs = df[df['event_type'] == 'alloc'].set_index('object_id')
frees = df[df['event_type'] == 'free'].set_index('object_id')

lifetimes = frees['timestamp'] - allocs['timestamp']
print(f"Average lifetime: {lifetimes.mean():.2f} events")
```

### 3. Heap Size Simulation

Track maximum heap usage:
```python
import pandas as pd

df = pd.read_csv('oracle_events.csv')
df = df.sort_values('timestamp')

heap_size = 0
max_heap = 0

for _, row in df.iterrows():
    if row['event_type'] == 'alloc':
        heap_size += row['size']
    else:
        heap_size -= row['size']
    max_heap = max(max_heap, heap_size)

print(f"Maximum heap size: {max_heap} bytes")
```

## Example

```bash
$ cd gem5-simulation/scripts
$ python3 build_oracle.py ../../test_traces_offline/SimpleTrace/trace_with_offline_deaths --stats

# Oracle Event Stream
# Format: t<event_index>: <event_type>(id=<obj_id>, size=<bytes>, site=<site_id>, thread=<thread_id>)
# Total events: 32
# Allocations: 16
# Frees: 16

t5: alloc(id=212628335, size=24, site=62, thread=1950409828)
...

=== Oracle Statistics ===
Total events: 32
Allocations: 16
Frees: 16
Live objects (not freed): 0
Total bytes allocated: 440
Total bytes freed: 440
Live bytes: 0

Allocation sites: 7
Most active sites:
  Site 151: 9 allocations
  Site 135: 2 allocations
```

## Limitations

- **Death records required**: The input trace must include Merlin death records (D records). Run traces without deaths through `MerlinDeathTracker.java` first.
- **Logical time**: Timestamps are event indices, not wall-clock time. They represent program order.
- **No GC timing**: Death records indicate when objects became unreachable, not when GC actually collected them.

## See Also

- [TRACE_FORMAT.md](TRACE_FORMAT.md) - ET trace format specification
- [MERLIN_README.md](../../MERLIN_README.md) - Merlin death tracking
- [TraceReplayer](../trace_replayer/) - gem5 component that uses oracle data
