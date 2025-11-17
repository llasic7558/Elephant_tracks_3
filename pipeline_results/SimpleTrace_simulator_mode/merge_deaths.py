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
        return (time, obj_id, size, obj_type)
    return None

def main(trace_file, deaths_file, output_file):
    # Parse death records
    deaths = []
    with open(deaths_file, 'r') as f:
        for line in f:
            parsed = parse_death_line(line.strip())
            if parsed:
                deaths.append(parsed)
    
    # Sort by time
    deaths.sort(key=lambda x: x[0])
    
    print(f"Parsed {len(deaths)} death records")
    
    # Read trace and merge deaths
    death_idx = 0
    with open(trace_file, 'r') as inf, open(output_file, 'w') as outf:
        for line in inf:
            line = line.strip()
            if not line:
                continue
            
            # Extract timestamp from record
            parts = line.split()
            if len(parts) < 2:
                continue
            
            rec_type = parts[0]
            rec_time = int(parts[-1])  # Last field is usually timestamp
            
            # Insert all deaths before or at this time
            while death_idx < len(deaths) and deaths[death_idx][0] <= rec_time:
                time, obj_id, size, obj_type = deaths[death_idx]
                # Format: D <object-id> <thread-id> <timestamp> <size>
                outf.write(f"D {obj_id} 1950409828 {time} {size}\n")
                death_idx += 1
            
            # Write original record
            outf.write(line + '\n')
        
        # Write any remaining deaths
        while death_idx < len(deaths):
            time, obj_id, size, obj_type = deaths[death_idx]
            outf.write(f"D {obj_id} 1950409828 {time} {size}\n")
            death_idx += 1

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: merge_deaths.py <trace> <deaths> <output>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
