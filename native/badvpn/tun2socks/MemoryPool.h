#ifndef MEMORY_POOL_H
#define MEMORY_POOL_H

#include <stddef.h>
#include <pthread.h>

typedef struct PoolNode {
    struct PoolNode *next;
} PoolNode;

typedef struct {
    PoolNode *head;
    size_t block_size;
    pthread_mutex_t lock;
    int initialized;
} MemoryPool;

typedef struct {
    unsigned long long alloc_calls;
    unsigned long long free_calls;
    unsigned long long pool_hits;
    unsigned long long pool_misses;
    unsigned long long bytes_from_heap;
    unsigned long long lock_wait_ns;
} MemoryPoolStats;

void pool_init(MemoryPool *pool, size_t block_size);
void pool_free_all(MemoryPool *pool);
void *pool_alloc(MemoryPool *pool);
void pool_free(MemoryPool *pool, void *ptr);
void pool_get_stats(MemoryPoolStats *out_stats);
void pool_reset_stats(void);

#endif
