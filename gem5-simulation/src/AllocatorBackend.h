#ifndef ALLOCATOR_BACKEND_H
#define ALLOCATOR_BACKEND_H

#include <cstdlib>
#include <cstring>

/**
 * Abstract allocator backend interface
 * Allows swapping between different memory allocators
 */
class AllocatorBackend {
public:
    virtual ~AllocatorBackend() {}
    
    virtual void* allocate(size_t size) = 0;
    virtual void deallocate(void* ptr) = 0;
    virtual void* reallocate(void* ptr, size_t new_size) = 0;
    
    virtual const char* name() const = 0;
    virtual void print_stats() const {}
};

/**
 * Standard libc malloc/free
 */
class StandardAllocator : public AllocatorBackend {
public:
    void* allocate(size_t size) override {
        return malloc(size);
    }
    
    void deallocate(void* ptr) override {
        free(ptr);
    }
    
    void* reallocate(void* ptr, size_t new_size) override {
        return realloc(ptr, new_size);
    }
    
    const char* name() const override {
        return "standard (libc malloc)";
    }
};

#ifdef USE_MIMALLOC
#include <mimalloc.h>

/**
 * Microsoft mimalloc allocator
 * High-performance allocator with low fragmentation
 */
class MimallocAllocator : public AllocatorBackend {
public:
    void* allocate(size_t size) override {
        return mi_malloc(size);
    }
    
    void deallocate(void* ptr) override {
        mi_free(ptr);
    }
    
    void* reallocate(void* ptr, size_t new_size) override {
        return mi_realloc(ptr, new_size);
    }
    
    const char* name() const override {
        return "mimalloc";
    }
    
    void print_stats() const override {
        mi_stats_print(nullptr);
    }
};
#endif

#ifdef USE_JEMALLOC
#include <jemalloc/jemalloc.h>

/**
 * jemalloc allocator
 * Used by Firefox, Facebook, and many high-performance systems
 */
class JemallocAllocator : public AllocatorBackend {
public:
    void* allocate(size_t size) override {
        return je_malloc(size);
    }
    
    void deallocate(void* ptr) override {
        je_free(ptr);
    }
    
    void* reallocate(void* ptr, size_t new_size) override {
        return je_realloc(ptr, new_size);
    }
    
    const char* name() const override {
        return "jemalloc";
    }
    
    void print_stats() const override {
        // Print jemalloc statistics
        je_malloc_stats_print(nullptr, nullptr, nullptr);
    }
};
#endif

/**
 * Factory function to create appropriate allocator
 */
inline AllocatorBackend* createAllocator(const char* allocator_name) {
    if (allocator_name == nullptr || strcmp(allocator_name, "standard") == 0) {
        return new StandardAllocator();
    }
    
#ifdef USE_MIMALLOC
    if (strcmp(allocator_name, "mimalloc") == 0) {
        return new MimallocAllocator();
    }
#endif

#ifdef USE_JEMALLOC
    if (strcmp(allocator_name, "jemalloc") == 0) {
        return new JemallocAllocator();
    }
#endif
    
    // Default to standard if unknown
    return new StandardAllocator();
}

#endif // ALLOCATOR_BACKEND_H
