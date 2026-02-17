/*
 * Reset Handler - Improved Connection Cleanup
 * Provides robust handling of connection cleanup and resource deallocation
 * Handles TCP connections, UDP peers, and memory cleanup with error tracking
 */

#ifndef _RESET_HANDLER_H_
#define _RESET_HANDLER_H_

#include <stdint.h>
#include <sys/types.h>

#ifdef ANDROID

/* Reset handler status codes */
typedef enum {
    RESET_STATUS_SUCCESS = 0,
    RESET_STATUS_PARTIAL = 1,
    RESET_STATUS_ERROR = -1
} ResetStatus;

/* Reset handler statistics */
typedef struct {
    uint32_t tcp_connections_closed;
    uint32_t tcp_connections_aborted;
    uint32_t udp_peers_removed;
    uint32_t cleanup_errors;
    uint64_t cleanup_duration_us; /* microseconds */
} ResetStats;

/* Reset handler context */
typedef struct {
    ResetStats stats;
    int max_retries;
    int current_retry;
} ResetContext;

/**
 * Initialize reset handler context
 * 
 * @param ctx Reset context to initialize
 * @param max_retries Maximum retry attempts for cleanup operations
 * @return RESET_STATUS_SUCCESS on success, RESET_STATUS_ERROR on failure
 */
ResetStatus reset_handler_init(ResetContext *ctx, int max_retries);

/**
 * Cleanup and free reset handler context
 * 
 * @param ctx Reset context to free
 */
void reset_handler_free(ResetContext *ctx);

/**
 * Get current reset statistics
 * 
 * @param ctx Reset context
 * @return Pointer to reset statistics structure
 */
ResetStats* reset_handler_get_stats(ResetContext *ctx);

/**
 * Format reset statistics for logging
 * 
 * @param stats Reset statistics
 * @return Dynamically allocated string (caller must free)
 */
char* reset_stats_format(ResetStats *stats);

#endif /* ANDROID */

#endif /* _RESET_HANDLER_H_ */
