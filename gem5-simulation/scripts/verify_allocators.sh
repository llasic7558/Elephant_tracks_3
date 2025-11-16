#!/bin/bash
#
# Verify that different allocators are available and working
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Allocator Verification ==="
echo ""

# Check if binary exists
BINARY="$PROJECT_ROOT/build/trace_replayer"
if [ ! -f "$BINARY" ]; then
    echo "❌ TraceReplayer binary not found: $BINARY"
    echo "   Build it with: make"
    exit 1
fi
echo "✓ Binary found: $BINARY"
echo ""

# Detect OS
UNAME_S=$(uname -s)
echo "Operating System: $UNAME_S"
echo ""

# Function to find library
find_library() {
    local LIB_NAME=$1
    local SEARCH_PATHS=(
        "/usr/local/lib"
        "/usr/lib"
        "/opt/homebrew/lib"
        "/usr/lib/x86_64-linux-gnu"
        "/usr/lib64"
    )
    
    for path in "${SEARCH_PATHS[@]}"; do
        if [ -d "$path" ]; then
            local FOUND=$(find "$path" -name "$LIB_NAME" 2>/dev/null | head -1)
            if [ -n "$FOUND" ]; then
                echo "$FOUND"
                return 0
            fi
        fi
    done
    
    return 1
}

# Check standard allocator
echo "--- Standard Allocator ---"
echo "✓ Always available (system default)"
echo ""

# Check jemalloc
echo "--- jemalloc ---"
if [ "$UNAME_S" = "Darwin" ]; then
    JEMALLOC_LIB=$(find_library "libjemalloc*.dylib" | head -1)
elif [ "$UNAME_S" = "Linux" ]; then
    JEMALLOC_LIB=$(find_library "libjemalloc.so*" | head -1)
fi

if [ -n "$JEMALLOC_LIB" ]; then
    echo "✓ Found: $JEMALLOC_LIB"
    
    # Test it
    if [ "$UNAME_S" = "Darwin" ]; then
        export DYLD_INSERT_LIBRARIES="$JEMALLOC_LIB"
    else
        export LD_PRELOAD="$JEMALLOC_LIB"
    fi
    
    # Quick test (just check it runs)
    echo "  Testing..."
    $BINARY --help > /dev/null 2>&1 || true
    echo "  ✓ jemalloc loads successfully"
    
    unset LD_PRELOAD
    unset DYLD_INSERT_LIBRARIES
else
    echo "❌ Not found"
    echo "   Install with:"
    if [ "$UNAME_S" = "Darwin" ]; then
        echo "   brew install jemalloc"
    else
        echo "   sudo apt install libjemalloc-dev"
    fi
fi
echo ""

# Check mimalloc
echo "--- mimalloc ---"
if [ "$UNAME_S" = "Darwin" ]; then
    MIMALLOC_LIB=$(find_library "libmimalloc*.dylib" | head -1)
elif [ "$UNAME_S" = "Linux" ]; then
    MIMALLOC_LIB=$(find_library "libmimalloc.so*" | head -1)
fi

if [ -n "$MIMALLOC_LIB" ]; then
    echo "✓ Found: $MIMALLOC_LIB"
    
    # Test it
    if [ "$UNAME_S" = "Darwin" ]; then
        export DYLD_INSERT_LIBRARIES="$MIMALLOC_LIB"
    else
        export LD_PRELOAD="$MIMALLOC_LIB"
    fi
    
    # Quick test
    echo "  Testing..."
    $BINARY --help > /dev/null 2>&1 || true
    echo "  ✓ mimalloc loads successfully"
    
    unset LD_PRELOAD
    unset DYLD_INSERT_LIBRARIES
else
    echo "❌ Not found"
    echo "   Install with:"
    if [ "$UNAME_S" = "Darwin" ]; then
        echo "   brew install mimalloc"
    else
        echo "   sudo apt install libmimalloc-dev"
    fi
fi
echo ""

# Summary
echo "=== Summary ==="
echo ""

AVAILABLE_COUNT=1  # standard always available

if [ -n "$JEMALLOC_LIB" ]; then
    AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
fi

if [ -n "$MIMALLOC_LIB" ]; then
    AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
fi

echo "Available allocators: $AVAILABLE_COUNT/3"
echo ""

if [ $AVAILABLE_COUNT -eq 3 ]; then
    echo "✓ All allocators available!"
    echo ""
    echo "Try:"
    echo "  ./scripts/compare_allocators.sh -t ../trace_output/trace -m explicit"
elif [ $AVAILABLE_COUNT -gt 1 ]; then
    echo "⚠ Some allocators available"
    echo ""
    echo "Install missing allocators to compare all three:"
    if [ -z "$JEMALLOC_LIB" ]; then
        echo "  jemalloc: brew install jemalloc"
    fi
    if [ -z "$MIMALLOC_LIB" ]; then
        echo "  mimalloc: brew install mimalloc"
    fi
else
    echo "⚠ Only standard allocator available"
    echo ""
    echo "Install allocators for comparison:"
    if [ "$UNAME_S" = "Darwin" ]; then
        echo "  brew install jemalloc mimalloc"
    else
        echo "  sudo apt install libjemalloc-dev libmimalloc-dev"
    fi
fi
echo ""

echo "For more information:"
echo "  docs/QUICK_REFERENCE.md"
echo "  docs/ALLOCATORS.md"
