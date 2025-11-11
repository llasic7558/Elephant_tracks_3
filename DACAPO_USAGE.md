# Running DaCapo Benchmarks with ET3+Merlin

## Quick Start

### First, rebuild ET3 if you haven't already:
```bash
cd /Users/luka/Desktop/Honors_Thesis/et2-java/javassist-inst/et2-instrumenter
mvn clean compile package
cd ../..
```

### List available benchmarks:
```bash
chmod +x run_dacapo_with_merlin.sh
./run_dacapo_with_merlin.sh list
```

### Run a benchmark (small size, good for testing):
```bash
./run_dacapo_with_merlin.sh avrora small
```

### Run different benchmarks:
```bash
# Fast benchmarks (good for testing)
./run_dacapo_with_merlin.sh avrora small      # ~10-30 seconds
./run_dacapo_with_merlin.sh fop small         # ~15-45 seconds
./run_dacapo_with_merlin.sh luindex small     # ~20-60 seconds

# Medium benchmarks
./run_dacapo_with_merlin.sh h2 small          # Database benchmark
./run_dacapo_with_merlin.sh pmd small         # Static analyzer
./run_dacapo_with_merlin.sh sunflow small     # Ray tracer

# Larger benchmarks (may take several minutes)
./run_dacapo_with_merlin.sh lusearch default  # Lucene search
./run_dacapo_with_merlin.sh xalan default     # XSLT processor
```

## Common DaCapo Benchmarks

| Benchmark | Description | Typical Time (small) |
|-----------|-------------|---------------------|
| avrora | AVR microcontroller simulator | ~30s |
| fop | XML to PDF formatter | ~45s |
| h2 | H2 database engine | ~1m |
| luindex | Lucene indexer | ~1m |
| lusearch | Lucene searcher | ~1m |
| pmd | Java source code analyzer | ~1.5m |
| sunflow | Ray tracer | ~2m |
| xalan | XSLT processor | ~1.5m |

## Size Options

- `small` - Quick runs for testing (~10-60s)
- `default` - Standard benchmark size (~1-5m)
- `large` - Extended runs (several minutes)
- `huge` - Very long runs (not recommended for initial testing)

## Output Location

Traces are saved to: `/Users/luka/Desktop/Honors_Thesis/et2-java/dacapo_traces/`

Each run generates:
- `<benchmark>_<size>_trace.txt` - Full trace with deaths
- `<benchmark>_<size>_methods.list` - Method metadata
- `<benchmark>_<size>_fields.list` - Field metadata
- `<benchmark>_<size>_classs.list` - Class metadata
- `<benchmark>_<size>_output.log` - Benchmark output

## What to Expect

✅ **Successful trace** should show:
- Thousands to millions of allocation records (N/A)
- Method entries/exits (M/E)
- Field updates (U)
- **Death records (D)** with timestamps

Example output:
```
Record Counts:
  Allocations (N/A): 125,432
  Method Entries (M): 543,210
  Method Exits (E):  543,198
  Field Updates (U): 89,234
  Deaths (D):        98,765    ← Death tracking working!
```

## Performance Notes

- **Overhead**: ET3+Merlin adds ~20-50% overhead
- **Memory**: Large benchmarks may need `-Xmx4g` or more
- **Trace size**: Can be very large (100s of MB to GBs)

## Troubleshooting

### Issue: OutOfMemoryError
**Solution**: Increase heap size in the script:
```bash
# Edit run_dacapo_with_merlin.sh, change:
-Xmx2g  →  -Xmx4g
```

### Issue: No death records
**Check**:
1. Ensure ET3 agent rebuilt with Merlin integration
2. Check `<benchmark>_output.log` for errors
3. Verify "ET3 trace complete with Merlin death tracking" message

### Issue: Trace file too large
**Solution**: Use smaller benchmark size or shorter benchmarks:
```bash
./run_dacapo_with_merlin.sh avrora small  # Smaller traces
```

## Example Session

```bash
# Rebuild ET3 with Merlin
cd javassist-inst/et2-instrumenter
mvn clean compile package
cd ../..

# Run a small benchmark
chmod +x run_dacapo_with_merlin.sh
./run_dacapo_with_merlin.sh avrora small

# Check the results
cd dacapo_traces
ls -lh avrora_small_trace.txt
head -100 avrora_small_trace.txt
grep "^D" avrora_small_trace.txt | head -10
```

## Advanced Usage

### Custom Java options:
Edit `run_dacapo_with_merlin.sh` to add:
```bash
java -javaagent:"$ET3_AGENT" \
     -Xmx4g \
     -XX:+UseG1GC \              # Use G1 garbage collector
     -XX:MaxGCPauseMillis=200 \  # Limit GC pauses
     -jar "$DACAPO_JAR" \
     ...
```

### Multiple runs for analysis:
```bash
for size in small default; do
    ./run_dacapo_with_merlin.sh avrora $size
done
```

## Interpreting Results

### Trace Format
```
N 12345 256 100 200 0 1234567890    # Object allocation
M 200 12345 1234567890              # Method entry
U 12345 67890 5 1234567890          # Field update
E 200 1234567890                    # Method exit
D 12345 1234567890 1234567895       # Object death (with timestamp!)
```

### Death Record Format
```
D <object-id> <thread-id> <timestamp>
```

- `object-id`: Hash code of the dead object
- `thread-id`: Thread that allocated it
- `timestamp`: When it died (nanoseconds, method exit time)

## Next Steps

After generating traces, you can:
1. **Analyze with simulator**: Process traces to compute heap statistics
2. **Validate deaths**: Check that deaths ≤ allocations
3. **Study object lifetimes**: Time between allocation and death
4. **Compare benchmarks**: See which create more short-lived objects

## References

- DaCapo: https://www.dacapobench.org/
- ET3 Documentation: See `ET3_INTEGRATED_MERLIN.md`
- Merlin Algorithm: See `MERLIN_README.md`
