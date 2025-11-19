# ET3 Getting Started Guide

## Overview

**Elephant Tracks 3 with integrated Merlin death tracking** - A complete GC tracing tool that produces in-order traces with:
- ✅ Object allocations (N, A)
- ✅ Method entry/exit (M, E)
- ✅ Field updates (U)
- ✅ **Object deaths (D) - with Merlin Algorithm**

## Requirements

- **Java 21** (also compatible with Java 11, 17)
- **Maven 3.9+**
- **Javassist** 3.24.1-GA (included in dependencies)
- For trace analysis:
  - gcc/g++ or clang++
  - cmake 3.9 or greater

## Build Once

```bash
cd javassist-inst/et2-instrumenter
mvn clean compile package
```

This creates the instrumentation agent JAR at:
```
target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar
```

## Use Everywhere

### Basic Usage

```bash
java -javaagent:path/to/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar YourProgram
```

### With Your Own JAR

```bash
java -javaagent:./instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar -jar YourProgram.jar
```

### DaCapo Benchmarks

```bash
java -javaagent:./instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     -jar dacapo-9.12-bach.jar \
     --no-validation \
     -t 8 \
     avrora
```

**Note**: The `--no-validation` flag is required because bytecode rewriting causes DaCapo to flag runs as invalid.

## Test It

### Quick Test

```bash
cd /path/to/et2-java
./test_integrated_merlin.sh
```

Expected output:
```
Trace Statistics:
  Allocations:       15
  Field Updates:     9
  Method Entries:    23
  Method Exits:      22
  Deaths (Merlin):   15  ← All objects tracked!
```

### View Generated Trace

```bash
less trace_output_integrated/trace

# See just death records
grep "^D" trace_output_integrated/trace
```

## Trace Format

ET3 produces these record types:

```
N 1001 32 100 200 0 5001    # Object allocation
A 1002 40 101 200 10 5001   # Array allocation (length=10)
M 200 1001 5001              # Method entry (receiver=1001)
U 1001 1002 3 5001           # Field update (1001.field3 = 1002)
E 200 5001                   # Method exit
D 1001 5001                  # Object death ← NEW!
```

### Record Format Details

| Type | Format | Description |
|------|--------|-------------|
| **N** | `N <obj-id> <size> <type-id> <site-id> 0 <thread-id>` | Object allocation |
| **A** | `A <obj-id> <size> <type-id> <site-id> <length> <thread-id>` | Array allocation |
| **M** | `M <method-id> <receiver-id> <thread-id>` | Method entry |
| **E** | `E <method-id> <thread-id>` | Method exit |
| **U** | `U <obj-id> <new-tgt-id> <field-id> <thread-id>` | Field update |
| **D** | `D <obj-id> <thread-id>` | Object death |

## How It Works

1. **Object allocated** → Added to live set, tracked by Merlin
2. **Field updated** → Object reference graph updated
3. **Method exit** → Reachability analysis runs
4. **Unreachable objects** → Death records (D) written to trace

## Key Features

- **In-order traces**: Deaths appear in temporal order with other events
- **Method-boundary accuracy**: Deaths detected at method exit (E records)
- **Merlin algorithm**: Reachability-based, conservative detection
- **Real-time**: No post-processing needed
- **Logical time**: Uses method entry/exit for deterministic timestamps

## Performance

- ~5-10% runtime overhead for tracking
- Reachability analysis every 500 events (configurable)
- O(live objects) memory usage

## Troubleshooting

### No death records in trace

**Check**:
```bash
grep "^D" trace
```

**Solution**: Ensure the agent rebuilt correctly with `mvn clean compile package`

### Build errors

**Solution**: Verify Java 21 is being used:
```bash
java -version
mvn -version
```

### DaCapo validation errors

**Solution**: Always use `--no-validation` flag when running DaCapo benchmarks

## Next Steps

- Read [Implementation Guide](../implementation/merlin.md) for technical details
- See [Testing Guide](testing.md) for comprehensive testing instructions
- Refer to [Trace Format](../reference/trace-format.md) for complete format specification

## That's It!

You now have a complete GC tracing tool. Just rebuild once and use the `-javaagent` flag with any Java program.
