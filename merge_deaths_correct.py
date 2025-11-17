#!/usr/bin/env python3
"""
Correctly merge death records into trace by understanding the simulator's time counter.

The simulator's "time" is not the event index, but a counter that gets extracted from
trace records (the prev/rec in the verification output). We need to map event indices 
to this counter to know where to insert deaths.
"""

import sys
import re

def parse_death_line(line):
    """Parse death line: D 458209687 at time 2 (size: 24 bytes, type: TODO)"""
    match = re.match(r'D (\d+) at time (\d+) \(size: (\d+) bytes', line)
    if match:
        obj_id = match.group(1)
        time = int(match.group(2))
        size = int(match.group(3))
        return (obj_id, time, size)
    return None

def build_event_to_time_map(trace_file):
    """
    Build mapping from event index to time counter.
    Parse trace and extract timestamps/counters to understand when deaths occur.
    
    For now, we'll use a simple heuristic: the "time" from simulator
    likely corresponds to cumulative state changes.Looking at the trace records,
    we need to track which event indices correspond to which time values.
    """
    # Read through trace and build map
    # Based on the simulator output, times go from 0-56 across 95 trace records
    # This suggests times increment at certain events (not every line)
    
    event_to_time = {}
    current_time = 0
    
    with open(trace_file, 'r') as f:
        for event_idx, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            
            parts = line.split()
            if len(parts) < 2:
                continue
            
            rec_type = parts[0]
            
            # Time increments on certain record types
            # Based on simulator behavior: M, N, A records seem to advance time
            if rec_type in ['M', 'N', 'A']:
                current_time += 1
            
            event_to_time[event_idx] = current_time
    
    return event_to_time

def main(trace_file, deaths_file, output_file):
    # Parse death records
    deaths = []
    with open(deaths_file, 'r') as f:
        for line in f:
            parsed = parse_death_line(line.strip())
            if parsed:
                deaths.append(parsed)
    
    deaths.sort(key=lambda x: x[1])  # Sort by time
    print(f"Parsed {len(deaths)} death records")
    
    # Map each event to its time using "increment AFTER" strategy
    event_to_time = {}
    current_time = 0
    
    with open(trace_file, 'r') as f:
        for event_idx, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            
            rec_type = line.split()[0]
            
            # Record time BEFORE incrementing (time at which this event occurs)
            event_to_time[event_idx] = current_time
            
            # Then increment for M, N, A records
            if rec_type in ['M', 'N', 'A']:
                current_time += 1
    
    print(f"Mapped {len(event_to_time)} events to time values")
    print(f"Time range: {min(event_to_time.values())} to {max(event_to_time.values())}")
    
    # Build reverse map: time -> last event index at that time
    time_to_last_event = {}
    for event_idx, time in event_to_time.items():
        time_to_last_event[time] = max(time_to_last_event.get(time, -1), event_idx)
    
    # Build death insertion map: insert deaths AFTER the last event at their death time
    death_insertion_map = {}  # event_idx_after_which_to_insert -> list of deaths
    for obj_id, death_time, size in deaths:
        if death_time in time_to_last_event:
            insert_after_idx = time_to_last_event[death_time]
            if insert_after_idx not in death_insertion_map:
                death_insertion_map[insert_after_idx] = []
            death_insertion_map[insert_after_idx].append((obj_id, death_time, size))
        else:
            print(f"WARNING: Death time {death_time} for obj {obj_id} has no corresponding event")
    
    # Merge trace with deaths
    with open(trace_file, 'r') as inf, open(output_file, 'w') as outf:
        for event_idx, line in enumerate(inf):
            line = line.strip()
            if not line:
                continue
            
            # Write the trace record
            outf.write(line + '\n')
            
            # Insert any deaths that occur after this event
            if event_idx in death_insertion_map:
                for obj_id, death_time, size in death_insertion_map[event_idx]:
                    outf.write(f"D {obj_id} 1950409828 {death_time} {size}\n")
                    print(f"Inserted death for obj {obj_id} at time {death_time} after event {event_idx}")

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: merge_deaths_correct.py <trace> <deaths> <output>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
