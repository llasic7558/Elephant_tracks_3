#!/usr/bin/env python3
"""
Reorder Death Records in ET Traces

The Merlin offline algorithm appends all death records to the end of the trace
with timestamps indicating when they should have occurred. This script reorders
the death records into their correct temporal positions based on the logical clock.

The logical clock in ET traces increments at:
- Method Entry (M records)
- Method Exit (E records)

Death timestamps represent the logical clock value when the object became unreachable.

Usage:
    python3 reorder_deaths.py <input_trace> <output_trace> [--verbose]
"""

import sys
import argparse
from typing import List, Tuple


class TraceReorderer:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.logical_clock = 0
        
    def reorder_trace(self, input_file: str, output_file: str):
        """
        Reorder death records into correct temporal positions.
        
        Algorithm:
        1. Read all trace records, tracking logical clock
        2. Separate death records (D) from other records
        3. Build mapping of logical_time -> line_index for non-death records
        4. Insert death records at appropriate positions
        """
        
        # Read entire trace
        with open(input_file, 'r') as f:
            lines = f.readlines()
        
        if self.verbose:
            print(f"Read {len(lines)} lines from {input_file}", file=sys.stderr)
        
        # Separate death records from other records
        trace_records = []  # (logical_time, line_text)
        death_records = []  # (timestamp, line_text)
        
        current_logical_time = 0
        
        for line in lines:
            stripped = line.strip()
            
            # Keep empty lines and comments as-is (no logical time)
            if not stripped or stripped.startswith('#'):
                trace_records.append((current_logical_time, line))
                continue
            
            parts = stripped.split()
            if not parts:
                trace_records.append((current_logical_time, line))
                continue
            
            record_type = parts[0]
            
            if record_type == 'D':
                # Death record: D <obj-id> <thread-id> <timestamp>
                if len(parts) >= 4:
                    timestamp = int(parts[3])
                    death_records.append((timestamp, line))
                else:
                    if self.verbose:
                        print(f"Warning: Malformed death record: {stripped}", file=sys.stderr)
            else:
                # Regular record - track logical clock
                # Clock increments at M (method entry) and E (method exit)
                if record_type in ['M', 'E', 'X']:  # X is exception exit, also increments
                    current_logical_time += 1
                
                trace_records.append((current_logical_time, line))
        
        if self.verbose:
            print(f"Found {len(trace_records)} trace records", file=sys.stderr)
            print(f"Found {len(death_records)} death records to reorder", file=sys.stderr)
            print(f"Max logical time: {current_logical_time}", file=sys.stderr)
        
        # Merge death records into trace at correct positions
        merged = self._merge_records(trace_records, death_records)
        
        # Write output
        with open(output_file, 'w') as f:
            for line in merged:
                f.write(line)
        
        if self.verbose:
            print(f"Wrote {len(merged)} lines to {output_file}", file=sys.stderr)
    
    def _merge_records(self, trace_records: List[Tuple[int, str]], 
                      death_records: List[Tuple[int, str]]) -> List[str]:
        """
        Merge death records into trace records at correct temporal positions.
        
        Death records should be inserted AFTER the trace record at their timestamp.
        For example, a death at timestamp 4 should appear after the record where
        logical_clock becomes 4 (typically an M or E record).
        """
        
        # Sort death records by timestamp
        death_records.sort(key=lambda x: x[0])
        
        merged = []
        death_idx = 0
        
        for i, (logical_time, line) in enumerate(trace_records):
            # Add the current trace record
            merged.append(line)
            
            # Insert all death records that should occur at or before this logical time
            while death_idx < len(death_records):
                death_time, death_line = death_records[death_idx]
                
                # Death should be inserted after we reach its timestamp
                if death_time <= logical_time:
                    merged.append(death_line)
                    death_idx += 1
                    if self.verbose and death_time < logical_time:
                        print(f"Debug: Inserting death at timestamp {death_time} " 
                              f"after record at logical time {logical_time}",
                              file=sys.stderr)
                else:
                    break
        
        # Add any remaining death records at the end (shouldn't happen with valid traces)
        while death_idx < len(death_records):
            death_time, death_line = death_records[death_idx]
            if self.verbose:
                print(f"Warning: Death at timestamp {death_time} inserted at end", 
                      file=sys.stderr)
            merged.append(death_line)
            death_idx += 1
        
        return merged
    
    def validate_trace(self, trace_file: str):
        """Validate that death records are properly ordered."""
        
        with open(trace_file, 'r') as f:
            lines = f.readlines()
        
        logical_clock = 0
        deaths_after_birth = 0
        deaths_in_order = 0
        
        allocated_objects = {}  # obj_id -> allocation_time
        
        for line in lines:
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            
            parts = stripped.split()
            if not parts:
                continue
            
            record_type = parts[0]
            
            # Track logical clock
            if record_type in ['M', 'E', 'X']:
                logical_clock += 1
            
            # Track allocations
            if record_type in ['N', 'A']:
                obj_id = int(parts[1])
                allocated_objects[obj_id] = logical_clock
            
            # Validate deaths
            if record_type == 'D':
                obj_id = int(parts[1])
                death_time = int(parts[3])
                
                # Check death is after allocation
                if obj_id in allocated_objects:
                    alloc_time = allocated_objects[obj_id]
                    if death_time >= alloc_time:
                        deaths_after_birth += 1
                    else:
                        print(f"ERROR: Object {obj_id} died at {death_time} "
                              f"but was allocated at {alloc_time}", file=sys.stderr)
                
                # Check death is at or before current time
                if death_time <= logical_clock:
                    deaths_in_order += 1
                else:
                    print(f"ERROR: Death at timestamp {death_time} appears "
                          f"at logical time {logical_clock}", file=sys.stderr)
        
        print(f"\n=== Validation Results ===", file=sys.stderr)
        print(f"Deaths correctly ordered: {deaths_in_order}", file=sys.stderr)
        print(f"Deaths after allocation: {deaths_after_birth}", file=sys.stderr)
        print(f"Total objects allocated: {len(allocated_objects)}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Reorder death records in ET trace based on timestamps'
    )
    parser.add_argument('input_trace', help='Input trace file with deaths at end')
    parser.add_argument('output_trace', help='Output trace file with reordered deaths')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Print verbose debugging info')
    parser.add_argument('--validate', action='store_true',
                        help='Validate output trace ordering')
    
    args = parser.parse_args()
    
    # Reorder trace
    reorderer = TraceReorderer(verbose=args.verbose)
    reorderer.reorder_trace(args.input_trace, args.output_trace)
    
    print(f"Successfully reordered trace: {args.output_trace}")
    
    # Validate if requested
    if args.validate:
        reorderer.validate_trace(args.output_trace)


if __name__ == '__main__':
    main()
