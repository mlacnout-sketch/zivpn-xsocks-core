#include "MemoryPool.h"
#include <stdlib.h>
#include <time.h>

static MemoryPoolStats g_pool_stats;

static unsigned long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long long)ts.tv_sec * 1000000000ull + (unsigned long long)ts.tv_nsec;
}

static void add_ull(unsigned long long *dst, unsigned long long v) {
    __sync_fetch_and_add(dst, v);
}

void pool_init(MemoryPool *pool, size_t block_size) {
    pool->head = NULL;
    pool->block_size = block_size;
    pthread_mutex_init(&pool->lock, NULL);
    pool->initialized = 1;
}

void pool_free_all(MemoryPool *pool) {
    if (!pool->initialized) return;

    const unsigned long long lock_start = now_ns();
    pthread_mutex_lock(&pool->lock);
    add_ull(&g_pool_stats.lock_wait_ns, now_ns() - lock_start);

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

    add_ull(&g_pool_stats.alloc_calls, 1);

    const unsigned long long lock_start = now_ns();
    pthread_mutex_lock(&pool->lock);
    add_ull(&g_pool_stats.lock_wait_ns, now_ns() - lock_start);

    if (pool->head) {
        void *ptr = pool->head;
        pool->head = pool->head->next;
        pthread_mutex_unlock(&pool->lock);
        add_ull(&g_pool_stats.pool_hits, 1);
        return ptr;
    }
    pthread_mutex_unlock(&pool->lock);

    size_t alloc_size = pool->block_size;
    if (alloc_size < sizeof(PoolNode)) alloc_size = sizeof(PoolNode);

    add_ull(&g_pool_stats.pool_misses, 1);
    add_ull(&g_pool_stats.bytes_from_heap, (unsigned long long)alloc_size);
    return malloc(alloc_size);
}

void pool_free(MemoryPool *pool, void *ptr) {
    if (!ptr || !pool->initialized) return;

    add_ull(&g_pool_stats.free_calls, 1);

    const unsigned long long lock_start = now_ns();
    pthread_mutex_lock(&pool->lock);
    add_ull(&g_pool_stats.lock_wait_ns, now_ns() - lock_start);

    PoolNode *node = (PoolNode *)ptr;
    node->next = pool->head;
    pool->head = node;
    pthread_mutex_unlock(&pool->lock);
}

void pool_get_stats(MemoryPoolStats *out_stats) {
    if (!out_stats) return;
    out_stats->alloc_calls = __sync_add_and_fetch(&g_pool_stats.alloc_calls, 0);
    out_stats->free_calls = __sync_add_and_fetch(&g_pool_stats.free_calls, 0);
    out_stats->pool_hits = __sync_add_and_fetch(&g_pool_stats.pool_hits, 0);
    out_stats->pool_misses = __sync_add_and_fetch(&g_pool_stats.pool_misses, 0);
    out_stats->bytes_from_heap = __sync_add_and_fetch(&g_pool_stats.bytes_from_heap, 0);
    out_stats->lock_wait_ns = __sync_add_and_fetch(&g_pool_stats.lock_wait_ns, 0);
}

void pool_reset_stats(void) {
    g_pool_stats.alloc_calls = 0;
    g_pool_stats.free_calls = 0;
    g_pool_stats.pool_hits = 0;
    g_pool_stats.pool_misses = 0;
    g_pool_stats.bytes_from_heap = 0;
    g_pool_stats.lock_wait_ns = 0;
}
