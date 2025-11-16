# Memory Allocator Support

## Overview

The TraceReplayer supports multiple memory allocators to provide more realistic comparisons between explicit memory management and garbage collection. Different allocators have different performance characteristics, fragmentation behaviors, and memory overhead.

## Quick Start - Easy Method (Recommended)

**You don't need to recompile!** Use dynamic linking to test different allocators:

```bash
# Build the standard version once
make

# Run with different allocators using preloading
./scripts/run_with_allocator.sh --allocator=standard -t ../trace_output/trace -m explicit
./scripts/run_with_allocator.sh --allocator=jemalloc -t ../trace_output/trace -m explicit
./scripts/run_with_allocator.sh --allocator=mimalloc -t ../trace_output/trace -m explicit

# Compare all allocators
./scripts/compare_allocators.sh -t ../trace_output/trace -m explicit
```

This uses `LD_PRELOAD` (Linux) or `DYLD_INSERT_LIBRARIES` (macOS) to replace malloc/free at runtime without code changes.

## Two Approaches

### 1. Dynamic Linking (Easier - Recommended)
- Build once with standard malloc
- Switch allocators at runtime using environment variables
- No recompilation needed
- Easier to test multiple allocators

### 2. Static Linking (For gem5)
- Compile separate binaries for each allocator
- Required for static binaries (e.g., gem5 simulation)
- More control but requires rebuilding

## Supported Allocators

### 1. Standard libc malloc (Default)

**Description**: System-provided malloc/free implementation.

**Characteristics**:
- Available on all systems
- Performance varies by platform (ptmalloc2 on Linux, Apple's malloc on macOS)
- Moderate fragmentation
- No special tuning options

**When to use**: Baseline comparisons, portability requirements

**Build**:
```bash
make standard
# or
make -f Makefile.enhanced standard
```

**Run**:
```bash
./build/trace_replayer trace.txt explicit
```

---

### 2. mimalloc (Recommended for Performance)

**Description**: Microsoft's high-performance allocator optimized for modern multi-threaded workloads.

**Characteristics**:
- Excellent performance (often 2-5x faster than system malloc)
- Low fragmentation through segregated free lists
- Thread-local caches reduce contention
- Detailed statistics available
- Optimized for small to medium allocations (typical for Java objects)

**When to use**: 
- Performance-focused benchmarks
- Modern hardware with multiple cores
- Workloads with many small allocations
- Need detailed allocation statistics

**Installation**:

macOS:
```bash
brew install mimalloc
```

Ubuntu/Debian:
```bash
sudo apt-get install libmimalloc-dev
```

Fedora/RHEL:
```bash
sudo yum install mimalloc-devel
```

From source:
```bash
git clone https://github.com/microsoft/mimalloc.git
cd mimalloc
mkdir build && cd build
cmake ..
make -j
sudo make install
```

**Build**:
```bash
make -f Makefile.enhanced mimalloc

# If installed in non-standard location:
make -f Makefile.enhanced mimalloc MIMALLOC_DIR=/opt/mimalloc
```

**Run** (using helper script):
```bash
./scripts/run_with_allocator.sh --allocator=mimalloc -t trace.txt -m explicit
```

**Run** (manual LD_PRELOAD):

Linux:
```bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libmimalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

macOS:
```bash
DYLD_INSERT_LIBRARIES=/usr/local/lib/libmimalloc.dylib \
    ./build/trace_replayer trace.txt explicit
```

**Run** (compiled version):
```bash
./build/trace_replayer_mimalloc trace.txt explicit --allocator=mimalloc

# With statistics:
./build/trace_replayer_mimalloc trace.txt explicit \
    --allocator=mimalloc --allocator-stats
```

**Enable mimalloc statistics**:
```bash
MIMALLOC_SHOW_STATS=1 \
LD_PRELOAD=libmimalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

**Statistics Output**:
mimalloc provides detailed metrics including:
- Heap size and committed pages
- Thread-local cache usage
- Fragmentation ratio
- Peak memory usage
- Large object allocations

---

### 3. jemalloc

**Description**: Facebook's allocator used in production systems like Firefox, Redis, and FreeBSD.

**Characteristics**:
- Excellent scalability for multi-threaded applications
- Low fragmentation through size-class segregation
- Configurable arenas for reduced contention
- Profiling and debugging features
- Good for server workloads

**When to use**:
- Production-like scenarios
- Multi-threaded workloads
- Need memory profiling capabilities
- Comparison with systems like Firefox/Redis

**Installation**:

macOS:
```bash
brew install jemalloc
```

Ubuntu/Debian:
```bash
sudo apt-get install libjemalloc-dev
```

Fedora/RHEL:
```bash
sudo yum install jemalloc-devel
```

From source:
```bash
git clone https://github.com/jemalloc/jemalloc.git
cd jemalloc
./autogen.sh
./configure
make -j
sudo make install
```

**Build**:
```bash
make -f Makefile.enhanced jemalloc

# If installed in non-standard location:
make -f Makefile.enhanced jemalloc JEMALLOC_DIR=/opt/jemalloc
```

**Run** (using helper script):
```bash
./scripts/run_with_allocator.sh --allocator=jemalloc -t trace.txt -m explicit
```

**Run** (manual LD_PRELOAD):

Linux:
```bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

macOS:
```bash
DYLD_INSERT_LIBRARIES=/usr/local/lib/libjemalloc.dylib \
    ./build/trace_replayer trace.txt explicit
```

**Run** (compiled version):
```bash
./build/trace_replayer_jemalloc trace.txt explicit --allocator=jemalloc

# With statistics:
./build/trace_replayer_jemalloc trace.txt explicit \
    --allocator=jemalloc --allocator-stats
```

**Enable jemalloc statistics**:
```bash
MALLOC_CONF="stats_print:true" \
LD_PRELOAD=libjemalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

**Statistics Output**:
jemalloc provides comprehensive statistics:
- Per-arena statistics
- Size class distributions
- Fragmentation metrics
- Allocation/deallocation counts
- Memory maps

---

## Performance Comparison Example

Run all three allocators on the same trace:

```bash
# Build all versions
make -f Makefile.enhanced all-allocators

# Run benchmarks
echo "=== Standard malloc ==="
time ./build/trace_replayer ../trace_output/trace explicit

echo ""
echo "=== mimalloc ==="
time ./build/trace_replayer_mimalloc ../trace_output/trace explicit \
    --allocator=mimalloc

echo ""
echo "=== jemalloc ==="
time ./build/trace_replayer_jemalloc ../trace_output/trace explicit \
    --allocator=jemalloc
```

## Batch Comparison Script

Create a comparison script:

```bash
#!/bin/bash
# compare_allocators.sh

TRACE_FILE="$1"

if [ -z "$TRACE_FILE" ]; then
    echo "Usage: $0 <trace-file>"
    exit 1
fi

RESULTS_DIR="allocator_comparison_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "Running allocator comparison..."
echo "Trace: $TRACE_FILE"
echo "Results: $RESULTS_DIR"
echo ""

# Test each allocator
for alloc in standard mimalloc jemalloc; do
    echo "Testing $alloc..."
    
    BINARY="./build/trace_replayer"
    ALLOC_OPT=""
    
    if [ "$alloc" != "standard" ]; then
        BINARY="./build/trace_replayer_${alloc}"
        ALLOC_OPT="--allocator=${alloc} --allocator-stats"
    fi
    
    if [ -f "$BINARY" ]; then
        /usr/bin/time -l $BINARY "$TRACE_FILE" explicit $ALLOC_OPT \
            > "$RESULTS_DIR/${alloc}_explicit.txt" 2>&1
        
        /usr/bin/time -l $BINARY "$TRACE_FILE" gc $ALLOC_OPT \
            > "$RESULTS_DIR/${alloc}_gc.txt" 2>&1
        
        echo "  Complete: $RESULTS_DIR/${alloc}_*.txt"
    else
        echo "  Skipped: $BINARY not found"
    fi
done

echo ""
echo "Comparison complete. Results in: $RESULTS_DIR"
```

## gem5 Integration

To use custom allocators with gem5:

### Option 1: Build Replayer with Allocator

```bash
# Build with mimalloc (statically linked for gem5)
g++ -std=c++11 -O3 -static -DUSE_MIMALLOC \
    -I/usr/local/include \
    -o build/trace_replayer_mimalloc \
    src/TraceReplayerEnhanced.cpp \
    -L/usr/local/lib -lmimalloc -lpthread
```

### Option 2: Update gem5 Config

Modify `configs/memory_comparison_config.py`:

```python
# Set binary based on allocator choice
parser.add_argument('--allocator', type=str, default='standard',
                    choices=['standard', 'mimalloc', 'jemalloc'],
                    help='Memory allocator to use')

# In workload setup:
if args.allocator != 'standard':
    binary = f'{args.binary}_{args.allocator}'
    cmd.append(f'--allocator={args.allocator}')
```

Run gem5 with specific allocator:

```bash
./scripts/run_simulation.sh -t ../trace \
    --allocator mimalloc
```

## Allocator Selection Guide

### Choose **Standard malloc** when:
- Maximum portability required
- Baseline measurements needed
- Testing on multiple platforms

### Choose **mimalloc** when:
- Performance is critical
- Running on modern hardware
- Need detailed allocation statistics
- Typical Java-like workload (many small objects)
- Memory bandwidth is a bottleneck

### Choose **jemalloc** when:
- Multi-threaded scalability is important
- Need profiling/debugging features
- Comparing with real-world systems (Firefox, Redis)
- Server-like workloads
- Need tunable arena configuration

## Expected Performance Differences

Based on typical workloads:

| Metric | Standard | mimalloc | jemalloc |
|--------|----------|----------|----------|
| Allocation Speed | 1.0x | 2-5x | 1.5-3x |
| Deallocation Speed | 1.0x | 2-4x | 1.5-2.5x |
| Memory Overhead | Medium | Low | Low-Medium |
| Fragmentation | Medium | Low | Low |
| Thread Scalability | Poor | Excellent | Excellent |
| Cache Friendliness | Medium | Excellent | Good |

## Interpreting Statistics

### mimalloc Statistics

Key metrics to watch:
```
heap stats:  peak      total      freed
  normal:     10MB      50MB       45MB    # Regular allocations
  large:       2MB       5MB        4MB    # Large object heap
```

- High "freed/total" ratio indicates good memory reuse
- Large "peak" suggests high memory pressure
- "large" allocations show array/large object behavior

### jemalloc Statistics

Key metrics:
```
Allocated: 50MB, active: 52MB, mapped: 60MB
```

- `allocated`: Actually used by application
- `active`: Includes internal fragmentation
- `mapped`: Total virtual memory
- `(active - allocated)` shows fragmentation
- `(mapped - active)` shows retained pages

## Troubleshooting

### mimalloc not found

```bash
# Check installation
ls /usr/local/include/mimalloc.h
ls /usr/local/lib/libmimalloc.*

# If not found, install or set MIMALLOC_DIR
make -f Makefile.enhanced mimalloc MIMALLOC_DIR=/path/to/mimalloc
```

### jemalloc linking errors

```bash
# Verify jemalloc installation
pkg-config --cflags --libs jemalloc

# Use pkg-config for build
g++ ... $(pkg-config --cflags --libs jemalloc)
```

### Static linking issues

For gem5, you need static libraries:

```bash
# mimalloc
cmake -DMI_BUILD_STATIC=ON ..

# jemalloc
./configure --enable-static
```

## References

- [mimalloc GitHub](https://github.com/microsoft/mimalloc)
- [mimalloc Paper](https://www.microsoft.com/en-us/research/publication/mimalloc-free-list-sharding-in-action/)
- [jemalloc GitHub](https://github.com/jemalloc/jemalloc)
- [jemalloc Paper](https://people.freebsd.org/~jasone/jemalloc/bsdcan2006/jemalloc.pdf)
- [Allocator Benchmarks](https://github.com/daanx/mimalloc-bench)
