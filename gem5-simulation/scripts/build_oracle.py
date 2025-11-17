#!/usr/bin/env python3
"""
Oracle Builder for ET Traces with Merlin Death Records

Constructs an "oracle" event stream from an Elephant Tracks trace file.
For each object, extracts allocation time, death time, size, site, and thread.
Outputs a temporal sequence of alloc/free events.

Usage:
    python3 build_oracle.py <input_trace_file> [--output <output_file>] [--verbose]
"""

import sys
import argparse
from collections import namedtuple
from typing import Dict, List, Tuple

# Data structures
AllocationInfo = namedtuple('AllocationInfo', [
    'object_id', 'size', 'type_id', 'site_id', 'thread_id',
    'event_index', 'is_array', 'array_length'
])

DeathInfo = namedtuple('DeathInfo', [
    'object_id', 'thread_id', 'timestamp', 'event_index'
])

Event = namedtuple('Event', [
    'timestamp', 'event_type', 'object_id', 'size', 
    'site_id', 'thread_id', 'type_id', 'event_index'
])


class OracleBuilder:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.allocations: Dict[int, AllocationInfo] = {}
        self.deaths: Dict[int, DeathInfo] = {}
        self.event_index = 0
        
    def parse_trace(self, trace_file: str) -> Tuple[Dict[int, AllocationInfo], Dict[int, DeathInfo]]:
        """Parse the trace file and extract allocation and death records."""
        
        with open(trace_file, 'r') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                parts = line.split()
                if not parts:
                    continue
                
                record_type = parts[0]
                
                try:
                    if record_type == 'N':  # Object allocation
                        self._parse_allocation(parts, is_array=False)
                    elif record_type == 'A':  # Array allocation
                        self._parse_allocation(parts, is_array=True)
                    elif record_type == 'D':  # Death record
                        self._parse_death(parts)
                    
                    # Increment event index for all trace records
                    # (to maintain temporal ordering)
                    self.event_index += 1
                    
                except Exception as e:
                    if self.verbose:
                        print(f"Warning: Error parsing line {line_num}: {line}", file=sys.stderr)
                        print(f"  Error: {e}", file=sys.stderr)
        
        if self.verbose:
            print(f"Parsed {len(self.allocations)} allocations", file=sys.stderr)
            print(f"Parsed {len(self.deaths)} deaths", file=sys.stderr)
        
        return self.allocations, self.deaths
    
    def _parse_allocation(self, parts: List[str], is_array: bool):
        """Parse allocation record: N/A <obj-id> <size> <type-id> <site-id> <length> <thread-id>"""
        if len(parts) < 7:
            return
        
        object_id = int(parts[1])
        size = int(parts[2])
        type_id = int(parts[3])
        site_id = int(parts[4])
        array_length = int(parts[5])
        thread_id = int(parts[6])
        
        alloc = AllocationInfo(
            object_id=object_id,
            size=size,
            type_id=type_id,
            site_id=site_id,
            thread_id=thread_id,
            event_index=self.event_index,
            is_array=is_array,
            array_length=array_length
        )
        
        self.allocations[object_id] = alloc
    
    def _parse_death(self, parts: List[str]):
        """Parse death record: D <obj-id> <thread-id> <timestamp>"""
        if len(parts) < 4:
            return
        
        object_id = int(parts[1])
        thread_id = int(parts[2])
        timestamp = int(parts[3])
        
        death = DeathInfo(
            object_id=object_id,
            thread_id=thread_id,
            timestamp=timestamp,
            event_index=self.event_index
        )
        
        self.deaths[object_id] = death
    
    def build_event_stream(self) -> List[Event]:
        """Build a chronological event stream of alloc/free operations."""
        
        events = []
        
        # Add allocation events
        for obj_id, alloc in self.allocations.items():
            event = Event(
                timestamp=alloc.event_index,  # Use event index as logical time
                event_type='alloc',
                object_id=obj_id,
                size=alloc.size,
                site_id=alloc.site_id,
                thread_id=alloc.thread_id,
                type_id=alloc.type_id,
                event_index=alloc.event_index
            )
            events.append(event)
        
        # Add death/free events
        for obj_id, death in self.deaths.items():
            # Get allocation info for this object
            alloc = self.allocations.get(obj_id)
            if alloc is None:
                if self.verbose:
                    print(f"Warning: Death record for unknown object {obj_id}", file=sys.stderr)
                continue
            
            event = Event(
                timestamp=death.event_index,  # Use event index as logical time
                event_type='free',
                object_id=obj_id,
                size=alloc.size,
                site_id=alloc.site_id,
                thread_id=death.thread_id,
                type_id=alloc.type_id,
                event_index=death.event_index
            )
            events.append(event)
        
        # Sort by timestamp (event index)
        events.sort(key=lambda e: e.timestamp)
        
        return events
    
    def print_event_stream(self, events: List[Event], output_file=None):
        """Print the event stream in a human-readable format."""
        
        f = open(output_file, 'w') if output_file else sys.stdout
        
        try:
            # Print header
            print("# Oracle Event Stream", file=f)
            print("# Format: t<event_index>: <event_type>(id=<obj_id>, size=<bytes>, site=<site_id>, thread=<thread_id>)", file=f)
            print(f"# Total events: {len(events)}", file=f)
            print(f"# Allocations: {sum(1 for e in events if e.event_type == 'alloc')}", file=f)
            print(f"# Frees: {sum(1 for e in events if e.event_type == 'free')}", file=f)
            print(file=f)
            
            # Print events
            for event in events:
                print(f"t{event.timestamp}: {event.event_type}(id={event.object_id}, "
                      f"size={event.size}, site={event.site_id}, thread={event.thread_id})", 
                      file=f)
        
        finally:
            if output_file:
                f.close()
    
    def export_csv(self, events: List[Event], output_file: str):
        """Export event stream as CSV for analysis."""
        
        with open(output_file, 'w') as f:
            # Write header
            print("timestamp,event_type,object_id,size,site_id,thread_id,type_id", file=f)
            
            # Write events
            for event in events:
                print(f"{event.timestamp},{event.event_type},{event.object_id},"
                      f"{event.size},{event.site_id},{event.thread_id},{event.type_id}", 
                      file=f)
    
    def print_statistics(self, events: List[Event]):
        """Print statistics about the oracle."""
        
        allocs = [e for e in events if e.event_type == 'alloc']
        frees = [e for e in events if e.event_type == 'free']
        
        total_allocated = sum(e.size for e in allocs)
        total_freed = sum(e.size for e in frees)
        
        print(f"\n=== Oracle Statistics ===", file=sys.stderr)
        print(f"Total events: {len(events)}", file=sys.stderr)
        print(f"Allocations: {len(allocs)}", file=sys.stderr)
        print(f"Frees: {len(frees)}", file=sys.stderr)
        print(f"Live objects (not freed): {len(allocs) - len(frees)}", file=sys.stderr)
        print(f"Total bytes allocated: {total_allocated}", file=sys.stderr)
        print(f"Total bytes freed: {total_freed}", file=sys.stderr)
        print(f"Live bytes: {total_allocated - total_freed}", file=sys.stderr)
        
        # Site statistics
        site_counts = {}
        for alloc in allocs:
            site_counts[alloc.site_id] = site_counts.get(alloc.site_id, 0) + 1
        
        print(f"\nAllocation sites: {len(site_counts)}", file=sys.stderr)
        print(f"Most active sites:", file=sys.stderr)
        for site, count in sorted(site_counts.items(), key=lambda x: x[1], reverse=True)[:5]:
            print(f"  Site {site}: {count} allocations", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Build oracle event stream from ET trace with Merlin death records'
    )
    parser.add_argument('input_trace', help='Input trace file')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    parser.add_argument('--csv', help='Export CSV to specified file')
    parser.add_argument('--verbose', '-v', action='store_true', 
                        help='Print verbose debugging info')
    parser.add_argument('--stats', '-s', action='store_true',
                        help='Print statistics')
    
    args = parser.parse_args()
    
    # Build oracle
    builder = OracleBuilder(verbose=args.verbose)
    builder.parse_trace(args.input_trace)
    events = builder.build_event_stream()
    
    # Output results
    builder.print_event_stream(events, args.output)
    
    # Export CSV if requested
    if args.csv:
        builder.export_csv(events, args.csv)
        if args.verbose:
            print(f"CSV exported to {args.csv}", file=sys.stderr)
    
    # Print statistics if requested
    if args.stats:
        builder.print_statistics(events)


if __name__ == '__main__':
    main()
