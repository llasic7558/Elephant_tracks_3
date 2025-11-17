#include <iostream>
#include <fstream>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <string>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <iomanip>

#include "AllocatorBackend.h"

// ============================================================================
// Data Structures
// ============================================================================

struct AllocationRecord {
    int objectId;
    size_t size;
    int typeId;
    int siteId;
    int length;
    long threadId;
    void* address;
    bool isArray;
    std::chrono::high_resolution_clock::time_point allocTime;
};

struct Statistics {
    size_t totalAllocations = 0;
    size_t totalDeallocations = 0;
    size_t totalBytesAllocated = 0;
    size_t totalBytesFreed = 0;
    size_t peakMemoryUsage = 0;
    size_t currentMemoryUsage = 0;
    size_t gcCollections = 0;
    size_t totalGCTime = 0; // microseconds
    size_t fieldUpdates = 0;
    size_t methodCalls = 0;
    
    void recordAllocation(size_t size) {
        totalAllocations++;
        totalBytesAllocated += size;
        currentMemoryUsage += size;
        if (currentMemoryUsage > peakMemoryUsage) {
            peakMemoryUsage = currentMemoryUsage;
        }
    }
    
    void recordDeallocation(size_t size) {
        totalDeallocations++;
        totalBytesFreed += size;
        currentMemoryUsage -= size;
    }
    
    void recordGC(size_t gcTimeUs) {
        gcCollections++;
        totalGCTime += gcTimeUs;
    }
    
    void print(const char* allocatorName) const {
        std::cout << "\n=== Memory Statistics ===" << std::endl;
        std::cout << "Allocator:             " << allocatorName << std::endl;
        std::cout << "Total Allocations:     " << totalAllocations << std::endl;
        std::cout << "Total Deallocations:   " << totalDeallocations << std::endl;
        std::cout << "Total Bytes Allocated: " << totalBytesAllocated << " (" 
                  << (totalBytesAllocated / 1024.0 / 1024.0) << " MB)" << std::endl;
        std::cout << "Total Bytes Freed:     " << totalBytesFreed << " (" 
                  << (totalBytesFreed / 1024.0 / 1024.0) << " MB)" << std::endl;
        std::cout << "Peak Memory Usage:     " << peakMemoryUsage << " (" 
                  << (peakMemoryUsage / 1024.0 / 1024.0) << " MB)" << std::endl;
        std::cout << "Current Memory Usage:  " << currentMemoryUsage << " (" 
                  << (currentMemoryUsage / 1024.0 / 1024.0) << " MB)" << std::endl;
        std::cout << "GC Collections:        " << gcCollections << std::endl;
        std::cout << "Total GC Time:         " << totalGCTime << " us (" 
                  << (totalGCTime / 1000.0) << " ms)" << std::endl;
        std::cout << "Field Updates:         " << fieldUpdates << std::endl;
        std::cout << "Method Calls:          " << methodCalls << std::endl;
        std::cout << "Memory Leak:           " 
                  << (totalBytesAllocated - totalBytesFreed) << " bytes" << std::endl;
    }
};

// ============================================================================
// Abstract Memory Simulator Interface
// ============================================================================

class MemorySimulator {
protected:
    Statistics stats;
    AllocatorBackend* allocator;
    
public:
    MemorySimulator(AllocatorBackend* alloc) : allocator(alloc) {}
    
    virtual void* allocate(size_t size, int objectId, bool isArray) = 0;
    virtual void deallocate(int objectId, size_t size) = 0;
    virtual void updateField(int tgtObjId, int srcObjId) = 0;
    virtual void methodEntry() = 0;
    virtual void methodExit() = 0;
    virtual ~MemorySimulator() {}
    
    Statistics getStatistics() const { return stats; }
    const char* getAllocatorName() const { return allocator->name(); }
    void printAllocatorStats() const { allocator->print_stats(); }
};

// ============================================================================
// Explicit Memory Manager (malloc/free)
// ============================================================================

class ExplicitMemoryManager : public MemorySimulator {
private:
    std::unordered_map<int, void*> allocations;
    std::unordered_map<int, size_t> sizes;
    
public:
    ExplicitMemoryManager(AllocatorBackend* alloc) : MemorySimulator(alloc) {}
    
    void* allocate(size_t size, int objectId, bool isArray) override {
        void* ptr = allocator->allocate(size);
        if (!ptr) {
            std::cerr << "ERROR: allocation failed for size " << size << std::endl;
            return nullptr;
        }
        
        // Initialize memory to simulate actual object creation
        memset(ptr, 0, size);
        
        allocations[objectId] = ptr;
        sizes[objectId] = size;
        stats.recordAllocation(size);
        
        return ptr;
    }
    
