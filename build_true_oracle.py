#!/usr/bin/env python3
"""
Build True Oracle - Creates allocation/free event stream from ET3 trace + Merlin deaths

Format:
  t0: alloc(id=1, size=32, site=5, thread=123)
  t1: alloc(id=2, size=128, site=7, thread=123)
  t2: free(id=1)
  t3: alloc(id=3, size=64, site=5, thread=456)
  t4: free(id=2)
  ...
"""

import sys
import re
from collections import defaultdict

def parse_allocation_record(line):
    """Parse N or A record from trace
    N format: N <obj-id> <size> <type-id> <site-id> <length> <thread-id>
    A format: A <obj-id> <size> <type-id> <site-id> <length> <thread-id>
    Returns: (obj_id, size, site_id, thread_id)
    """
    parts = line.strip().split()
    if len(parts) < 7:
        return None
    
    rec_type = parts[0]
    if rec_type not in ['N', 'A']:
        return None
    
    obj_id = parts[1]
    size = int(parts[2])
    type_id = int(parts[3])
    site_id = int(parts[4])
    length = int(parts[5])
    thread_id = parts[6]
    
    return {
        'type': 'alloc',
        'obj_id': obj_id,
        'size': size,
        'site': site_id,
        'thread': thread_id,
        'alloc_type': rec_type
    }

def parse_death_line(line):
    """Parse death line: D 458209687 at time 2 (size: 24 bytes, type: TODO)"""
    match = re.match(r'D (\d+) at time (\d+) \(size: (\d+) bytes', line)
    if match:
        obj_id = match.group(1)
        time = int(match.group(2))
        size = int(match.group(3))
        return (obj_id, time, size)
    return None

def build_event_stream(trace_file, deaths_file, output_file):
    """Build chronological event stream of allocations and frees"""
    
    print("Building true oracle event stream...")
    
    # Parse allocations from trace with their event indices
    allocations = {}  # obj_id -> (event_idx, alloc_info)
    event_idx = 0
    
    with open(trace_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            alloc_info = parse_allocation_record(line)
            if alloc_info:
                obj_id = alloc_info['obj_id']
                allocations[obj_id] = (event_idx, alloc_info)
                print(f"  Found allocation: obj {obj_id} at event {event_idx}, size={alloc_info['size']}")
            
            event_idx += 1
    
    print(f"\nTotal allocations found: {len(allocations)}")
    
    # Parse deaths
    deaths = {}  # obj_id -> (death_event_idx, size)
    with open(deaths_file, 'r') as f:
        for line in f:
            parsed = parse_death_line(line.strip())
            if parsed:
                obj_id, death_time, size = parsed
                deaths[obj_id] = (death_time, size)
                print(f"  Found death: obj {obj_id} at event {death_time}")
    
    print(f"Total deaths found: {len(deaths)}")
    
    # Build event stream
    events = []
    
    # Add allocation events
    for obj_id, (event_idx, alloc_info) in allocations.items():
        events.append({
            'time': event_idx,
            'type': 'alloc',
            'obj_id': obj_id,
            'size': alloc_info['size'],
            'site': alloc_info['site'],
            'thread': alloc_info['thread']
        })
    
    # Add death/free events
    for obj_id, (death_time, size) in deaths.items():
        if obj_id in allocations:
            events.append({
                'time': death_time,
                'type': 'free',
                'obj_id': obj_id,
                'size': size
            })
        else:
            print(f"  WARNING: Death for obj {obj_id} has no allocation record (phantom object)")
            # Still add it - these are JVM infrastructure objects
            events.append({
                'time': death_time,
                'type': 'free',
                'obj_id': obj_id,
                'size': size
            })
    
    # Sort by time
    events.sort(key=lambda e: e['time'])
    
    # Write event stream
    with open(output_file, 'w') as f:
        f.write("# True Oracle Event Stream\n")
        f.write("# Format: t<event_idx>: alloc(id=<obj_id>, size=<bytes>, site=<site_id>, thread=<thread_id>)\n")
        f.write("#         t<event_idx>: free(id=<obj_id>, size=<bytes>)\n")
        f.write(f"# Total events: {len(events)}\n")
        f.write(f"# Allocations: {sum(1 for e in events if e['type'] == 'alloc')}\n")
        f.write(f"# Frees: {sum(1 for e in events if e['type'] == 'free')}\n")
        f.write("\n")
        
        for event in events:
            if event['type'] == 'alloc':
                f.write(f"t{event['time']}: alloc(id={event['obj_id']}, "
                       f"size={event['size']}, site={event['site']}, thread={event['thread']})\n")
            else:  # free
                f.write(f"t{event['time']}: free(id={event['obj_id']}, size={event['size']})\n")
    
    print(f"\n✓ Oracle event stream written to {output_file}")
    print(f"  Total events: {len(events)}")
    print(f"  Allocations: {sum(1 for e in events if e['type'] == 'alloc')}")
    print(f"  Frees: {sum(1 for e in events if e['type'] == 'free')}")
    
    # Statistics
    total_allocated = sum(e['size'] for e in events if e['type'] == 'alloc')
    total_freed = sum(e['size'] for e in events if e['type'] == 'free')
    
    print(f"\n  Total memory allocated: {total_allocated} bytes")
    print(f"  Total memory freed: {total_freed} bytes")
    print(f"  Still live at end: {total_allocated - total_freed} bytes")

def main():
    if len(sys.argv) != 4:
        print("Usage: build_true_oracle.py <trace_file> <deaths_file> <output_file>")
        print("\nExample:")
        print("  ./build_true_oracle.py trace deaths_with_size.txt oracle.txt")
        sys.exit(1)
    
    trace_file = sys.argv[1]
    deaths_file = sys.argv[2]
    output_file = sys.argv[3]
    
    build_event_stream(trace_file, deaths_file, output_file)

if __name__ == '__main__':
    main()
