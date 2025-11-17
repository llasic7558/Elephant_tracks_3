# ET2 Simulator Analysis and Usage Guide

## Overview

The ET2 simulator in the `simulator/` directory is a C++ program designed to analyze ET2 trace files and compute precise object death times using the Merlin algorithm. **Yes, it is possible to run it with your current traces**, but some format conversion is required.

## Current Status

### ✅ What We Have
1. **Traces**: Generated in `test_traces_online/` directories (HelloWorld, LotsOfAllocs, Methods, NewCall, SimpleTrace)
2. **Metadata Files**: The ET3 instrumenter DOES generate metadata files:
   - `classs.list` (note: triple 's')
   - `fields.list`
   - `methods.list`
3. **Build Dependencies**: All requirements are met:
   - CMake: `/usr/local/bin/cmake`
   - g++: `/usr/bin/g++`
   - Boost: `/usr/local/Cellar/boost/1.89.0/`

### ⚠️ Format Mismatch

The ET3 metadata files use a different format than the simulator expects:

**Current ET3 Format** (CSV, value-first):
```
HelloWorld,32
java.util.Vector#get,103
java.util.LinkedList#first,6
```

**Required Simulator Format** (space-separated, ID-first):
```
32 HelloWorld
103 java.util.Vector get
6 java.util.LinkedList first
```

## Simulator Requirements

### Command Line Interface

The simulator expects:
```bash
./simulator SIM <classes_file> <fields_file> <methods_file> <output_base> <CYCLE/NOCYCLE> <OBJDEBUG/NOOBJDEBUG> <main.class> <main.function>
```

With trace data piped via stdin:
```bash
cat trace | ./simulator SIM classes.txt fields.txt methods.txt output NOCYCLE NOOBJDEBUG HelloWorld main
```

### File Formats

1. **Classes file**: `<type_id> <class_name>`
   ```
   1 java.lang.String
   32 HelloWorld
   ```

2. **Fields file**: `<field_id> <field_name>`
   ```
   1 sun.launcher.LauncherHelper outBuf
   5 java.util.Vector elementData
   ```

3. **Methods file**: `<method_id> <class_name> <method_name>`
   ```
   59 veroy.research.et2.javassist.MerlinTracker <clinit>
   103 java.util.Vector get
   ```

## Steps to Run the Simulator

### 1. Convert Metadata Files

Create conversion script `convert_metadata.sh`:

```bash
#!/bin/bash
# Convert ET3 metadata format to simulator format

TRACE_DIR=$1

# Convert classes: "ClassName,ID" -> "ID ClassName"
cat "$TRACE_DIR/classs.list" | grep -v '^$' | awk -F',' '{print $2, $1}' > "$TRACE_DIR/classes.txt"

# Convert fields: "ClassName#fieldName,ID" -> "ID ClassName fieldName"
cat "$TRACE_DIR/fields.list" | grep -v '^$' | awk -F',' '{
    split($1, parts, "#");
    print $2, parts[1], parts[2]
}' > "$TRACE_DIR/fields.txt"

# Convert methods: "ClassName#methodName,ID" -> "ID ClassName methodName"
cat "$TRACE_DIR/methods.list" | grep -v '^$' | awk -F',' '{
    split($1, parts, "#");
    print $2, parts[1], parts[2]
}' > "$TRACE_DIR/methods.txt"

echo "Converted metadata files in $TRACE_DIR"
```

### 2. Build the Simulator

```bash
cd simulator
mkdir -p build
cd build
cmake -DBOOST_ROOT=/usr/local/Cellar/boost/1.89.0 ..
make
```

This will create two executables:
- `simulator` - Standard version
- `simulator-type1` - With TYPE1 flag enabled

### 3. Run the Simulator

```bash
# Example with HelloWorld trace
cd /Users/luka/Desktop/Honors_Thesis/et2-java

# Convert metadata
./convert_metadata.sh test_traces_online/HelloWorld

# Run simulator
cat test_traces_online/HelloWorld/trace | \
  simulator/build/simulator SIM \
  test_traces_online/HelloWorld/classes.txt \
  test_traces_online/HelloWorld/fields.txt \
  test_traces_online/HelloWorld/methods.txt \
  output_helloworld \
  NOCYCLE \
  NOOBJDEBUG \
  HelloWorld \
  main
```

## Trace Format Compatibility

The ET3 traces use the following record types (compatible with simulator):

- **M** - Method entry: `M <method-id> <receiver-object-id> <thread-id>`
- **E** - Method exit: `E <method-id> <thread-id>`
- **N** - Object allocation: `N <object-id> <size> <type-id> <site-id> <length> <thread-id>`
- **A** - Array allocation: `A <object-id> <size> <type-id> <site-id> <length> <thread-id>`
- **U** - Field update: `U <obj-id> <new-tgt-obj-id> <field-id> <thread-id>`
- **D** - Death record: `D <object-id> <thread-id> <timestamp>` (from Merlin)

The simulator reads these records from stdin and applies the Merlin algorithm to compute death times.

## Expected Outputs

The simulator will:
1. Parse the metadata files
2. Read the trace from stdin
3. Apply the Merlin algorithm
4. Output analysis results including:
   - Object lifetimes
   - Death times
   - Reference patterns (STABLE, SERIAL_STABLE, UNSTABLE)
   - Heap statistics

## Next Steps

1. **Create the conversion script** as shown above
2. **Build the simulator** using CMake
3. **Test with a simple trace** (e.g., HelloWorld)
4. **Verify output** matches expected behavior
5. **Run on larger traces** (e.g., LotsOfAllocs, DaCapo benchmarks)

## Potential Issues

1. **Timestamp differences**: ET3 uses logical clock timestamps, while the original ET2 may have used different timing. The simulator should handle this.

2. **Missing death records**: Your traces already include death records from the integrated Merlin tracker in ET3, so the simulator's Merlin implementation might be redundant but shouldn't conflict.

3. **Memory usage**: Large traces may require significant RAM for the simulator's in-memory processing.

## Alternative: Offline Merlin Mode

Note that your ET3 implementation already has an offline Merlin tracker (`MerlinDeathTracker.java`). You might consider:
1. Using the existing offline tracker to enhance traces
2. Building custom analysis tools instead of the original simulator
3. Comparing results between the Java Merlin tracker and C++ simulator

## References

- Original simulator repo: https://github.com/ElephantTracksProject/et2-simulator
- Simulator code: `simulator/simulator.cpp`
- ET3 instrumenter: `javassist-inst/et2-instrumenter/`
- Merlin documentation: `MERLIN_USAGE.md`
