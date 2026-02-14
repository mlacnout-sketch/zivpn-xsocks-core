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

// ═══ OPTIMIZATION CONFIG ═══
#define MAX_CONNECTIONS 8
#define BATCH_SIZE 16
#define BATCH_TIMEOUT_MS 10

typedef struct {
    unsigned char data[8192];
    size_t len;
} packet_buffer_t;

typedef struct {
    int handle;
    char server[256];
    int port;
    int in_use;
    time_t last_used;

    // Per-connection Batching
    packet_buffer_t batch[BATCH_SIZE];
    int batch_count;
    struct timespec last_flush;
    pthread_mutex_t lock;
} connection_t;

static connection_t connection_pool[MAX_CONNECTIONS];
static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;

static void init_connection_pool(void) {
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        connection_pool[i].handle = -1;
        connection_pool[i].in_use = 0;
        connection_pool[i].batch_count = 0;
        pthread_mutex_init(&connection_pool[i].lock, NULL);
        clock_gettime(CLOCK_MONOTONIC, &connection_pool[i].last_flush);
    }
}

// Unused but kept for future use
static void release_connection(int handle) __attribute__((unused));
static void release_connection(int handle) {
    pthread_mutex_lock(&pool_lock);

    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (connection_pool[i].handle == handle) {
            connection_pool[i].in_use = 0;
            connection_pool[i].last_used = time(NULL);
            // We should arguably flush here, but if released, maybe handle is closed?
            break;
        }
    }

    pthread_mutex_unlock(&pool_lock);
}

static void flush_connection_batch(connection_t *conn) {
    if (conn->batch_count == 0) return;

    // Calculate size
    size_t total_len = 0;
    for (int i = 0; i < conn->batch_count; i++) {
        total_len += conn->batch[i].len;
    }

    unsigned char *combined = malloc(total_len);
    if (!combined) {
         LOGE("Failed to allocate memory for batch flush");
         conn->batch_count = 0;
         return;
    }

    size_t offset = 0;
    for (int i = 0; i < conn->batch_count; i++) {
        memcpy(combined + offset, conn->batch[i].data, conn->batch[i].len);
        offset += conn->batch[i].len;
    }

    if (orig_hysteria_send) {
        orig_hysteria_send(conn->handle, combined, total_len);
    }

    free(combined);
    conn->batch_count = 0;
    clock_gettime(CLOCK_MONOTONIC, &conn->last_flush);
}

// ═══ WRAPPED FUNCTIONS ═══

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
                connection_pool[i].batch_count = 0; // Reset batch
                break;
            }
        }
        pthread_mutex_unlock(&pool_lock);
    }

    return handle;
}

int hysteria_send(int handle, const void *data, size_t len) {
    if (!orig_hysteria_send) return -1;

    connection_t *conn = NULL;

    // Find connection in pool
    pthread_mutex_lock(&pool_lock);
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (connection_pool[i].in_use && connection_pool[i].handle == handle) {
            conn = &connection_pool[i];
            break;
        }
    }
    pthread_mutex_unlock(&pool_lock);

    if (!conn) {
        // Not pooled, just send
        return orig_hysteria_send(handle, data, len);
    }

    pthread_mutex_lock(&conn->lock);

    // Check if we should flush (batch full or timeout)
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long elapsed_ms = (now.tv_sec - conn->last_flush.tv_sec) * 1000 +
                     (now.tv_nsec - conn->last_flush.tv_nsec) / 1000000;

    if (conn->batch_count >= BATCH_SIZE || elapsed_ms >= BATCH_TIMEOUT_MS) {
        flush_connection_batch(conn);
    }

    // Add to batch
    if (len <= sizeof(conn->batch[0].data)) {
        memcpy(conn->batch[conn->batch_count].data, data, len);
        conn->batch[conn->batch_count].len = len;
        conn->batch_count++;
    } else {
        // Too large for batching, send immediately
        if (conn->batch_count > 0) flush_connection_batch(conn);
        orig_hysteria_send(handle, data, len);
    }

    pthread_mutex_unlock(&conn->lock);
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
    libuz_handle = dlopen("libuz.so", RTLD_NOW);
    if (!libuz_handle) {
        // Just return if not found, avoids crashing if lib is missing during dev
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

    LOGD("LibUZ wrapper initialized successfully");
}

__attribute__((destructor))
static void cleanup_wrapper(void) {
    if (libuz_handle) {
        dlclose(libuz_handle);
    }
}
