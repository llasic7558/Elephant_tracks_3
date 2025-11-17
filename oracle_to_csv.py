#!/usr/bin/env python3
"""
Convert oracle event stream to CSV for easy analysis in Excel, pandas, etc.

Output columns:
  event_idx, event_type, obj_id, size, site, thread
"""

import sys
import re

def parse_event_line(line):
    """Parse oracle event line"""
    # t3: alloc(id=458209687, size=24, site=62, thread=1950409828)
    # t8: free(id=38997010, size=40)
    
    match_alloc = re.match(r't(\d+): alloc\(id=(\d+), size=(\d+), site=(\d+), thread=(\d+)\)', line)
    if match_alloc:
        return {
            'event_idx': int(match_alloc.group(1)),
            'event_type': 'alloc',
            'obj_id': match_alloc.group(2),
            'size': int(match_alloc.group(3)),
            'site': int(match_alloc.group(4)),
            'thread': match_alloc.group(5)
        }
    
    match_free = re.match(r't(\d+): free\(id=(\d+), size=(\d+)\)', line)
    if match_free:
        return {
            'event_idx': int(match_free.group(1)),
            'event_type': 'free',
            'obj_id': match_free.group(2),
            'size': int(match_free.group(3)),
            'site': '',
            'thread': ''
        }
    
    return None

def convert_to_csv(oracle_file, csv_file):
    """Convert oracle to CSV"""
    print(f"Converting {oracle_file} to CSV...")
    
    events = []
    with open(oracle_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#') or not line:
                continue
            
            event = parse_event_line(line)
            if event:
                events.append(event)
    
    # Write CSV
    with open(csv_file, 'w') as f:
        f.write("event_idx,event_type,obj_id,size,site,thread\n")
        for event in events:
            f.write(f"{event['event_idx']},{event['event_type']},{event['obj_id']},"
                   f"{event['size']},{event['site']},{event['thread']}\n")
    
    print(f"✓ Wrote {len(events)} events to {csv_file}")

def main():
    if len(sys.argv) != 3:
        print("Usage: oracle_to_csv.py <oracle.txt> <output.csv>")
        sys.exit(1)
    
    convert_to_csv(sys.argv[1], sys.argv[2])

if __name__ == '__main__':
    main()