    void deallocate(int objectId, size_t size) override {
        auto it = allocations.find(objectId);
        if (it != allocations.end()) {
            // Touch memory before freeing to simulate access
            volatile char* ptr = (char*)it->second;
            for (size_t i = 0; i < sizes[objectId] && i < 64; i++) {
                ptr[i] = 0;
            }
            
            allocator->deallocate(it->second);
            stats.recordDeallocation(sizes[objectId]);
            allocations.erase(it);
            sizes.erase(objectId);
        }
    }
    
    void updateField(int tgtObjId, int srcObjId) override {
        stats.fieldUpdates++;
        
        // Simulate pointer write if both objects exist
        if (allocations.count(tgtObjId) && allocations.count(srcObjId)) {
            void** tgtAddr = (void**)allocations[tgtObjId];
            void* srcAddr = allocations[srcObjId];
            
            // Write pointer (simulates cache line access)
            *tgtAddr = srcAddr;
        }
    }
    
    void methodEntry() override {
        stats.methodCalls++;
    }
    
    void methodExit() override {
        // No special handling for explicit mode
    }
    
    ~ExplicitMemoryManager() {
        // Clean up any remaining allocations
        for (auto& pair : allocations) {
            allocator->deallocate(pair.second);
        }
    }
};

// ============================================================================
// Garbage Collection Simulator
// ============================================================================

class GCSimulator : public MemorySimulator {
private:
    std::unordered_map<int, void*> allocations;
    std::unordered_map<int, size_t> sizes;
    std::unordered_set<int> deadObjects;
    
    // GC configuration
    size_t gcThreshold;
    size_t allocationsSinceLastGC;
    size_t allocationThreshold;
    
public:
    GCSimulator(AllocatorBackend* alloc, size_t threshold = 10 * 1024 * 1024, 
                size_t allocThreshold = 1000) 
        : MemorySimulator(alloc), gcThreshold(threshold), 
          allocationsSinceLastGC(0), allocationThreshold(allocThreshold) {}
    
    void* allocate(size_t size, int objectId, bool isArray) override {
        void* ptr = allocator->allocate(size);
        if (!ptr) {
            // Try GC before failing
            performGC();
            ptr = allocator->allocate(size);
            if (!ptr) {
                std::cerr << "ERROR: allocation failed even after GC for size " 
                         << size << std::endl;
                return nullptr;
            }
        }
        
        // Initialize memory
        memset(ptr, 0, size);
        
        allocations[objectId] = ptr;
        sizes[objectId] = size;
        stats.recordAllocation(size);
        allocationsSinceLastGC++;
        
        // Trigger GC based on threshold or allocation count
        if (stats.currentMemoryUsage > gcThreshold || 
            allocationsSinceLastGC > allocationThreshold) {
            performGC();
        }
        
        return ptr;
    }
    
    void deallocate(int objectId, size_t size) override {
        // In GC mode, mark object as dead but don't free immediately
        deadObjects.insert(objectId);
    }
    
    void updateField(int tgtObjId, int srcObjId) override {
        stats.fieldUpdates++;
        
        // Simulate pointer write with GC write barrier
        if (allocations.count(tgtObjId) && allocations.count(srcObjId)) {
            void** tgtAddr = (void**)allocations[tgtObjId];
            void* srcAddr = allocations[srcObjId];
            
            // Write barrier: additional work in GC
            // (In real GC, this would update card table or remember set)
            *tgtAddr = srcAddr;
        }
    }
    
    void methodEntry() override {
        stats.methodCalls++;
    }
    
    void methodExit() override {
        // Could trigger GC at method boundaries (like real JVM)
    }
    
    void performGC() {
        auto gcStart = std::chrono::high_resolution_clock::now();
        
        size_t freedBytes = 0;
        size_t freedObjects = 0;
        
        // Sweep: free all dead objects
        for (int deadId : deadObjects) {
            auto it = allocations.find(deadId);
            if (it != allocations.end()) {
                size_t size = sizes[deadId];
                
                // Touch memory to simulate mark-sweep traversal
                volatile char* ptr = (char*)it->second;
                for (size_t i = 0; i < size && i < 64; i += 8) {
                    ptr[i] = 0;
                }
                
                allocator->deallocate(it->second);
                stats.recordDeallocation(size);
                freedBytes += size;
                freedObjects++;
                
                allocations.erase(it);
                sizes.erase(deadId);
            }
        }
        
        deadObjects.clear();
        allocationsSinceLastGC = 0;
        
        auto gcEnd = std::chrono::high_resolution_clock::now();
        auto gcDuration = std::chrono::duration_cast<std::chrono::microseconds>(
            gcEnd - gcStart).count();
        
        stats.recordGC(gcDuration);
        
        std::cout << "[GC] Collected " << freedObjects << " objects, freed " 
                  << (freedBytes / 1024.0) << " KB in " << gcDuration << " us" << std::endl;
    }
    
