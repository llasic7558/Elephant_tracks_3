# Concrete Example: Object Graph Reconstruction from ET3 Trace

## SimpleTrace Program

```java
// Creates a linked list of 10 nodes
class Node {
    Node next;
}

Node head = new Node();
Node current = head;
for (int i = 0; i < 9; i++) {
    Node newNode = new Node();
    current.next = newNode;  // ← Creates graph edge!
    current = newNode;
}
```

## ET3 Trace Output (Simplified)

```
N 1724731843 24 32 90 0 1950409828      # node1 = new Node()
N 1305193908 24 32 91 0 1950409828      # node2 = new Node()
U 1724731843 1305193908 16 1950409828   # node1.next = node2 ← EDGE!

N 463345942 24 32 91 0 1950409828       # node3 = new Node()
U 1305193908 463345942 16 1950409828    # node2.next = node3 ← EDGE!

N 195600860 24 32 91 0 1950409828       # node4 = new Node()
U 463345942 195600860 16 1950409828     # node3.next = node4 ← EDGE!

N 1334729950 24 32 91 0 1950409828      # node5 = new Node()
U 195600860 1334729950 16 1950409828    # node4.next = node5 ← EDGE!

... (continues for all 10 nodes)
```

## Reconstructed Object Graph

```
Object Graph at this point in time:

1724731843 ──→ 1305193908 ──→ 463345942 ──→ 195600860 ──→ 1334729950 ──→ ...
  (node1)        (node2)       (node3)       (node4)       (node5)

                    |
                    | Field update records (U)
                    | create edges in the graph
                    ↓
```

## How to Reconstruct Offline

### Step 1: Process N (allocation) records
```python
# N 1724731843 24 32 90 0 1950409828
objects[1724731843] = Node(type=24, size=90)
graph[1724731843] = set()  # Initially no outgoing edges
```

### Step 2: Process U (field update) records
```python
# U 1724731843 1305193908 16 1950409828
# This means: object 1724731843 now points to 1305193908
graph[1724731843].add(1305193908)
```

### Step 3: Result
```python
graph = {
    1724731843: {1305193908},      # node1 → node2
    1305193908: {463345942},       # node2 → node3
    463345942: {195600860},        # node3 → node4
    195600860: {1334729950},       # node4 → node5
    ...
}
```

## Full Record Format Explanation

### Allocation Record (N)
```
N 1724731843 24 32 90 0 1950409828
  │     │     │  │  │  │      │
  │     │     │  │  │  │      └─ Thread ID
  │     │     │  │  │  └──────── Allocation count (0 = first time)
  │     │     │  │  └─────────── Object size (90 bytes)
  │     │     │  └────────────── Allocation site ID (32)
  │     │     └───────────────── Class ID (24)
  │     └─────────────────────── Object ID (1724731843)
  └───────────────────────────── Record type (N = object allocation)
```

### Field Update Record (U)
```
U 1724731843 1305193908 16 1950409828
  │     │         │      │      │
  │     │         │      │      └─ Thread ID
  │     │         │      └──────── Field ID (16 = "next" field)
  │     │         └─────────────── Target object (1305193908)
  │     └───────────────────────── Source object (1724731843)
  └─────────────────────────────── Record type (U = field update)
```

**This is the critical record!** It means:
```java
object_1724731843.field_16 = object_1305193908;
// In Java source: node1.next = node2;
```

## Example: Query the Graph

### Q: What does object 1724731843 point to?
```python
>>> graph[1724731843]
{1305193908}
```

### Q: Build the complete linked list
```python
def traverse_list(start_id):
    path = [start_id]
    current = start_id
    while current in graph and graph[current]:
        current = next(iter(graph[current]))
        path.append(current)
    return path

>>> traverse_list(1724731843)
[1724731843, 1305193908, 463345942, 195600860, 1334729950, ...]
```

### Q: Compute reachability from roots
```python
def reachable_from(root_id):
    visited = set()
    queue = [root_id]
    
    while queue:
        obj_id = queue.pop(0)
        if obj_id in visited:
            continue
        visited.add(obj_id)
        
        if obj_id in graph:
            queue.extend(graph[obj_id])
    
    return visited

>>> reachable_from(1724731843)
{1724731843, 1305193908, 463345942, 195600860, 1334729950, ...}
```

## Death Records Complete the Picture

```
E 174 1950409828                       # Method exits
D 1305193908 1950409828 174842532151   # node2 died!
```

When we see a death record:
```python
# D 1305193908 1950409828 174842532151
del objects[1305193908]
del graph[1305193908]

# Remove incoming edges to this object
for obj_id in graph:
    graph[obj_id].discard(1305193908)
```

## Complete Timeline Replay

```
Time 0: Empty graph
  graph = {}

Time 1: N 1724731843 ...
  graph = {1724731843: set()}

Time 2: N 1305193908 ...
  graph = {1724731843: set(), 1305193908: set()}

Time 3: U 1724731843 1305193908 ...
  graph = {1724731843: {1305193908}, 1305193908: set()}
  
  Visualization: 1724731843 ──→ 1305193908

Time 4: N 463345942 ...
  graph = {1724731843: {1305193908}, 1305193908: set(), 463345942: set()}

Time 5: U 1305193908 463345942 ...
  graph = {1724731843: {1305193908}, 1305193908: {463345942}, 463345942: set()}
  
  Visualization: 1724731843 ──→ 1305193908 ──→ 463345942

... and so on ...
```

## Key Insight

**The U (field update) records contain the complete pointer graph!**

Every time Java code does:
```java
object.field = anotherObject;
```

ET3 generates:
```
U <object-id> <anotherObject-id> <field-id> <thread-id>
```

This is **all the information needed** to reconstruct:
- Object-to-object relationships
- Pointer graph structure
- Reachability paths
- Data structure shapes (linked lists, trees, graphs, etc.)

## Offline Analysis Capabilities

With ET3 traces, you can compute offline:

✅ Object graph at any point in time  
✅ Heap size evolution  
✅ Object lifetimes (allocation to death)  
✅ Reachability analysis  
✅ Reference counting  
✅ Escape analysis  
✅ Data structure identification  
✅ Memory leak detection  
✅ GC root set tracking  

**All without instrumenting the GC or modifying the JVM!**
