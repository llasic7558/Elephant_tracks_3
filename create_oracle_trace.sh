#!/bin/bash
# Create oracle trace with death records from simulator
# Usage: ./create_oracle_trace.sh <trace_directory>

set -e

TRACE_DIR=$1

if [ $# -eq 0 ]; then
    echo "Usage: $0 <trace_directory>"
    echo "Example: $0 pipeline_results/SimpleTrace_simulator_mode"
    exit 1
fi

if [ ! -d "$TRACE_DIR" ]; then
    echo "Error: Directory $TRACE_DIR does not exist"
    exit 1
fi

if [ ! -f "$TRACE_DIR/trace" ]; then
    echo "Error: No trace file found in $TRACE_DIR"
    exit 1
fi

echo "=== Creating Oracle Trace with Death Records ==="
echo ""

BASENAME=$(basename "$TRACE_DIR")
OUTPUT_BASE="oracle_trace_$BASENAME"

# Run simulator and capture all output
echo "Running simulator to compute death times..."
cat "$TRACE_DIR/trace" | \
  simulator/build/simulator SIM \
  "$TRACE_DIR/classes.txt" \
  "$TRACE_DIR/fields.txt" \
  "$TRACE_DIR/methods.txt" \
  "$OUTPUT_BASE" \
  NOCYCLE NOOBJDEBUG \
  "$BASENAME" main 2>&1 | tee "$TRACE_DIR/simulator_run.log"

# Extract death records with size information from log
echo ""
echo "Extracting death information..."
grep '^D ' "$TRACE_DIR/simulator_run.log" > "$TRACE_DIR/deaths_with_size.txt"
DEATH_COUNT=$(wc -l < "$TRACE_DIR/deaths_with_size.txt")
echo "  Found $DEATH_COUNT death records with size information"

# Create a Python script to merge deaths into trace
cat > "$TRACE_DIR/merge_deaths.py" << 'PYTHON_SCRIPT'
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
PYTHON_SCRIPT

chmod +x "$TRACE_DIR/merge_deaths.py"

# Merge deaths into trace
echo ""
echo "Merging death records into trace..."
python3 "$TRACE_DIR/merge_deaths.py" \
  "$TRACE_DIR/trace" \
  "$TRACE_DIR/deaths_with_size.txt" \
  "$TRACE_DIR/trace_with_deaths_oracle"

FINAL_COUNT=$(wc -l < "$TRACE_DIR/trace_with_deaths_oracle")
ORIG_COUNT=$(wc -l < "$TRACE_DIR/trace")
echo "  Original trace: $ORIG_COUNT records"
echo "  Oracle trace: $FINAL_COUNT records ($DEATH_COUNT deaths added)"

echo ""
echo "=== Building True Oracle Event Stream ==="
./build_true_oracle.py \
  "$TRACE_DIR/trace" \
  "$TRACE_DIR/deaths_with_size.txt" \
  "$TRACE_DIR/oracle_event_stream.txt"

echo ""
echo "=== Converting to CSV ==="
./oracle_to_csv.py \
  "$TRACE_DIR/oracle_event_stream.txt" \
  "$TRACE_DIR/oracle.csv"

echo ""
echo "=== Oracle Files Created ===" 
echo "  1. trace_with_deaths_oracle   - Raw trace with death records"
echo "  2. oracle_event_stream.txt    - Clean alloc/free event stream"
echo "  3. oracle.csv                 - CSV format for analysis"
echo ""
echo "Sample event stream (first 15 events):"
grep -v '^#' "$TRACE_DIR/oracle_event_stream.txt" | head -15
