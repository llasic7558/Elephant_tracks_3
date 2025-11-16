#!/bin/bash
#
# Run simulation in gem5 Docker container
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default parameters
DOCKER_IMAGE="${GEM5_DOCKER_IMAGE:-gcr.io/gem5-test/gem5:latest}"
TRACE_FILE=""
CONTAINER_NAME="gem5-memory-sim"
CPU_TYPE="timing"
EXTRA_ARGS=""

usage() {
    echo "Usage: $0 -t TRACE_FILE [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -t TRACE_FILE       Path to ET trace file (relative to project root)"
    echo ""
    echo "Options:"
    echo "  -i IMAGE            Docker image (default: gcr.io/gem5-test/gem5:latest)"
    echo "  -n NAME             Container name (default: gem5-memory-sim)"
    echo "  -c CPU_TYPE         CPU type: atomic, timing, o3 (default: timing)"
    echo "  -e ARGS             Extra arguments to pass to simulation"
    echo "  -h                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -t trace_output/trace"
    echo "  $0 -t trace_output/trace -c o3 -e \"--l2 512kB\""
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t)
            TRACE_FILE="$2"
            shift 2
            ;;
        -i)
            DOCKER_IMAGE="$2"
            shift 2
            ;;
        -n)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -c)
            CPU_TYPE="$2"
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

if [ -z "$TRACE_FILE" ]; then
    echo "Error: Trace file is required (-t option)"
    usage
fi

# Convert to absolute path
cd "$PROJECT_ROOT/.."
WORKSPACE_ROOT=$(pwd)
cd - > /dev/null

TRACE_PATH="$WORKSPACE_ROOT/$TRACE_FILE"
if [ ! -f "$TRACE_PATH" ]; then
    echo "Error: Trace file not found: $TRACE_PATH"
    exit 1
fi

echo "=== Running gem5 Simulation in Docker ==="
echo "Docker image:   $DOCKER_IMAGE"
echo "Container name: $CONTAINER_NAME"
echo "Workspace:      $WORKSPACE_ROOT"
echo "Trace file:     $TRACE_FILE"
echo "CPU type:       $CPU_TYPE"
echo ""

# Stop and remove existing container if it exists
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

# Build the replayer first (on host if possible, or in container)
echo "Building TraceReplayer..."
cd "$PROJECT_ROOT"
if [ -f "scripts/build.sh" ]; then
    ./scripts/build.sh
fi
cd - > /dev/null

# Run Docker container
echo ""
echo "Starting Docker container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -v "$WORKSPACE_ROOT:/workspace" \
    -w /workspace/et2-java/gem5-simulation \
    "$DOCKER_IMAGE" \
    tail -f /dev/null

echo "Container started: $CONTAINER_NAME"

# Build in container if not built on host (for static linking)
echo ""
echo "Building in container for gem5 compatibility..."
docker exec "$CONTAINER_NAME" bash -c "
    cd /workspace/et2-java/gem5-simulation
    g++ -std=c++11 -O3 -static -o build/trace_replayer src/TraceReplayer.cpp
"

# Run explicit mode simulation
echo ""
echo "=========================================="
echo "Running Explicit Memory Management Mode"
echo "=========================================="

docker exec "$CONTAINER_NAME" bash -c "
    cd /workspace/et2-java/gem5-simulation
    GEM5_PATH=/gem5 ./scripts/run_simulation.sh \
        -t /workspace/$TRACE_FILE \
        -c $CPU_TYPE \
        $EXTRA_ARGS \
        2>&1 | head -100
"

echo ""
echo "Simulations completed!"
echo ""

# Find latest results
RESULTS_DIR="$PROJECT_ROOT/results"
LATEST_EXPLICIT=$(ls -td "$RESULTS_DIR"/explicit_* 2>/dev/null | head -1)
LATEST_GC=$(ls -td "$RESULTS_DIR"/gc_* 2>/dev/null | head -1)

if [ -n "$LATEST_EXPLICIT" ] && [ -n "$LATEST_GC" ]; then
    echo "Latest results:"
    echo "  Explicit: $LATEST_EXPLICIT"
    echo "  GC:       $LATEST_GC"
    echo ""
    echo "To analyze:"
    echo "  cd $PROJECT_ROOT"
    echo "  python3 scripts/analyze_results.py \\"
    echo "    $LATEST_EXPLICIT \\"
    echo "    $LATEST_GC \\"
    echo "    --plot"
fi

# Ask user if they want to stop the container
echo ""
read -p "Stop Docker container? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
    echo "Container stopped and removed"
else
    echo "Container still running: $CONTAINER_NAME"
    echo "To access: docker exec -it $CONTAINER_NAME /bin/bash"
    echo "To stop: docker stop $CONTAINER_NAME"
fi
