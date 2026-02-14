// File: native/integration/libuz_wrapper.c

/**
 * Optimized wrapper around libuz.so
 * Adds caching, batching, and other optimizations
 */

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>
#include <android/log.h>

#define TAG "LibUZ-Wrapper"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ═══ ORIGINAL FUNCTION POINTERS ═══
static void *libuz_handle = NULL;

typedef int (*hysteria_connect_t)(const char *server, int port, const char *auth);
typedef int (*hysteria_send_t)(int handle, const void *data, size_t len);
typedef int (*hysteria_recv_t)(int handle, void *data, size_t len);

static hysteria_connect_t orig_hysteria_connect = NULL;
static hysteria_send_t orig_hysteria_send = NULL;
static hysteria_recv_t orig_hysteria_recv = NULL;

// ═══ OPTIMIZATION: CONNECTION POOL ═══
#define MAX_CONNECTIONS 8

typedef struct {
    int handle;
    char server[256];
    int port;
    int in_use;
    time_t last_used;
} connection_t;

static connection_t connection_pool[MAX_CONNECTIONS];
static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;

static void init_connection_pool(void) {
    memset(connection_pool, 0, sizeof(connection_pool));
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        connection_pool[i].handle = -1;
    }
}

static int get_pooled_connection(const char *server, int port) {
    pthread_mutex_lock(&pool_lock);

    // Find existing connection
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (connection_pool[i].handle >= 0 &&
            strcmp(connection_pool[i].server, server) == 0 &&
            connection_pool[i].port == port &&
            !connection_pool[i].in_use) {

            connection_pool[i].in_use = 1;
            connection_pool[i].last_used = time(NULL);

            pthread_mutex_unlock(&pool_lock);
            LOGD("Reusing pooled connection %d", i);
            return connection_pool[i].handle;
        }
    }

    pthread_mutex_unlock(&pool_lock);
    return -1;  // Not found
}

// Unused but kept for future use
static void release_connection(int handle) __attribute__((unused));
static void release_connection(int handle) {
    pthread_mutex_lock(&pool_lock);

    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (connection_pool[i].handle == handle) {
            connection_pool[i].in_use = 0;
            connection_pool[i].last_used = time(NULL);
            break;
        }
    }

    pthread_mutex_unlock(&pool_lock);
}

// ═══ OPTIMIZATION: SEND BATCHING ═══
#define BATCH_SIZE 16
#define BATCH_TIMEOUT_MS 10

typedef struct {
    unsigned char data[8192];
    size_t len;
} batch_buffer_t;

static batch_buffer_t send_batch[BATCH_SIZE];
static int batch_count = 0;
static pthread_mutex_t batch_lock = PTHREAD_MUTEX_INITIALIZER;
static struct timespec last_flush;

static void flush_send_batch(int handle) {
    if (batch_count == 0) return;

    LOGD("Flushing batch: %d packets", batch_count);

    // Combine all batched data
    size_t total_len = 0;
    for (int i = 0; i < batch_count; i++) {
        total_len += send_batch[i].len;
    }

    unsigned char *combined = malloc(total_len);
    if (!combined) {
        LOGE("Failed to allocate memory for batch flush");
        batch_count = 0;
        return;
    }

    size_t offset = 0;

    for (int i = 0; i < batch_count; i++) {
        memcpy(combined + offset, send_batch[i].data, send_batch[i].len);
        offset += send_batch[i].len;
    }

    // Single send call instead of multiple
    if (orig_hysteria_send) {
        orig_hysteria_send(handle, combined, total_len);
    }

    free(combined);
    batch_count = 0;
    clock_gettime(CLOCK_MONOTONIC, &last_flush);
}

// ═══ WRAPPED FUNCTIONS ═══

int hysteria_connect(const char *server, int port, const char *auth) {
    LOGD("hysteria_connect(%s, %d)", server, port);

    if (!orig_hysteria_connect) return -1;

    // Try to get from pool
    int handle = get_pooled_connection(server, port);
    if (handle >= 0) {
        return handle;
    }

    // Call original
    handle = orig_hysteria_connect(server, port, auth);

    if (handle >= 0) {
        // Add to pool
        pthread_mutex_lock(&pool_lock);
        for (int i = 0; i < MAX_CONNECTIONS; i++) {
            if (connection_pool[i].handle < 0) {
                connection_pool[i].handle = handle;
                strncpy(connection_pool[i].server, server, sizeof(connection_pool[i].server) - 1);
                connection_pool[i].server[sizeof(connection_pool[i].server) - 1] = '\0';
                connection_pool[i].port = port;
                connection_pool[i].in_use = 1;
                connection_pool[i].last_used = time(NULL);
                break;
            }
        }
        pthread_mutex_unlock(&pool_lock);
    }

    return handle;
}

int hysteria_send(int handle, const void *data, size_t len) {
    if (!orig_hysteria_send) return -1;

    pthread_mutex_lock(&batch_lock);

    // Check if we should flush (batch full or timeout)
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long elapsed_ms = (now.tv_sec - last_flush.tv_sec) * 1000 +
                     (now.tv_nsec - last_flush.tv_nsec) / 1000000;

    if (batch_count >= BATCH_SIZE || elapsed_ms >= BATCH_TIMEOUT_MS) {
        flush_send_batch(handle);
    }

    // Add to batch
    if (len <= sizeof(send_batch[0].data)) {
        memcpy(send_batch[batch_count].data, data, len);
        send_batch[batch_count].len = len;
        batch_count++;
    } else {
        // Too large for batching, send immediately
        // Flush existing batch first to maintain order
        if (batch_count > 0) {
            flush_send_batch(handle);
        }
        pthread_mutex_unlock(&batch_lock);
        return orig_hysteria_send(handle, data, len);
    }

    pthread_mutex_unlock(&batch_lock);
    return len;
}

int hysteria_recv(int handle, void *data, size_t len) {
    if (!orig_hysteria_recv) return -1;
    // No batching for recv, just pass through
    return orig_hysteria_recv(handle, data, len);
}

// ═══ LIBRARY INITIALIZATION ═══

__attribute__((constructor))
static void init_wrapper(void) {
    LOGD("Initializing LibUZ wrapper");

    // Load original library
    // The path here assumes the library is in the library path
    // In Android, it might be loaded automatically or we might need the full path
    libuz_handle = dlopen("libuz.so", RTLD_NOW);
    if (!libuz_handle) {
        // Fallback or log error
        // LOGE("Failed to load libuz.so: %s", dlerror());
        // For testing purposes, we might just return if not found
        return;
    }

    // Resolve functions
    orig_hysteria_connect = (hysteria_connect_t)dlsym(libuz_handle, "hysteria_connect");
    orig_hysteria_send = (hysteria_send_t)dlsym(libuz_handle, "hysteria_send");
    orig_hysteria_recv = (hysteria_recv_t)dlsym(libuz_handle, "hysteria_recv");

    if (!orig_hysteria_connect || !orig_hysteria_send || !orig_hysteria_recv) {
        LOGE("Failed to resolve functions");
        return;
    }

    // Initialize optimizations
    init_connection_pool();
    clock_gettime(CLOCK_MONOTONIC, &last_flush);

    LOGD("LibUZ wrapper initialized successfully");
}

__attribute__((destructor))
static void cleanup_wrapper(void) {
    if (libuz_handle) {
        dlclose(libuz_handle);
    }
}
