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
#include <unistd.h>

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
    
    long long memory_leak = (long long)(stats->total_bytes_allocated - stats->total_bytes_freed);
    printf("Memory Leak:           %lld bytes\n", memory_leak);
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
    
    // DEBUG: Print current working directory and file information
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd)) != NULL) {
        printf("DEBUG: Current working directory: %s\n", cwd);
    } else {
        perror("DEBUG: getcwd() error");
    }
    
    printf("DEBUG: Attempting to open file: '%s'\n", trace_file);
    
    // Check if file exists and is readable
    if (access(trace_file, F_OK) == 0) {
        printf("DEBUG: File exists!\n");
        if (access(trace_file, R_OK) == 0) {
            printf("DEBUG: File is readable!\n");
        } else {
            fprintf(stderr, "DEBUG: File exists but is NOT readable (permission denied)\n");
        }
    } else {
        fprintf(stderr, "DEBUG: File does NOT exist at path: '%s'\n", trace_file);
    }
    
    // Try to list current directory contents
    printf("DEBUG: Listing current directory contents:\n");
    system("ls -la");
    
    // Open trace file
    FILE* fp = fopen(trace_file, "r");
    if (!fp) {
        fprintf(stderr, "ERROR: Cannot open file '%s'\n", trace_file);
        perror("ERROR: fopen failed with");
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
