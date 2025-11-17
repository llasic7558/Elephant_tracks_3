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
        return (obj_id, time, size, obj_type)
    return None

# Parse death records
deaths = []
with open('pipeline_results/SimpleTrace_simulator_mode/deaths_with_size.txt', 'r') as f:
    for line in f:
        parsed = parse_death_line(line.strip())
        if parsed:
            deaths.append(parsed)

# Sort by time
deaths.sort(key=lambda x: x[1])

print(f"Parsed {len(deaths)} death records")
print(f"First 5 deaths: {deaths[:5]}")

# Build death_map
death_map = {}
for obj_id, time, size, obj_type in deaths:
    if time not in death_map:
        death_map[time] = []
    death_map[time].append((obj_id, size))

print(f"\nDeath map keys (times): {sorted(death_map.keys())}")
print(f"Deaths at time 0: {death_map.get(0, 'NONE')}")
print(f"Deaths at time 1: {death_map.get(1, 'NONE')}")
print(f"Deaths at time 2: {death_map.get(2, 'NONE')}")
