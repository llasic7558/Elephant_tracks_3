# Makefile for gem5 Memory Management Comparison

CXX = g++
CXXFLAGS = -std=c++11 -O3 -Wall -Wextra
LDFLAGS = 

# Detect OS for static linking on Linux
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    LDFLAGS += -static
endif

# Directories
SRC_DIR = src
BUILD_DIR = build
SCRIPT_DIR = scripts

# Target binary
TARGET = $(BUILD_DIR)/trace_replayer

# Source files
SOURCES = $(SRC_DIR)/TraceReplayer.cpp
OBJECTS = $(SOURCES:$(SRC_DIR)/%.cpp=$(BUILD_DIR)/%.o)

# Default target
all: $(TARGET)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build target
$(TARGET): $(SOURCES) | $(BUILD_DIR)
	@echo "Building TraceReplayer..."
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)
	@echo "Build complete: $@"
	@ls -lh $@

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	@echo "Clean complete"

# Test with a trace file
test: $(TARGET)
	@echo "Running test..."
	@if [ -f "../trace_output/trace" ]; then \
		$(TARGET) ../trace_output/trace explicit; \
	else \
		echo "No trace file found at ../trace_output/trace"; \
		echo "Generate one first with ET instrumentation"; \
	fi

# Make scripts executable
scripts:
	@echo "Making scripts executable..."
	chmod +x $(SCRIPT_DIR)/*.sh
	@echo "Scripts are now executable"

# Install dependencies for analysis
install-deps:
	@echo "Installing Python dependencies..."
	pip3 install matplotlib numpy
	@echo "Dependencies installed"

# Help target
help:
	@echo "gem5 Memory Management Comparison - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build the trace replayer (default)"
	@echo "  clean        - Remove build artifacts"
	@echo "  test         - Build and run a quick test"
	@echo "  scripts      - Make all scripts executable"
	@echo "  install-deps - Install Python dependencies"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Usage Examples:"
	@echo "  make              # Build the replayer"
	@echo "  make test         # Build and test"
	@echo "  make clean all    # Clean and rebuild"
	@echo ""

.PHONY: all clean test scripts install-deps help
