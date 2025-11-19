/**
 * TraceReplayer - Simple C Allocator Benchmark
 * 
 * Reads oracle CSV (timestamp,event_type,object_id,size,...)
 * and replays alloc/free events using real malloc/free to measure
 * allocator performance with realistic memory access patterns.
 * 
 * Can be linked against different allocators:
 *   - glibc malloc (default)
 *   - jemalloc: LD_PRELOAD=/path/to/libjemalloc.so ./trace_replayer ...
 *   - mimalloc: LD_PRELOAD=/path/to/libmimalloc.so ./trace_replayer ...
 *   - tcmalloc: LD_PRELOAD=/path/to/libtcmalloc.so ./trace_replayer ...
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <sys/time.h>

// Hash table for tracking allocations
#define HASH_SIZE 65536
#define MAX_LINE 1024

typedef struct Allocation {
    int object_id;
    void* ptr;
    size_t size;
    struct Allocation* next;
} Allocation;

typedef struct {
    Allocation* table[HASH_SIZE];
    size_t total_allocations;
    size_t total_frees;
    size_t total_bytes_allocated;
    size_t total_bytes_freed;
    size_t current_bytes;
    size_t peak_bytes;
    size_t live_objects;
    size_t failed_allocations;
    size_t failed_frees;
} AllocatorStats;

// Global statistics
AllocatorStats g_stats;

// ============================================================================
// Hash Table Functions
// ============================================================================

static unsigned int hash(int object_id) {
    return (unsigned int)object_id % HASH_SIZE;
}

static void init_stats(AllocatorStats* stats) {
    memset(stats, 0, sizeof(AllocatorStats));
    memset(stats->table, 0, sizeof(stats->table));
}

static Allocation* find_allocation(AllocatorStats* stats, int object_id) {
    unsigned int idx = hash(object_id);
    Allocation* curr = stats->table[idx];
    while (curr != NULL) {
        if (curr->object_id == object_id) {
            return curr;
        }
        curr = curr->next;
    }
    return NULL;
}

static void insert_allocation(AllocatorStats* stats, int object_id, void* ptr, size_t size) {
    unsigned int idx = hash(object_id);
    Allocation* alloc = (Allocation*)malloc(sizeof(Allocation));
    if (!alloc) {
        fprintf(stderr, "ERROR: Failed to allocate tracking structure\n");
        return;
    }
    alloc->object_id = object_id;
    alloc->ptr = ptr;
    alloc->size = size;
    alloc->next = stats->table[idx];
    stats->table[idx] = alloc;
}

static void remove_allocation(AllocatorStats* stats, int object_id) {
    unsigned int idx = hash(object_id);
    Allocation* curr = stats->table[idx];
    Allocation* prev = NULL;
    
    while (curr != NULL) {
        if (curr->object_id == object_id) {
            if (prev == NULL) {
                stats->table[idx] = curr->next;
            } else {
                prev->next = curr->next;
            }
            free(curr);
            return;
        }
        prev = curr;
        curr = curr->next;
    }
}

// ============================================================================
// Memory Touch Functions - Force cache/TLB activity
// ============================================================================

static void touch_memory(void* ptr, size_t size) {
    if (!ptr || size == 0) return;
    
    // Write pattern to simulate field initialization
    // Touch memory at multiple offsets to populate cache lines
    volatile char* mem = (volatile char*)ptr;
    
    // Write to first byte
    mem[0] = 0xAA;
    
    // Write to last byte
    if (size > 1) {
        mem[size - 1] = 0xBB;
    }
    
    // Write to middle bytes (every 64 bytes for cache line activity)
    for (size_t offset = 64; offset < size; offset += 64) {
        mem[offset] = 0xCC;
    }
    
    // For larger allocations, write some "fields"
    if (size >= sizeof(long) * 4) {
        volatile long* fields = (volatile long*)ptr;
        fields[0] = 0x123456789ABCDEF0L;  // Simulated field 1
        fields[1] = 0xFEDCBA9876543210L;  // Simulated field 2
    }
}

static void read_random_objects(AllocatorStats* stats) {
    // Periodically read from live objects to maintain working set
    // This simulates the mutator accessing objects
    size_t count = 0;
    size_t target = stats->live_objects / 10; // Sample 10% of live objects
    
    if (target == 0) return;
    
    for (int i = 0; i < HASH_SIZE && count < target; i++) {
        Allocation* curr = stats->table[i];
        while (curr != NULL && count < target) {
            if (curr->ptr && curr->size > 0) {
                volatile char* mem = (volatile char*)curr->ptr;
                volatile char val = mem[0]; // Read first byte
                (void)val; // Suppress unused variable warning
                count++;
            }
            curr = curr->next;
        }
    }
}

// ============================================================================
// Allocation Event Handlers
// ============================================================================

static void handle_alloc(AllocatorStats* stats, int object_id, size_t size) {
    // Allocate memory
    void* ptr = malloc(size);
    
    if (!ptr) {
        stats->failed_allocations++;
        fprintf(stderr, "WARNING: malloc(%zu) failed for object %d\n", size, object_id);
        return;
    }
    
    // Touch memory to force cache/TLB activity
    touch_memory(ptr, size);
    
    // Track allocation
    insert_allocation(stats, object_id, ptr, size);
    
    // Update statistics
    stats->total_allocations++;
    stats->total_bytes_allocated += size;
    stats->current_bytes += size;
    stats->live_objects++;
    
    if (stats->current_bytes > stats->peak_bytes) {
        stats->peak_bytes = stats->current_bytes;
    }
    
    // Periodically read from live objects (every 100 allocations)
    if (stats->total_allocations % 100 == 0) {
        read_random_objects(stats);
    }
}

static void handle_free(AllocatorStats* stats, int object_id) {
    Allocation* alloc = find_allocation(stats, object_id);
    
    if (!alloc) {
        stats->failed_frees++;
        // Silent fail - oracle may have deaths for objects allocated before tracing
        return;
    }
    
    // Free the memory
    free(alloc->ptr);
    
    // Update statistics
    stats->total_frees++;
    stats->total_bytes_freed += alloc->size;
    stats->current_bytes -= alloc->size;
    stats->live_objects--;
    
    // Remove from tracking
    remove_allocation(stats, object_id);
}

// ============================================================================
// CSV Parsing
// ============================================================================

static void parse_csv_line(char* line, AllocatorStats* stats) {
    // Expected format: timestamp,event_type,object_id,size,site_id,thread_id,type_id
    char event_type[32];
    int object_id;
    size_t size;
    
    // Skip header line
    if (strstr(line, "timestamp") != NULL) {
        return;
    }
    
    // Parse CSV fields
    char* token = strtok(line, ",");
    if (!token) return;  // timestamp
    
    token = strtok(NULL, ",");
    if (!token) return;
    strncpy(event_type, token, sizeof(event_type) - 1);
    event_type[sizeof(event_type) - 1] = '\0';
    
    token = strtok(NULL, ",");
    if (!token) return;
    object_id = atoi(token);
    
    token = strtok(NULL, ",");
    if (!token) return;
    size = (size_t)atol(token);
    
    // Process event
    if (strcmp(event_type, "alloc") == 0) {
        handle_alloc(stats, object_id, size);
    } else if (strcmp(event_type, "free") == 0) {
        handle_free(stats, object_id);
    }
}

// ============================================================================
// Statistics Printing
// ============================================================================

static void print_statistics(AllocatorStats* stats, double elapsed_seconds) {
    printf("\n=== Trace Replay Complete ===\n");
    printf("Total events processed: %zu allocations, %zu frees\n", 
           stats->total_allocations, stats->total_frees);
    printf("Replay time: %.3f seconds\n", elapsed_seconds);
    printf("\n=== Memory Statistics ===\n");
    printf("Total Allocations:     %zu\n", stats->total_allocations);
    printf("Total Frees:           %zu\n", stats->total_frees);
    printf("Total Bytes Allocated: %zu (%.2f MB)\n", 
           stats->total_bytes_allocated,
           stats->total_bytes_allocated / 1024.0 / 1024.0);
    printf("Total Bytes Freed:     %zu (%.2f MB)\n", 
           stats->total_bytes_freed,
           stats->total_bytes_freed / 1024.0 / 1024.0);
    printf("Peak Memory Usage:     %zu (%.2f MB)\n", 
           stats->peak_bytes,
           stats->peak_bytes / 1024.0 / 1024.0);
    printf("Current Memory Usage:  %zu (%.2f MB)\n", 
           stats->current_bytes,
           stats->current_bytes / 1024.0 / 1024.0);
    printf("Live Objects:          %zu\n", stats->live_objects);
    printf("Failed Allocations:    %zu\n", stats->failed_allocations);
    printf("Failed Frees:          %zu\n", stats->failed_frees);
    printf("Memory Leak:           %zd bytes\n", 
           (ssize_t)(stats->total_bytes_allocated - stats->total_bytes_freed));
}

// ============================================================================
// Main Program
// ============================================================================

static void print_usage(const char* progname) {
    printf("Usage: %s <oracle.csv>\n", progname);
    printf("\nReads an oracle CSV file and replays alloc/free events.\n");
    printf("Uses real malloc/free to measure allocator performance.\n");
    printf("\nTo test different allocators:\n");
    printf("  Default (glibc):  %s oracle.csv\n", progname);
    printf("  jemalloc:         LD_PRELOAD=/path/to/libjemalloc.so %s oracle.csv\n", progname);
    printf("  mimalloc:         LD_PRELOAD=/path/to/libmimalloc.so %s oracle.csv\n", progname);
    printf("  tcmalloc:         LD_PRELOAD=/path/to/libtcmalloc.so %s oracle.csv\n", progname);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }
    
    const char* trace_file = argv[1];
    
    // Initialize statistics
    init_stats(&g_stats);
    
    // Open trace file
    FILE* fp = fopen(trace_file, "r");
    if (!fp) {
        fprintf(stderr, "ERROR: Cannot open file '%s'\n", trace_file);
        return 1;
    }
    
    printf("=== Trace Replayer - Allocator Benchmark ===\n");
    printf("Reading oracle: %s\n\n", trace_file);
    
    // Start timing
    struct timeval start_time, end_time;
    gettimeofday(&start_time, NULL);
    
    // Process trace file line by line
    char line[MAX_LINE];
    size_t line_count = 0;
    
    while (fgets(line, sizeof(line), fp)) {
        line_count++;
        // Remove newline
        line[strcspn(line, "\r\n")] = 0;
        
        // Parse and process line
        parse_csv_line(line, &g_stats);
    }
    
    fclose(fp);
    
    // End timing
    gettimeofday(&end_time, NULL);
    double elapsed = (end_time.tv_sec - start_time.tv_sec) + 
                     (end_time.tv_usec - start_time.tv_usec) / 1000000.0;
    
    // Print statistics
    print_statistics(&g_stats, elapsed);
    
    // Cleanup - free any remaining allocations
    printf("\nCleaning up remaining allocations...\n");
    for (int i = 0; i < HASH_SIZE; i++) {
        Allocation* curr = g_stats.table[i];
        while (curr != NULL) {
            Allocation* next = curr->next;
            if (curr->ptr) {
                free(curr->ptr);
            }
            free(curr);
            curr = next;
        }
    }
    
    printf("Done.\n");
    return 0;
}

// ============================================================================
// Abstract Memory Simulator Interface
// ============================================================================

class MemorySimulator {
protected:
    Statistics stats;
    
public:
    virtual void* allocate(size_t size, int objectId, bool isArray) = 0;
    virtual void deallocate(int objectId, size_t size) = 0;
    virtual void updateField(int tgtObjId, int srcObjId) = 0;
    virtual void methodEntry() = 0;
    virtual void methodExit() = 0;
    virtual ~MemorySimulator() {}
    
    Statistics getStatistics() const { return stats; }
};

// ============================================================================
// Explicit Memory Manager (malloc/free)
// ============================================================================

class ExplicitMemoryManager : public MemorySimulator {
private:
    std::unordered_map<int, void*> allocations;
    std::unordered_map<int, size_t> sizes;
    
public:
    void* allocate(size_t size, int objectId, bool isArray) override {
        void* ptr = malloc(size);
        if (!ptr) {
            std::cerr << "ERROR: malloc failed for size " << size << std::endl;
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
            
            free(it->second);
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
            free(pair.second);
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
    GCSimulator(size_t threshold = 10 * 1024 * 1024, size_t allocThreshold = 1000) 
        : gcThreshold(threshold), allocationsSinceLastGC(0), 
          allocationThreshold(allocThreshold) {}
    
    void* allocate(size_t size, int objectId, bool isArray) override {
        void* ptr = malloc(size);
        if (!ptr) {
            // Try GC before failing
            performGC();
            ptr = malloc(size);
            if (!ptr) {
                std::cerr << "ERROR: malloc failed even after GC for size " << size << std::endl;
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
                
                free(it->second);
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
            free(pair.second);
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
            case 'N': // Object allocation: N <object-id> <size> <type-id> <site-id> <length> <thread-id>
                handleObjectAllocation(iss, false);
                break;
                
            case 'A': // Array allocation: A <object-id> <size> <type-id> <site-id> <length> <thread-id>
                handleObjectAllocation(iss, true);
                break;
                
            case 'D': // Object death: D <object-id> <thread-id> <timestamp>
                handleObjectDeath(iss);
                break;
                
            case 'U': // Field update: U <tgt-obj-id> <src-obj-id> <field-id> <thread-id>
                handleFieldUpdate(iss);
                break;
                
            case 'M': // Method entry: M <method-id> <receiver-object-id> <thread-id>
                handleMethodEntry(iss);
                break;
                
            case 'E': // Method exit: E <method-id> <thread-id>
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
        
        if (verbose && lineNumber % 1000 == 0) {
            std::cout << "Alloc: objId=" << objectId << " size=" << size 
                      << " type=" << (isArray ? "array" : "object") << std::endl;
        }
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
            
            if (verbose && lineNumber % 1000 == 0) {
                std::cout << "Death: objId=" << objectId << " size=" << size << std::endl;
            }
        } else if (verbose) {
            std::cerr << "Warning: Death of unknown object " << objectId 
                      << " at line " << lineNumber << std::endl;
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
    std::cerr << "  --verbose           Enable verbose output" << std::endl;
    std::cerr << "  --gc-threshold=N    GC heap threshold in bytes (default: 10MB)" << std::endl;
    std::cerr << "  --gc-alloc-count=N  GC after N allocations (default: 1000)" << std::endl;
    std::cerr << std::endl;
    std::cerr << "Examples:" << std::endl;
    std::cerr << "  " << progName << " trace.txt explicit" << std::endl;
    std::cerr << "  " << progName << " trace.txt gc --gc-threshold=20971520" << std::endl;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printUsage(argv[0]);
        return 1;
    }
    
    std::string traceFile = argv[1];
    std::string mode = argv[2];
    
    bool verbose = false;
    size_t gcThreshold = 10 * 1024 * 1024; // 10 MB
    size_t gcAllocCount = 1000;
    
    // Parse additional options
    for (int i = 3; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--verbose") {
            verbose = true;
        } else if (arg.find("--gc-threshold=") == 0) {
            gcThreshold = std::stoul(arg.substr(15));
        } else if (arg.find("--gc-alloc-count=") == 0) {
            gcAllocCount = std::stoul(arg.substr(17));
        }
    }
    
    MemorySimulator* memSim = nullptr;
    
    if (mode == "explicit") {
        std::cout << "=== Explicit Memory Management Mode ===" << std::endl;
        memSim = new ExplicitMemoryManager();
    } else if (mode == "gc") {
        std::cout << "=== Garbage Collection Mode ===" << std::endl;
        std::cout << "GC Threshold: " << (gcThreshold / 1024.0 / 1024.0) << " MB" << std::endl;
        std::cout << "GC Alloc Count: " << gcAllocCount << std::endl;
        memSim = new GCSimulator(gcThreshold, gcAllocCount);
    } else {
        std::cerr << "ERROR: Unknown mode '" << mode << "'" << std::endl;
        printUsage(argv[0]);
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
    memSim->getStatistics().print();
    
    delete memSim;
    return 0;
}