    void finalGC() {
        std::cout << "\n[GC] Performing final collection..." << std::endl;
        
        // Mark all remaining objects as dead
        for (auto& pair : allocations) {
            deadObjects.insert(pair.first);
        }
        
        performGC();
    }
    
    ~GCSimulator() {
        // Final cleanup
        for (auto& pair : allocations) {
            allocator->deallocate(pair.second);
        }
    }
};

// ============================================================================
// Trace Replayer
// ============================================================================

class TraceReplayer {
private:
    std::unordered_map<int, AllocationRecord> liveObjects;
    MemorySimulator* memoryManager;
    size_t lineNumber;
    bool verbose;
    
public:
    TraceReplayer(MemorySimulator* mm, bool verbose = false) 
        : memoryManager(mm), lineNumber(0), verbose(verbose) {}
    
    void processTraceLine(const std::string& line) {
        lineNumber++;
        
        if (line.empty() || line[0] == '#') {
            return;
        }
        
        std::istringstream iss(line);
        char recordType;
        iss >> recordType;
        
        switch (recordType) {
            case 'N': // Object allocation
                handleObjectAllocation(iss, false);
                break;
            case 'A': // Array allocation
                handleObjectAllocation(iss, true);
                break;
            case 'D': // Object death
                handleObjectDeath(iss);
                break;
            case 'U': // Field update
                handleFieldUpdate(iss);
                break;
            case 'M': // Method entry
                handleMethodEntry(iss);
                break;
            case 'E': // Method exit
                handleMethodExit(iss);
                break;
            default:
                if (verbose) {
                    std::cerr << "Warning: Unknown record type '" << recordType 
                              << "' at line " << lineNumber << std::endl;
                }
        }
        
        // Progress indicator every 10000 lines
        if (lineNumber % 10000 == 0) {
            std::cout << "Processed " << lineNumber << " records..." << std::endl;
        }
    }
    
private:
    void handleObjectAllocation(std::istringstream& iss, bool isArray) {
        int objectId, typeId, siteId, length;
        long size, threadId;
        
        iss >> objectId >> size >> typeId >> siteId >> length >> threadId;
        
        void* ptr = memoryManager->allocate(size, objectId, isArray);
        
        AllocationRecord rec;
        rec.objectId = objectId;
        rec.size = size;
        rec.typeId = typeId;
        rec.siteId = siteId;
        rec.length = length;
        rec.threadId = threadId;
        rec.address = ptr;
        rec.isArray = isArray;
        rec.allocTime = std::chrono::high_resolution_clock::now();
        
        liveObjects[objectId] = rec;
    }
    
    void handleObjectDeath(std::istringstream& iss) {
        int objectId;
        long threadId, timestamp;
        
        iss >> objectId >> threadId >> timestamp;
        
        auto it = liveObjects.find(objectId);
        if (it != liveObjects.end()) {
            size_t size = it->second.size;
            memoryManager->deallocate(objectId, size);
            liveObjects.erase(it);
        }
    }
    
    void handleFieldUpdate(std::istringstream& iss) {
        int tgtObjId, srcObjId, fieldId;
        long threadId;
        
        iss >> tgtObjId >> srcObjId >> fieldId >> threadId;
        
        memoryManager->updateField(tgtObjId, srcObjId);
    }
    
    void handleMethodEntry(std::istringstream& iss) {
        int methodId, receiverObjId;
        long threadId;
        
        iss >> methodId >> receiverObjId >> threadId;
        
        memoryManager->methodEntry();
    }
    
    void handleMethodExit(std::istringstream& iss) {
        int methodId;
        long threadId;
        
        iss >> methodId >> threadId;
        
        memoryManager->methodExit();
    }
    
public:
    void replayTrace(const std::string& traceFile) {
        std::ifstream infile(traceFile);
        if (!infile) {
            std::cerr << "ERROR: Cannot open trace file: " << traceFile << std::endl;
            return;
        }
        
        std::cout << "Replaying trace: " << traceFile << std::endl;
        std::cout << "Using allocator: " << memoryManager->getAllocatorName() << std::endl;
        
        auto start = std::chrono::high_resolution_clock::now();
        
        std::string line;
        while (std::getline(infile, line)) {
            processTraceLine(line);
        }
        
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            end - start).count();
        
