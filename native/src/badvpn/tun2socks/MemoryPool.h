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

void pool_init(MemoryPool *pool, size_t block_size);
void pool_free_all(MemoryPool *pool);
void *pool_alloc(MemoryPool *pool);
void pool_free(MemoryPool *pool, void *ptr);

#endif
