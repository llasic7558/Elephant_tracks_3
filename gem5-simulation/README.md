# gem5 Memory Management Comparison

This project simulates and compares **explicit memory management** (malloc/free) vs **garbage collection** using [gem5](https://www.gem5.org/) with Elephant Tracks trace files.

## Overview

The goal is to replay Java workload traces (from DaCapo benchmarks or other Java programs) in a C++ environment to compare:
- **Explicit Memory Management**: Immediate deallocation when objects die (using malloc/free)
- **Garbage Collection**: Deferred deallocation with periodic collection cycles

## Project Structure

```
gem5-simulation/
├── src/
│   └── TraceReplayer.cpp         # Main C++ trace replay engine
├── configs/
│   └── memory_comparison_config.py  # gem5 configuration
├── scripts/
│   ├── build.sh                   # Build the replayer
│   ├── test_replayer.sh          # Test replayer locally without gem5
│   ├── run_simulation.sh         # Run gem5 simulation
│   ├── run_in_docker.sh          # Run simulation in Docker container
│   └── analyze_results.py        # Analyze and compare results
├── traces/                        # Place trace files here
├── results/                       # Simulation results go here
└── README.md                      # This file
```

## Prerequisites

### For Local Testing (No gem5 required)
- C++ compiler (g++ or clang++)
- C++11 support

### For gem5 Simulation
- gem5 installed or Docker with gem5 image
- Python 3.6+
- For analysis: matplotlib, numpy

## Quick Start

### 1. Generate Elephant Tracks Trace

First, generate a trace file using your ET instrumenter:

```bash
# From et2-java directory
cd /Users/luka/Desktop/Honors_Thesis/et2-java

# For a simple test
java -javaagent:javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     java.SimpleTrace

# This creates a 'trace' file with allocations and deaths
```

### 2. Build TraceReplayer

```bash
cd gem5-simulation
./scripts/build.sh
```

This creates `build/trace_replayer`.

### 3. Test Locally (Without gem5)

Test that the replayer works with your trace:

```bash
# Test explicit memory management
./scripts/test_replayer.sh -t ../trace_output/trace -m explicit

# Test GC mode
./scripts/test_replayer.sh -t ../trace_output/trace -m gc -v
```

This will show statistics like:
- Total allocations/deallocations
- Peak memory usage
- GC collection statistics
- Method call counts

### 3a. Test Different Allocators (Optional)

Compare memory allocators without recompiling:

```bash
# Install allocators
# macOS:
brew install jemalloc mimalloc

# Linux:
sudo apt install libjemalloc-dev libmimalloc-dev

# Test each allocator
./scripts/run_with_allocator.sh --allocator=standard -t ../trace_output/trace -m explicit
./scripts/run_with_allocator.sh --allocator=jemalloc -t ../trace_output/trace -m explicit
./scripts/run_with_allocator.sh --allocator=mimalloc -t ../trace_output/trace -m explicit

# Compare all allocators automatically
./scripts/compare_allocators.sh -t ../trace_output/trace -m explicit
```

See `docs/ALLOCATORS.md` for details on using jemalloc, mimalloc, and other allocators.

### 4. Run gem5 Simulation

#### Option A: Using Docker (Recommended)

```bash
# Set your gem5 Docker image (or use default)
export GEM5_DOCKER_IMAGE="gcr.io/gem5-test/gem5:latest"

# Run simulation
./scripts/run_in_docker.sh -t trace_output/trace -c timing
```

#### Option B: Local gem5 Installation

```bash
# Set gem5 installation path
export GEM5_PATH="/path/to/gem5"

# Run simulation
./scripts/run_simulation.sh -t ../trace_output/trace -c timing
```

Available CPU types:
- `atomic`: Atomic CPU (fastest, least accurate)
- `timing`: Timing simple CPU (good balance)
- `o3`: Out-of-order CPU (most detailed, slowest)

### 5. Analyze Results

After both simulations complete:

```bash
python3 scripts/analyze_results.py \
    results/explicit_20241111_204530 \
    results/gc_20241111_204530 \
    --plot
```

This generates:
- Console output with detailed comparisons
- `comparison_report.txt`: Text report
- `plots/`: Visualization graphs (if matplotlib available)

## Trace File Format

The replayer understands Elephant Tracks format with Merlin death records:

```
N <obj-id> <size> <type-id> <site-id> <length> <thread-id>  # Object allocation
A <obj-id> <size> <type-id> <site-id> <length> <thread-id>  # Array allocation
D <obj-id> <thread-id> <timestamp>                           # Object death
U <tgt-obj-id> <src-obj-id> <field-id> <thread-id>          # Field update
M <method-id> <receiver-obj-id> <thread-id>                  # Method entry
E <method-id> <thread-id>                                    # Method exit
```

## Configuration Options

### TraceReplayer Options

```bash
trace_replayer <trace-file> <mode> [options]

Modes:
  explicit  - Explicit memory management (malloc/free)
  gc        - Garbage collection simulation

Options:
  --verbose           Enable verbose output
  --gc-threshold=N    GC heap threshold in bytes (default: 10MB)
  --gc-alloc-count=N  GC after N allocations (default: 1000)
```

### gem5 Configuration Options

```bash
run_simulation.sh -t TRACE_FILE [OPTIONS]

Options:
  -c CPU_TYPE         CPU type: atomic, timing, o3 (default: timing)
  -f CPU_CLOCK        CPU clock frequency (default: 3GHz)
  -m MEM_SIZE         Memory size (default: 8GB)
  --l1i SIZE          L1 instruction cache size (default: 32kB)
  --l1d SIZE          L1 data cache size (default: 32kB)
  --l2 SIZE           L2 cache size (default: 256kB)
  --gc-threshold N    GC threshold in bytes (default: 10485760)
  --gc-alloc N        GC after N allocations (default: 1000)
  -v                  Verbose output
```

## Metrics Compared

The analysis compares:

### Performance Metrics
- Total execution cycles
- Simulated time
- Instructions per cycle (IPC)
- Total instructions committed

### Cache Behavior
- L1 data/instruction cache hit rates
- L2 cache hit rates
- Cache miss penalties
- Average miss latency

### Memory Bandwidth
- Total bytes read from memory
- Total bytes written to memory
- Memory bandwidth utilization
- Read/write ratios

### GC-Specific Metrics
- Number of GC collections
- Total GC pause time
- Average GC pause duration
- Memory reclaimed per collection

## Example Workflow: DaCapo Benchmarks

```bash
# 1. Generate trace for DaCapo benchmark
cd /Users/luka/Desktop/Honors_Thesis/et2-java
java -javaagent:javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar \
     -jar dacapo-9.12-bach.jar avrora -s small

# This creates dacapo_traces/trace

# 2. Copy trace to simulation directory
cp dacapo_traces/trace gem5-simulation/traces/avrora_small.trace

# 3. Test locally first
cd gem5-simulation
./scripts/test_replayer.sh -t traces/avrora_small.trace -m explicit
./scripts/test_replayer.sh -t traces/avrora_small.trace -m gc

# 4. Run full gem5 simulation (in Docker)
./scripts/run_in_docker.sh -t gem5-simulation/traces/avrora_small.trace -c timing

# 5. Analyze results
python3 scripts/analyze_results.py \
    results/explicit_* \
    results/gc_* \
    --plot \
    --report avrora_comparison.txt
```

## Advanced Usage

### Custom GC Parameters

Experiment with different GC configurations:

```bash
# Aggressive GC (small threshold, frequent collections)
./scripts/run_simulation.sh -t ../trace \
    --gc-threshold 5242880 \   # 5 MB
    --gc-alloc 500

# Lazy GC (large threshold, infrequent collections)
./scripts/run_simulation.sh -t ../trace \
    --gc-threshold 52428800 \  # 50 MB
    --gc-alloc 5000
```

### Different Cache Configurations

Compare with different cache sizes:

```bash
# Small caches (embedded system)
./scripts/run_simulation.sh -t ../trace \
    --l1i 16kB --l1d 16kB --l2 128kB

# Large caches (server)
./scripts/run_simulation.sh -t ../trace \
    --l1i 64kB --l1d 64kB --l2 2MB
```

### Out-of-Order CPU

For more detailed simulation:

```bash
./scripts/run_simulation.sh -t ../trace -c o3
```

Note: O3 CPU is much slower but provides more accurate results.

## Implementation Details

### TraceReplayer.cpp

The replayer implements two memory management strategies:

1. **ExplicitMemoryManager**:
   - `allocate()`: Calls `malloc()` immediately
   - `deallocate()`: Calls `free()` immediately when death record appears
   - Simulates optimal explicit memory management

2. **GCSimulator**:
   - `allocate()`: Calls `malloc()` but tracks dead objects
   - `deallocate()`: Marks object as dead, doesn't free immediately
   - `performGC()`: Sweeps dead objects when threshold reached
   - Simulates mark-sweep garbage collection

Both implementations:
- Touch allocated memory to simulate real access patterns
- Track object graphs for field updates
- Generate identical memory access patterns for fair comparison

### gem5 Configuration

The gem5 config (`memory_comparison_config.py`) sets up:
- Configurable CPU model (atomic, timing, O3)
- Multi-level cache hierarchy (L1I, L1D, L2)
- DDR3 memory controller
- System interconnects

## Troubleshooting

### Build Issues

```bash
# On macOS, if you get linker errors:
g++ -std=c++11 -O3 -o build/trace_replayer src/TraceReplayer.cpp

# On Linux, for static binary:
g++ -std=c++11 -O3 -static -o build/trace_replayer src/TraceReplayer.cpp
```

### gem5 Not Found

```bash
# Check your gem5 path
ls $GEM5_PATH/build/X86/gem5.opt

# Or use Docker
docker pull gcr.io/gem5-test/gem5:latest
```

### Trace File Issues

```bash
# Verify trace format
head -20 trace_output/trace

# Check for death records (D lines)
grep "^D " trace_output/trace | head -5

# If no D records, your ET trace needs Merlin integration
```

## References

- [Elephant Tracks](https://www.cs.tufts.edu/~nr/pubs/et.pdf): Object allocation tracking
- [Merlin Algorithm](https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf): Object death detection
- [gem5 Simulator](https://www.gem5.org/): Full-system architectural simulator
- [DaCapo Benchmarks](https://www.dacapobench.org/): Java benchmark suite

## License

This project is part of an honors thesis at [Your University]. Use for academic purposes.

## Contact

For questions or issues, please contact [Your Name/Email].