        std::cout << "\nTrace replay complete!" << std::endl;
        std::cout << "Total lines processed: " << lineNumber << std::endl;
        std::cout << "Replay time: " << duration << " ms" << std::endl;
        std::cout << "Live objects remaining: " << liveObjects.size() << std::endl;
    }
};

// ============================================================================
// Main Entry Point
// ============================================================================

void printUsage(const char* progName) {
    std::cerr << "Usage: " << progName << " <trace-file> <mode> [options]" << std::endl;
    std::cerr << std::endl;
    std::cerr << "Modes:" << std::endl;
    std::cerr << "  explicit  - Explicit memory management (malloc/free)" << std::endl;
    std::cerr << "  gc        - Garbage collection simulation" << std::endl;
    std::cerr << std::endl;
    std::cerr << "Options:" << std::endl;
    std::cerr << "  --allocator=NAME    Memory allocator to use:" << std::endl;
    std::cerr << "                        standard  - libc malloc (default)" << std::endl;
#ifdef USE_MIMALLOC
    std::cerr << "                        mimalloc  - Microsoft mimalloc" << std::endl;
#endif
#ifdef USE_JEMALLOC
    std::cerr << "                        jemalloc  - Facebook jemalloc" << std::endl;
#endif
    std::cerr << "  --verbose           Enable verbose output" << std::endl;
    std::cerr << "  --gc-threshold=N    GC heap threshold in bytes (default: 10MB)" << std::endl;
    std::cerr << "  --gc-alloc-count=N  GC after N allocations (default: 1000)" << std::endl;
    std::cerr << "  --allocator-stats   Print allocator-specific statistics" << std::endl;
    std::cerr << std::endl;
    std::cerr << "Examples:" << std::endl;
    std::cerr << "  " << progName << " trace.txt explicit" << std::endl;
    std::cerr << "  " << progName << " trace.txt gc --allocator=mimalloc" << std::endl;
    std::cerr << "  " << progName << " trace.txt explicit --allocator=jemalloc --allocator-stats" << std::endl;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printUsage(argv[0]);
        return 1;
    }
    
    std::string traceFile = argv[1];
    std::string mode = argv[2];
    
    bool verbose = false;
    bool allocatorStats = false;
    size_t gcThreshold = 10 * 1024 * 1024; // 10 MB
    size_t gcAllocCount = 1000;
    const char* allocatorName = "standard";
    
    // Parse additional options
    for (int i = 3; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--verbose") {
            verbose = true;
        } else if (arg == "--allocator-stats") {
            allocatorStats = true;
        } else if (arg.find("--allocator=") == 0) {
            allocatorName = argv[i] + 12; // Skip "--allocator="
        } else if (arg.find("--gc-threshold=") == 0) {
            gcThreshold = std::stoul(arg.substr(15));
        } else if (arg.find("--gc-alloc-count=") == 0) {
            gcAllocCount = std::stoul(arg.substr(17));
        }
    }
    
    // Create allocator backend
    AllocatorBackend* allocator = createAllocator(allocatorName);
    
    MemorySimulator* memSim = nullptr;
    
    if (mode == "explicit") {
        std::cout << "=== Explicit Memory Management Mode ===" << std::endl;
        memSim = new ExplicitMemoryManager(allocator);
    } else if (mode == "gc") {
        std::cout << "=== Garbage Collection Mode ===" << std::endl;
        std::cout << "GC Threshold: " << (gcThreshold / 1024.0 / 1024.0) << " MB" << std::endl;
        std::cout << "GC Alloc Count: " << gcAllocCount << std::endl;
        memSim = new GCSimulator(allocator, gcThreshold, gcAllocCount);
    } else {
        std::cerr << "ERROR: Unknown mode '" << mode << "'" << std::endl;
        printUsage(argv[0]);
        delete allocator;
        return 1;
    }
    
    TraceReplayer replayer(memSim, verbose);
    replayer.replayTrace(traceFile);
    
    // Final GC for GC mode
    if (mode == "gc") {
        GCSimulator* gcSim = dynamic_cast<GCSimulator*>(memSim);
        if (gcSim) {
            gcSim->finalGC();
        }
    }
    
    // Print statistics
    memSim->getStatistics().print(memSim->getAllocatorName());
    
    // Print allocator-specific stats if requested
    if (allocatorStats) {
        std::cout << "\n=== Allocator Statistics ===" << std::endl;
        memSim->printAllocatorStats();
    }
    
    delete memSim;
    delete allocator;
    return 0;
}
