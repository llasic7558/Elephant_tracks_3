# Quick Reference: Using Different Allocators

## The Easy Way (Recommended)

### Why LD_PRELOAD?

As explained in the [jemalloc documentation](https://github.com/jemalloc/jemalloc/wiki/getting-started), you can use jemalloc (and mimalloc) **without modifying your code**:

- No recompilation needed
- No code changes required
- Switch allocators instantly
- Test multiple allocators easily

### Installation

**macOS**:
```bash
brew install jemalloc mimalloc
```

**Ubuntu/Debian**:
```bash
sudo apt install libjemalloc-dev libmimalloc-dev
```

**Fedora/RHEL**:
```bash
sudo yum install jemalloc-devel mimalloc-devel
```

### Usage

#### Option 1: Helper Script (Easiest)

```bash
# Build once
make

# Run with different allocators
./scripts/run_with_allocator.sh --allocator=standard -t trace.txt -m explicit
./scripts/run_with_allocator.sh --allocator=jemalloc -t trace.txt -m explicit
./scripts/run_with_allocator.sh --allocator=mimalloc -t trace.txt -m explicit

# Compare all
./scripts/compare_allocators.sh -t trace.txt -m explicit
```

#### Option 2: Manual LD_PRELOAD

**Linux**:
```bash
# jemalloc
LD_PRELOAD=libjemalloc.so.2 ./build/trace_replayer trace.txt explicit

# mimalloc
LD_PRELOAD=libmimalloc.so.2 ./build/trace_replayer trace.txt explicit

# With statistics
MALLOC_CONF="stats_print:true" \
LD_PRELOAD=libjemalloc.so.2 \
    ./build/trace_replayer trace.txt explicit
```

**macOS**:
```bash
# jemalloc
DYLD_INSERT_LIBRARIES=/usr/local/lib/libjemalloc.dylib \
    ./build/trace_replayer trace.txt explicit

# mimalloc
DYLD_INSERT_LIBRARIES=/usr/local/lib/libmimalloc.dylib \
    ./build/trace_replayer trace.txt explicit

# With statistics
MIMALLOC_SHOW_STATS=1 \
DYLD_INSERT_LIBRARIES=/usr/local/lib/libmimalloc.dylib \
    ./build/trace_replayer trace.txt explicit
```

## Comparison Example

```bash
#!/bin/bash
# quick_compare.sh

TRACE="../trace_output/trace"

echo "=== Standard libc malloc ==="
time ./build/trace_replayer "$TRACE" explicit | grep "Peak Memory"

echo ""
echo "=== jemalloc ==="
time LD_PRELOAD=libjemalloc.so.2 \
    ./build/trace_replayer "$TRACE" explicit | grep "Peak Memory"

echo ""
echo "=== mimalloc ==="
time LD_PRELOAD=libmimalloc.so.2 \
    ./build/trace_replayer "$TRACE" explicit | grep "Peak Memory"
```

## Environment Variables

### jemalloc
```bash
# Enable statistics
export MALLOC_CONF="stats_print:true"

# Configure background threads
export MALLOC_CONF="background_thread:true,stats_print:true"

# Profiling
export MALLOC_CONF="prof:true,prof_prefix:jeprof.out"
```

### mimalloc
```bash
# Show statistics at exit
export MIMALLOC_SHOW_STATS=1

# Verbose output
export MIMALLOC_VERBOSE=1

# Show errors
export MIMALLOC_SHOW_ERRORS=1

# Page reset (impacts performance)
export MIMALLOC_PAGE_RESET=0
```

## When to Use Each Method

### Use LD_PRELOAD when:
- ✅ Quick testing and comparisons
- ✅ Running on native OS (not in gem5)
- ✅ Want to test multiple allocators
- ✅ Dynamic linking available

### Use Static Compilation when:
- ✅ Running in gem5 simulator
- ✅ Need portable static binary
- ✅ Debugging allocator-specific issues
- ✅ Production deployment

## Troubleshooting

### Library not found

**Find library location**:
```bash
# Linux
find /usr/lib /usr/local/lib -name "libjemalloc*"
find /usr/lib /usr/local/lib -name "libmimalloc*"

# macOS
find /usr/local/lib /opt/homebrew/lib -name "libjemalloc*"
find /usr/local/lib /opt/homebrew/lib -name "libmimalloc*"
```

**Set explicit path**:
```bash
# Linux
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ./build/trace_replayer ...

# macOS
DYLD_INSERT_LIBRARIES=/opt/homebrew/lib/libjemalloc.dylib ./build/trace_replayer ...
```

### macOS Security (SIP)

If you get errors on macOS about system integrity:

```bash
# Check if SIP is enabled
csrutil status

# For system binaries, use static linking instead
make -f Makefile.enhanced jemalloc
./build/trace_replayer_jemalloc trace.txt explicit
```

### Verify allocator is being used

```bash
# Check which libraries are loaded
ldd ./build/trace_replayer  # Linux
otool -L ./build/trace_replayer  # macOS

# Run with verbose output
LD_DEBUG=libs LD_PRELOAD=libjemalloc.so.2 ./build/trace_replayer ...  # Linux
```

## Performance Tips

### jemalloc
- Good for multi-threaded workloads
- Configure number of arenas: `MALLOC_CONF="narenas:4"`
- Enable background threads for better performance

### mimalloc
- Excellent for single-threaded or moderate multi-threading
- Very low overhead
- Faster for small allocations (typical Java objects)
- Use `MIMALLOC_PAGE_RESET=0` for maximum speed

### Measurements
```bash
# Use system time for accurate measurements
/usr/bin/time -v ./build/trace_replayer ...  # Linux
/usr/bin/time -l ./build/trace_replayer ...  # macOS

# Multiple runs for accuracy
for i in {1..5}; do
    echo "Run $i:"
    LD_PRELOAD=libjemalloc.so.2 ./build/trace_replayer ...
done
```

## References

- [jemalloc Getting Started](https://github.com/jemalloc/jemalloc/wiki/getting-started)
- [jemalloc Configuration](https://github.com/jemalloc/jemalloc/wiki/use)
- [mimalloc Documentation](https://microsoft.github.io/mimalloc/)
- [LD_PRELOAD Tutorial](https://blog.jessfraz.com/post/ld_preload/)

## See Also

- `docs/ALLOCATORS.md` - Detailed allocator documentation
- `Makefile.enhanced` - Static compilation options
- `scripts/run_with_allocator.sh` - Helper script source
- `scripts/compare_allocators.sh` - Comparison script source
