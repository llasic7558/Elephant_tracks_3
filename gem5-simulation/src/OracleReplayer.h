#ifndef ORACLE_REPLAYER_H
#define ORACLE_REPLAYER_H

#include <string>
#include <vector>
#include <map>
#include <queue>
#include <fstream>
#include <sstream>
#include <iostream>
#include <cstdlib>
#include <cstdint>

/**
 * Oracle Replayer - Follows the original paper's approach
 * 
 * Before each allocation:
 * 1. Consult oracle to find objects that should be freed
 * 2. For each object to free:
 *    - Save malloc size parameter
 *    - Call free()
 *    - Set return address back to malloc call
 * 3. Once all reclamations done, proceed with malloc
 * 
 * This simulates the memory behavior with perfect knowledge of object lifetimes.
 */

namespace oracle {

// Oracle event from CSV
struct Event {
    uint64_t timestamp;      // Event index (logical time)
    std::string event_type;  // "alloc" or "free"
    uint64_t object_id;      // Object identifier
    size_t size;             // Object size in bytes
    uint32_t site_id;        // Allocation site
    uint64_t thread_id;      // Thread ID
    uint32_t type_id;        // Type ID
    
    bool is_alloc() const { return event_type == "alloc"; }
    bool is_free() const { return event_type == "free"; }
};

// Allocated object tracking
struct AllocatedObject {
    void* address;           // Actual memory address
    size_t size;             // Size in bytes
    uint64_t alloc_time;     // When allocated
    uint32_t site_id;        // Allocation site
    
    AllocatedObject() : address(nullptr), size(0), alloc_time(0), site_id(0) {}
    AllocatedObject(void* addr, size_t sz, uint64_t time, uint32_t site)
        : address(addr), size(sz), alloc_time(time), site_id(site) {}
};

// Statistics tracking
struct Statistics {
    uint64_t total_allocations = 0;
    uint64_t total_frees = 0;
    uint64_t bytes_allocated = 0;
    uint64_t bytes_freed = 0;
    uint64_t peak_memory = 0;
    uint64_t current_memory = 0;
    
    // Allocation sites
    std::map<uint32_t, uint64_t> allocations_per_site;
    std::map<uint32_t, uint64_t> bytes_per_site;
    
    // Lifetime analysis
    uint64_t total_lifetime = 0;  // Sum of all object lifetimes
    uint64_t max_lifetime = 0;
    uint64_t min_lifetime = UINT64_MAX;
    
    void record_allocation(size_t size, uint32_t site_id) {
        total_allocations++;
        bytes_allocated += size;
        current_memory += size;
        if (current_memory > peak_memory) {
            peak_memory = current_memory;
        }
        allocations_per_site[site_id]++;
        bytes_per_site[site_id] += size;
    }
    
    void record_free(size_t size, uint64_t lifetime) {
        total_frees++;
        bytes_freed += size;
        current_memory -= size;
        total_lifetime += lifetime;
        if (lifetime > max_lifetime) max_lifetime = lifetime;
        if (lifetime < min_lifetime) min_lifetime = lifetime;
    }
    
    void print() const {
        std::cout << "\n=== Memory Statistics ===\n";
        std::cout << "Total allocations: " << total_allocations << "\n";
        std::cout << "Total frees: " << total_frees << "\n";
        std::cout << "Bytes allocated: " << bytes_allocated << " (" 
                  << (bytes_allocated / 1024.0) << " KB)\n";
        std::cout << "Bytes freed: " << bytes_freed << " (" 
                  << (bytes_freed / 1024.0) << " KB)\n";
        std::cout << "Peak memory: " << peak_memory << " (" 
                  << (peak_memory / 1024.0) << " KB)\n";
        std::cout << "Live memory: " << current_memory << " (" 
                  << (current_memory / 1024.0) << " KB)\n";
        
        if (total_frees > 0) {
            std::cout << "\n=== Lifetime Analysis ===\n";
            std::cout << "Average lifetime: " 
                      << (total_lifetime / total_frees) << " events\n";
            std::cout << "Max lifetime: " << max_lifetime << " events\n";
            std::cout << "Min lifetime: " << (min_lifetime == UINT64_MAX ? 0 : min_lifetime) 
                      << " events\n";
        }
        
        std::cout << "\n=== Hot Allocation Sites ===\n";
        // Convert map to vector for sorting
        std::vector<std::pair<uint32_t, uint64_t>> sites(
            allocations_per_site.begin(), allocations_per_site.end());
        std::sort(sites.begin(), sites.end(),
                  [](const std::pair<uint32_t, uint64_t>& a, 
                     const std::pair<uint32_t, uint64_t>& b) { 
                      return a.second > b.second; 
                  });
        
        size_t limit = std::min(sites.size(), size_t(10));
        for (size_t i = 0; i < limit; i++) {
            uint32_t site = sites[i].first;
            uint64_t count = sites[i].second;
            uint64_t bytes = bytes_per_site.at(site);
            std::cout << "  Site " << site << ": " << count << " allocations, "
                      << bytes << " bytes (" << (bytes / 1024.0) << " KB)\n";
        }
    }
};

class OracleReplayer {
public:
    OracleReplayer(bool verbose = false) 
        : verbose_(verbose), current_event_index_(0) {}
    
    ~OracleReplayer() {
        cleanup();
    }
    
    // Load oracle from CSV file
    bool load_oracle(const std::string& csv_file);
    
    // Run the replay simulation
    void replay();
    
    // Get statistics
    const Statistics& get_statistics() const { return stats_; }
    
    // Print statistics
    void print_statistics() const { stats_.print(); }

private:
    bool verbose_;
    uint64_t current_event_index_;
    
    // Oracle events (sorted by timestamp)
    std::vector<Event> events_;
    
    // Active allocations: object_id -> AllocatedObject
    std::map<uint64_t, AllocatedObject> live_objects_;
    
    // Pending frees (objects that should be freed before next alloc)
    std::queue<Event> pending_frees_;
    
    // Statistics
    Statistics stats_;
    
    // Parse CSV line into Event
    bool parse_event(const std::string& line, Event& event);
    
    // Process allocation event
    void process_allocation(const Event& event);
    
    // Process free event (queued until next allocation)
    void process_free(const Event& event);
    
    // Execute pending frees before allocation
    void execute_pending_frees(size_t next_alloc_size);
    
    // Actually call malloc/free
    void* do_malloc(size_t size);
    void do_free(void* ptr);
    
    // Cleanup all allocated memory
    void cleanup();
};

} // namespace oracle

#endif // ORACLE_REPLAYER_H
