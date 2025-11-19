# ET3 Trace Format Specification

## Overview

ET3 produces line-based trace files where each line represents an event. All events include logical timestamps for deterministic replay.

## Record Types

### Object Allocation (N)

```
N <object-id> <size> <type-id> <site-id> 0 <timestamp>
```

**Fields**:
- `object-id`: Identity hash code of object
- `size`: Size in bytes
- `type-id`: Class type identifier
- `site-id`: Allocation site (method ID)
- `0`: Placeholder (not array)
- `timestamp`: Logical time of allocation

**Example**:
```
N 1288354730 32 1437783372 1090623040 0 5
```

Object 1288354730 of size 32 bytes allocated at time 5.

### Array Allocation (A)

```
A <object-id> <size> <type-id> <site-id> <length> <timestamp>
```

**Fields**:
- `object-id`: Identity hash code of array
- `size`: Total size in bytes
- `type-id`: Array type identifier
- `site-id`: Allocation site (method ID)
- `length`: Array length
- `timestamp`: Logical time of allocation

**Example**:
```
A 2117255219 48 1437783372 1090623040 10 7
```

Array 2117255219 of size 48 bytes with length 10 allocated at time 7.

### Method Entry (M)

```
M <method-id> <receiver-id> <timestamp>
```

**Fields**:
- `method-id`: Method identifier
- `receiver-id`: Object ID of `this` (0 for static methods)
- `timestamp`: Logical time (clock ticks on entry)

**Example**:
```
M 1090623040 1288354730 10
```

Method 1090623040 called on receiver 1288354730 at time 10.

### Method Exit (E)

```
E <method-id> <timestamp>
```

**Fields**:
- `method-id`: Method identifier (same as corresponding M record)
- `timestamp`: Logical time (clock ticks on exit)

**Example**:
```
E 1090623040 15
```

Method 1090623040 exited at time 15.

### Field Update (U)

```
U <target-obj-id> <source-obj-id> <field-id> <timestamp>
```

**Fields**:
- `target-obj-id`: Object whose field is being updated (0 for static field)
- `source-obj-id`: Object being assigned to the field
- `field-id`: Field identifier
- `timestamp`: Logical time of update

**Example**:
```
U 1288354730 2117255219 1746572565 12
```

Object 1288354730's field 1746572565 updated to reference 2117255219 at time 12.

**Special case** (static field):
```
U 0 1288354730 1746572565 12
```

Static field 1746572565 updated to reference 1288354730 at time 12.

### Object Death (D)

```
D <object-id> <thread-id> <timestamp>
```

**Fields**:
- `object-id`: Object that died
- `thread-id`: Thread that allocated the object
- `timestamp`: Logical time of death

**Example**:
```
D 1288354730 1950409828 20
```

Object 1288354730 died at time 20.

## Logical Time

### Clock Semantics

Logical clock ticks **only at method boundaries**:

| Event | Clock Action |
|-------|--------------|
| Method entry (M) | Increment |
| Method exit (E) | Increment |
| All others (N, A, U, D) | Use current value |

### Example Timeline

```
M 100 0 1           # Clock: 0→1 (method entry)
N 1001 32 ... 1     # Clock: 1 (allocation, no tick)
N 1002 48 ... 1     # Clock: 1 (allocation, no tick)
U 1001 1002 ... 1   # Clock: 1 (field update, no tick)
E 100 2             # Clock: 1→2 (method exit)
D 1001 ... 2        # Clock: 2 (death, no tick)
M 200 1002 3        # Clock: 2→3 (method entry)
E 200 4             # Clock: 3→4 (method exit)
```

## Complete Example

### Java Program

```java
public class Example {
    static Object global;
    
    public static void main(String[] args) {
        Object a = new Object();
        Object b = new Object();
        a = b;  // a becomes unreachable
    }
}
```

### Generated Trace

```
M 100 0 1                    # main() entry: clock 0→1
N 1001 16 200 100 0 1       # new Object() → a
N 1002 16 200 100 0 1       # new Object() → b
U 0 1001 300 1              # global = a (static field update)
U 0 1002 300 1              # global = b (overwrites a)
E 100 2                     # main() exit: clock 1→2
D 1001 5001 2               # a dies (unreachable)
```

**Explanation**:
1. `main()` enters → clock ticks to 1
2. Two objects allocated at time 1
3. First assigned to static field
4. Overwritten by second object
5. `main()` exits → clock ticks to 2
6. First object unreachable → death at time 2

## Class and Method Maps

ET3 generates ID mapping files at shutdown.

### class_list

```
<class-id>,<class-name>
```

**Example**:
```
1437783372,java/lang/Object
1437783373,java/lang/String
1437783374,Example
```

### method_list

```
<method-id>,<class-id>,<method-name>
```

**Example**:
```
1090623040,1437783374,main
1090623041,1437783372,<init>
1090623042,1437783373,toString
```

## Parsing Traces

### Python Parser

