#!/bin/bash
#
# Run TraceReplayer with different memory allocators using LD_PRELOAD/DYLD_INSERT_LIBRARIES
# This is easier than recompiling with allocator support
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BINARY="$PROJECT_ROOT/build/trace_replayer"

# Detect OS
UNAME_S=$(uname -s)

# Arguments
ALLOCATOR=""
TRACE_FILE=""
MODE="explicit"
EXTRA_ARGS=""

usage() {
    echo "Usage: $0 --allocator=ALLOCATOR -t TRACE_FILE -m MODE [OPTIONS]"
    echo ""
    echo "Run TraceReplayer with different allocators via dynamic linking"
    echo ""
    echo "Required:"
    echo "  --allocator=NAME  Allocator: standard, mimalloc, jemalloc"
    echo "  -t TRACE_FILE     Path to ET trace file"
    echo "  -m MODE           Mode: explicit or gc"
    echo ""
    echo "Optional:"
    echo "  -e ARGS           Extra arguments to pass to replayer"
    echo "  -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --allocator=jemalloc -t ../trace_output/trace -m explicit"
    echo "  $0 --allocator=mimalloc -t ../trace_output/trace -m gc -e \"--verbose\""
    echo ""
    echo "Note: Allocator libraries must be installed:"
    echo "  macOS:  brew install jemalloc mimalloc"
    echo "  Linux:  apt install libjemalloc-dev libmimalloc-dev"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --allocator=*)
            ALLOCATOR="${1#*=}"
            shift
            ;;
        -t)
            TRACE_FILE="$2"
            shift 2
            ;;
        -m)
            MODE="$2"
            shift 2
            ;;
        -e)
            EXTRA_ARGS="$2"
            shift 2
            ;;
        -h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$ALLOCATOR" ] || [ -z "$TRACE_FILE" ] || [ -z "$MODE" ]; then
    echo "Error: Missing required arguments"
    usage
fi

if [ ! -f "$BINARY" ]; then
    echo "Error: TraceReplayer binary not found: $BINARY"
    echo "Build it with: make"
    exit 1
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: Trace file not found: $TRACE_FILE"
    exit 1
fi

echo "=== Running with $ALLOCATOR allocator ==="
echo "Binary:     $BINARY"
echo "Trace:      $TRACE_FILE"
echo "Mode:       $MODE"
echo "Extra args: $EXTRA_ARGS"
echo ""

# Function to find library
find_library() {
    local LIB_NAME=$1
    local SEARCH_PATHS=(
        "/usr/local/lib"
        "/usr/lib"
        "/opt/homebrew/lib"
        "/usr/lib/x86_64-linux-gnu"
    )
    
    for path in "${SEARCH_PATHS[@]}"; do
        if [ -f "$path/$LIB_NAME" ]; then
            echo "$path/$LIB_NAME"
            return 0
        fi
    done
    
    return 1
}

# Set up environment based on allocator
case "$ALLOCATOR" in
    standard)
        echo "Using standard libc allocator (no preload)"
        ;;
        
    jemalloc)
        if [ "$UNAME_S" = "Darwin" ]; then
            # macOS
            JEMALLOC_LIB=$(find_library "libjemalloc.dylib")
            if [ -z "$JEMALLOC_LIB" ]; then
                JEMALLOC_LIB=$(find_library "libjemalloc.2.dylib")
            fi
            
            if [ -z "$JEMALLOC_LIB" ]; then
                echo "Error: jemalloc not found"
                echo "Install with: brew install jemalloc"
                exit 1
            fi
            
            echo "Found jemalloc: $JEMALLOC_LIB"
            export DYLD_INSERT_LIBRARIES="$JEMALLOC_LIB"
            
        elif [ "$UNAME_S" = "Linux" ]; then
            # Linux
            JEMALLOC_LIB=$(find_library "libjemalloc.so.2")
            if [ -z "$JEMALLOC_LIB" ]; then
                JEMALLOC_LIB=$(find_library "libjemalloc.so")
            fi
            
            if [ -z "$JEMALLOC_LIB" ]; then
                echo "Error: jemalloc not found"
                echo "Install with: sudo apt install libjemalloc-dev"
                exit 1
            fi
            
            echo "Found jemalloc: $JEMALLOC_LIB"
            export LD_PRELOAD="$JEMALLOC_LIB"
        fi
        
        # Enable jemalloc statistics
        export MALLOC_CONF="stats_print:true"
        ;;
        
    mimalloc)
        if [ "$UNAME_S" = "Darwin" ]; then
            # macOS
            MIMALLOC_LIB=$(find_library "libmimalloc.dylib")
            if [ -z "$MIMALLOC_LIB" ]; then
                MIMALLOC_LIB=$(find_library "libmimalloc.2.dylib")
            fi
            
            if [ -z "$MIMALLOC_LIB" ]; then
                echo "Error: mimalloc not found"
                echo "Install with: brew install mimalloc"
                exit 1
            fi
            
            echo "Found mimalloc: $MIMALLOC_LIB"
            export DYLD_INSERT_LIBRARIES="$MIMALLOC_LIB"
            
        elif [ "$UNAME_S" = "Linux" ]; then
            # Linux
            MIMALLOC_LIB=$(find_library "libmimalloc.so.2")
            if [ -z "$MIMALLOC_LIB" ]; then
                MIMALLOC_LIB=$(find_library "libmimalloc.so")
            fi
            
            if [ -z "$MIMALLOC_LIB" ]; then
                echo "Error: mimalloc not found"
                echo "Install with: sudo apt install libmimalloc-dev"
                exit 1
            fi
            
            echo "Found mimalloc: $MIMALLOC_LIB"
            export LD_PRELOAD="$MIMALLOC_LIB"
        fi
        
        # Enable mimalloc statistics
        export MIMALLOC_SHOW_STATS=1
        export MIMALLOC_VERBOSE=1
        ;;
        
    *)
        echo "Error: Unknown allocator: $ALLOCATOR"
        echo "Valid options: standard, jemalloc, mimalloc"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Starting simulation..."
echo "=========================================="
echo ""

# Run the program
$BINARY "$TRACE_FILE" "$MODE" $EXTRA_ARGS

EXIT_CODE=$?

echo ""
echo "=========================================="
echo "Simulation complete (exit code: $EXIT_CODE)"
echo "=========================================="

exit $EXIT_CODE
