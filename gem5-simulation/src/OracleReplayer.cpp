#include "OracleReplayer.h"
#include <algorithm>
#include <cassert>

namespace oracle {

bool OracleReplayer::load_oracle(const std::string& csv_file) {
    std::ifstream file(csv_file);
    if (!file.is_open()) {
        std::cerr << "Error: Cannot open oracle file: " << csv_file << std::endl;
        return false;
    }
    
    std::string line;
    bool header_skipped = false;
    
    while (std::getline(file, line)) {
        // Skip header
        if (!header_skipped) {
            header_skipped = true;
            continue;
        }
        
        // Skip empty lines
        if (line.empty()) continue;
        
        Event event;
        if (parse_event(line, event)) {
            events_.push_back(event);
        }
    }
    
    file.close();
    
    // Sort by timestamp (should already be sorted, but ensure it)
    std::sort(events_.begin(), events_.end(),
              [](const Event& a, const Event& b) { return a.timestamp < b.timestamp; });
    
    if (verbose_) {
        std::cout << "Loaded " << events_.size() << " events from oracle\n";
        
        size_t alloc_count = 0;
        size_t free_count = 0;
        for (const auto& e : events_) {
            if (e.is_alloc()) alloc_count++;
            else if (e.is_free()) free_count++;
        }
        
        std::cout << "  Allocations: " << alloc_count << "\n";
        std::cout << "  Frees: " << free_count << "\n";
    }
    
    return events_.size() > 0;
}

bool OracleReplayer::parse_event(const std::string& line, Event& event) {
    std::istringstream iss(line);
    std::string field;
    
    // timestamp
    if (!std::getline(iss, field, ',')) return false;
    event.timestamp = std::stoull(field);
    
    // event_type
    if (!std::getline(iss, field, ',')) return false;
    event.event_type = field;
    
    // object_id
    if (!std::getline(iss, field, ',')) return false;
    event.object_id = std::stoull(field);
    
    // size
    if (!std::getline(iss, field, ',')) return false;
    event.size = std::stoull(field);
    
    // site_id
    if (!std::getline(iss, field, ',')) return false;
    event.site_id = std::stoul(field);
    
    // thread_id
    if (!std::getline(iss, field, ',')) return false;
    event.thread_id = std::stoull(field);
    
    // type_id
    if (!std::getline(iss, field, ',')) return false;
    event.type_id = std::stoul(field);
    
    return true;
}

void OracleReplayer::replay() {
    if (events_.empty()) {
        std::cerr << "Error: No events to replay\n";
        return;
    }
    
    if (verbose_) {
        std::cout << "\n=== Starting Oracle Replay ===\n";
        std::cout << "Total events: " << events_.size() << "\n\n";
    }
    
    for (current_event_index_ = 0; 
         current_event_index_ < events_.size(); 
         current_event_index_++) {
        
        const Event& event = events_[current_event_index_];
        
        if (verbose_ && (current_event_index_ % 100 == 0)) {
            std::cout << "Progress: " << current_event_index_ 
                      << "/" << events_.size() << " events\r" << std::flush;
        }
        
        if (event.is_alloc()) {
            process_allocation(event);
        } else if (event.is_free()) {
            process_free(event);
        }
    }
    
    // Execute any remaining pending frees at end of trace
    if (!pending_frees_.empty()) {
        if (verbose_) {
            std::cout << "\nExecuting " << pending_frees_.size() 
                      << " remaining frees at end of trace...\n";
        }
        execute_pending_frees(0);  // No next allocation
    }
    
    if (verbose_) {
        std::cout << "\nReplay complete!                    \n";
    }
}

void OracleReplayer::process_allocation(const Event& event) {
    // CRITICAL: Before allocation, check for pending frees
    // This implements the paper's approach:
    // "Before each allocation, the simulator consults the oracle 
    //  to determine if any objects should be freed."
    
    if (!pending_frees_.empty()) {
        execute_pending_frees(event.size);
    }
    
    // Now perform the allocation
    void* ptr = do_malloc(event.size);
    
    if (ptr == nullptr) {
        std::cerr << "Error: malloc failed for object " << event.object_id 
                  << " size " << event.size << std::endl;
        return;
    }
    
    // Track the allocation
    AllocatedObject obj(ptr, event.size, event.timestamp, event.site_id);
    live_objects_[event.object_id] = obj;
    
    // Update statistics
    stats_.record_allocation(event.size, event.site_id);
    
    if (verbose_ && (stats_.total_allocations % 100 == 0)) {
        std::cout << "Alloc #" << stats_.total_allocations 
                  << " (obj " << event.object_id << ", " << event.size << " bytes)\n";
    }
}

void OracleReplayer::process_free(const Event& event) {
    // Queue the free for execution before next allocation
    // This follows the paper: "saves the function parameter (the size request 
    // for malloc) and jumps to free instead"
    
    pending_frees_.push(event);
    
    if (verbose_ && (pending_frees_.size() % 50 == 0)) {
        std::cout << "Queued free for obj " << event.object_id 
                  << " (" << pending_frees_.size() << " pending)\n";
    }
}

void OracleReplayer::execute_pending_frees(size_t next_alloc_size) {
    // Execute all pending frees before the next allocation
    // This simulates: "The simulator repeats this cycle until there are 
    // no objects left to be reclaimed, and then allocation and program 
    // execution continues as normal."
    
    if (verbose_ && !pending_frees_.empty()) {
        std::cout << "Executing " << pending_frees_.size() 
                  << " pending frees before allocation of " 
                  << next_alloc_size << " bytes\n";
    }
    
    while (!pending_frees_.empty()) {
        const Event& free_event = pending_frees_.front();
        
        // Find the object
        auto it = live_objects_.find(free_event.object_id);
        if (it == live_objects_.end()) {
            std::cerr << "Warning: Attempt to free unknown object " 
                      << free_event.object_id << std::endl;
            pending_frees_.pop();
            continue;
        }
        
        const AllocatedObject& obj = it->second;
        
        // Calculate lifetime
        uint64_t lifetime = free_event.timestamp - obj.alloc_time;
        
        // Actually free the memory
        do_free(obj.address);
        
        // Update statistics
        stats_.record_free(obj.size, lifetime);
        
        // Remove from live objects
        live_objects_.erase(it);
        
        if (verbose_ && (stats_.total_frees % 100 == 0)) {
            std::cout << "Free #" << stats_.total_frees 
                      << " (obj " << free_event.object_id 
                      << ", lifetime " << lifetime << ")\n";
        }
        
        pending_frees_.pop();
    }
}

void* OracleReplayer::do_malloc(size_t size) {
    // Actual malloc call
    // In gem5 simulation, this would invoke the memory subsystem
    // For now, just use standard malloc
    return malloc(size);
}

void OracleReplayer::do_free(void* ptr) {
    // Actual free call
    // "sets the return address so that execution returns to the 
    //  malloc call rather than the following instruction"
    // In simulation, this is implicit - we're already in the allocation flow
    
    if (ptr != nullptr) {
        free(ptr);
    }
}

void OracleReplayer::cleanup() {
    // Free any remaining allocated objects
    if (!live_objects_.empty()) {
        if (verbose_) {
            std::cout << "\nCleaning up " << live_objects_.size() 
                      << " remaining objects\n";
        }
        
        for (auto& pair : live_objects_) {
            if (pair.second.address != nullptr) {
                free(pair.second.address);
            }
        }
        
        live_objects_.clear();
    }
}

} // namespace oracle
