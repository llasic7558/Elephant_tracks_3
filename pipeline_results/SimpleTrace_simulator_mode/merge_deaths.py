#!/usr/bin/env python3
import sys
import re

def parse_death_line(line):
    """Parse death line: D 458209687 at time 2 (size: 24 bytes, type: java.lang.String)"""
    match = re.match(r'D (\d+) at time (\d+) \(size: (\d+) bytes, type: (.+?)\)', line)
    if match:
        obj_id = match.group(1)
        time = int(match.group(2))
        size = int(match.group(3))
        obj_type = match.group(4).replace(' [end]', '')
        return (obj_id, time, size, obj_type)  # Return obj_id first
    return None

def main(trace_file, deaths_file, output_file):
    # Parse death records
    deaths = []
    with open(deaths_file, 'r') as f:
        for line in f:
            parsed = parse_death_line(line.strip())
            if parsed:
                deaths.append(parsed)
    
    # Sort by time (second element)
    deaths.sort(key=lambda x: x[1])
    
    print(f"Parsed {len(deaths)} death records")
    
    # Build a map of death_time -> list of deaths at that time
    death_map = {}
    for obj_id, time, size, obj_type in deaths:
        if time not in death_map:
            death_map[time] = []
        death_map[time].append((obj_id, size))
    
    # Read trace with line numbers (event indices)
    event_idx = 0
    with open(trace_file, 'r') as inf, open(output_file, 'w') as outf:
        for line in inf:
            line = line.strip()
            if not line:
                continue
            
            # Insert deaths that occur BEFORE this event (at current index)
            # Deaths at time T happen before the trace record at index T
            if event_idx in death_map:
                for obj_id, size in death_map[event_idx]:
                    # Format: D <object-id> <thread-id> <timestamp> <size>
                    outf.write(f"D {obj_id} 1950409828 {event_idx} {size}\n")
            
            # Write original record
            outf.write(line + '\n')
            event_idx += 1
        
        # Write any remaining deaths at the end (after last event)
        for time in sorted(death_map.keys()):
            if time >= event_idx:
                for obj_id, size in death_map[time]:
                    outf.write(f"D {obj_id} 1950409828 {time} {size}\n")

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: merge_deaths.py <trace> <deaths> <output>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
