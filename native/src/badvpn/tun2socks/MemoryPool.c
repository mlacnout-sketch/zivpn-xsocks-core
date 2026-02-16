#include "MemoryPool.h"
#include <stdlib.h>

void pool_init(MemoryPool *pool, size_t block_size) {
    pool->head = NULL;
    pool->block_size = block_size;
    pthread_mutex_init(&pool->lock, NULL);
    pool->initialized = 1;
}

void pool_free_all(MemoryPool *pool) {
    if (!pool->initialized) return;

    pthread_mutex_lock(&pool->lock);
    PoolNode *current = pool->head;
    while (current) {
        PoolNode *next = current->next;
        free(current);
        current = next;
    }
    pool->head = NULL;
    pthread_mutex_unlock(&pool->lock);

    pthread_mutex_destroy(&pool->lock);
    pool->initialized = 0;
}

void *pool_alloc(MemoryPool *pool) {
    if (!pool->initialized) return NULL;

    pthread_mutex_lock(&pool->lock);
    if (pool->head) {
        void *ptr = pool->head;
        pool->head = pool->head->next;
        pthread_mutex_unlock(&pool->lock);
        return ptr;
    }
    pthread_mutex_unlock(&pool->lock);

    size_t alloc_size = pool->block_size;
    if (alloc_size < sizeof(PoolNode)) alloc_size = sizeof(PoolNode);
    return malloc(alloc_size);
}

void pool_free(MemoryPool *pool, void *ptr) {
    if (!ptr || !pool->initialized) return;

    pthread_mutex_lock(&pool->lock);
    PoolNode *node = (PoolNode *)ptr;
    node->next = pool->head;
    pool->head = node;
    pthread_mutex_unlock(&pool->lock);
}