```python
def parse_trace(trace_file):
    events = []
    
    with open(trace_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            
            record_type = parts[0]
            
            if record_type == 'N':
                events.append({
                    'type': 'alloc',
                    'object_id': int(parts[1]),
                    'size': int(parts[2]),
                    'type_id': int(parts[3]),
                    'site_id': int(parts[4]),
                    'time': int(parts[6])
                })
            
            elif record_type == 'M':
                events.append({
                    'type': 'method_entry',
                    'method_id': int(parts[1]),
                    'receiver': int(parts[2]),
                    'time': int(parts[3])
                })
            
            elif record_type == 'E':
                events.append({
                    'type': 'method_exit',
                    'method_id': int(parts[1]),
                    'time': int(parts[2])
                })
            
            elif record_type == 'U':
                events.append({
                    'type': 'field_update',
                    'target': int(parts[1]),
                    'source': int(parts[2]),
                    'field_id': int(parts[3]),
                    'time': int(parts[4])
                })
            
            elif record_type == 'D':
                events.append({
                    'type': 'death',
                    'object_id': int(parts[1]),
                    'thread_id': int(parts[2]),
                    'time': int(parts[3])
                })
    
    return events
```

### C++ Parser

```cpp
struct Event {
    enum Type { ALLOC, METHOD_ENTRY, METHOD_EXIT, UPDATE, DEATH };
    Type type;
    uint64_t time;
    uint64_t object_id;
    // ... other fields
};

std::vector<Event> parseTrace(const char* filename) {
    std::vector<Event> events;
    std::ifstream file(filename);
    std::string line;
    
    while (std::getline(file, line)) {
        std::istringstream iss(line);
        char type;
        iss >> type;
        
        Event e;
        
        switch (type) {
            case 'N': {
                uint64_t obj_id, size, type_id, site_id, zero, time;
                iss >> obj_id >> size >> type_id >> site_id >> zero >> time;
                e.type = Event::ALLOC;
                e.object_id = obj_id;
                e.time = time;
                // ... fill other fields
                break;
            }
            
            case 'M': {
                uint64_t method_id, receiver, time;
                iss >> method_id >> receiver >> time;
                e.type = Event::METHOD_ENTRY;
                e.time = time;
                // ... fill other fields
                break;
            }
            
            // ... other cases
        }
        
        events.push_back(e);
    }
    
    return events;
}
```

## Trace Properties

### Completeness

Every allocation should have a death:

```python
allocs = {e['object_id'] for e in events if e['type'] == 'alloc'}
deaths = {e['object_id'] for e in events if e['type'] == 'death'}

# In a complete trace (after program termination):
assert allocs == deaths
```

### Temporal Ordering

Events are in chronological order:

```python
times = [e['time'] for e in events]
assert times == sorted(times)
```

### Method Matching

Every method entry has a matching exit:

```python
stack = []
for e in events:
    if e['type'] == 'method_entry':
        stack.append(e['method_id'])
    elif e['type'] == 'method_exit':
        assert stack.pop() == e['method_id']
assert len(stack) == 0  # All methods exited
```

## Validation

### Basic Validation

```bash
#!/bin/bash
# validate_trace.sh

TRACE=$1

echo "Validating $TRACE..."

# Count records
TOTAL=$(wc -l < $TRACE)
VALID=$(grep -c "^[NAUMEXD]" $TRACE)

if [ $TOTAL -ne $VALID ]; then
    echo "❌ Found $((TOTAL - VALID)) invalid records"
    exit 1
fi

# Count allocations and deaths
ALLOCS=$(grep -c "^[NA]" $TRACE)
DEATHS=$(grep -c "^D" $TRACE)

echo "Allocations: $ALLOCS"
echo "Deaths: $DEATHS"
echo "Still alive: $((ALLOCS - DEATHS))"

# Check methods are balanced
ENTRIES=$(grep -c "^M" $TRACE)
EXITS=$(grep -c "^E" $TRACE)

if [ $ENTRIES -ne $EXITS ]; then
    echo "❌ Unbalanced methods: $ENTRIES entries, $EXITS exits"
    exit 1
fi

echo "✅ Trace valid"
```

## Trace Statistics

### Common Metrics

```python
def compute_stats(events):
    stats = {
        'total_events': len(events),
        'allocations': sum(1 for e in events if e['type'] == 'alloc'),
        'deaths': sum(1 for e in events if e['type'] == 'death'),
        'method_calls': sum(1 for e in events if e['type'] == 'method_entry'),
        'field_updates': sum(1 for e in events if e['type'] == 'field_update'),
        'time_span': max(e['time'] for e in events) - min(e['time'] for e in events),
    }
    
    # Memory metrics
    total_allocated = sum(e['size'] for e in events if e['type'] == 'alloc')
    stats['total_allocated'] = total_allocated
    
    # Lifetime metrics
    lifetimes = []
    alloc_times = {}
    for e in events:
        if e['type'] == 'alloc':
            alloc_times[e['object_id']] = e['time']
        elif e['type'] == 'death':
            if e['object_id'] in alloc_times:
                lifetimes.append(e['time'] - alloc_times[e['object_id']])
    
    if lifetimes:
        stats['avg_lifetime'] = sum(lifetimes) / len(lifetimes)
        stats['max_lifetime'] = max(lifetimes)
    
    return stats
```

## Next Steps

- See [Getting Started](../getting-started/) for generating traces
- See [Implementation](../implementation/merlin.md) for death detection details
- See [Oracle Construction](../development/oracle.md) for gem5 format conversion

## References

- Original Elephant Tracks paper: http://www.cs.tufts.edu/research/redline/elephantTracks/
- Merlin algorithm: https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf
