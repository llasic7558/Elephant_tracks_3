# Using jemalloc and mimalloc - Simple Guide

## TL;DR

**You don't need to modify code or recompile!** Just use environment variables:

```bash
# Build once
make

# Run with jemalloc
LD_PRELOAD=libjemalloc.so.2 ./build/trace_replayer trace.txt explicit

# Run with mimalloc  
LD_PRELOAD=libmimalloc.so.2 ./build/trace_replayer trace.txt explicit

# Compare all allocators automatically
./scripts/compare_allocators.sh -t trace.txt -m explicit
```

## Installation

```bash
# macOS
brew install jemalloc mimalloc

# Linux
sudo apt install libjemalloc-dev libmimalloc-dev
```

## Why Use Different Allocators?

Different allocators have different characteristics:

| Allocator | Best For | Speed | Fragmentation | Notes |
|-----------|----------|-------|---------------|-------|
| **standard** | Baseline | 1x | Medium | System default |
| **mimalloc** | Performance | 2-5x | Low | Best for Java-like workloads |
| **jemalloc** | Scalability | 1.5-3x | Low | Used by Firefox, Redis |

## Quick Start

### 1. Test a Single Allocator

```bash
./scripts/run_with_allocator.sh --allocator=mimalloc \
    -t ../trace_output/trace -m explicit
```

### 2. Compare All Allocators

```bash
./scripts/compare_allocators.sh -t ../trace_output/trace -m explicit
```

This generates a report comparing:
- Execution time
- Peak memory usage
- Total allocations
- GC statistics (if in GC mode)

### 3. Manual Testing

Linux:
```bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    ./build/trace_replayer ../trace_output/trace explicit
```

macOS:
```bash
DYLD_INSERT_LIBRARIES=/usr/local/lib/libjemalloc.dylib \
    ./build/trace_replayer ../trace_output/trace explicit
```

## Get Statistics

### jemalloc Stats
```bash
MALLOC_CONF="stats_print:true" \
LD_PRELOAD=libjemalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

### mimalloc Stats
```bash
MIMALLOC_SHOW_STATS=1 \
LD_PRELOAD=libmimalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

## How It Works

The `LD_PRELOAD` (Linux) or `DYLD_INSERT_LIBRARIES` (macOS) environment variable tells the dynamic linker to load a specific library before any others. This replaces `malloc()`, `free()`, and related functions with the allocator's implementation.

**Advantages**:
- No code changes
- No recompilation
- Easy to switch between allocators
- Can test with any binary

**Limitations**:
- Doesn't work with statically linked binaries
- May have issues with macOS System Integrity Protection (SIP)
- For gem5, you need static linking

## For gem5 Simulation

When running in gem5, you need static binaries:

```bash
# Build statically linked versions
make -f Makefile.enhanced all-allocators

# Use in gem5
./scripts/run_simulation.sh -t trace --binary trace_replayer_mimalloc
```

## Documentation

- **Quick Reference**: `docs/QUICK_REFERENCE.md`
- **Detailed Guide**: `docs/ALLOCATORS.md`
- **Main README**: `README.md`

## Credits

This simplified approach is based on the [jemalloc getting started guide](https://github.com/jemalloc/jemalloc/wiki/getting-started).
