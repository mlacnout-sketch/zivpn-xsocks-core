/*
 * Reset Handler Implementation - Improved Connection Cleanup
 * Provides robust handling of connection cleanup and resource deallocation
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/types.h>
#include <inttypes.h>

#include "reset_handler.h"

#ifdef ANDROID

/**
 * Initialize reset handler context
 */
ResetStatus reset_handler_init(ResetContext *ctx, int max_retries)
{
    if (!ctx) {
        return RESET_STATUS_ERROR;
    }
    
    if (max_retries < 1) {
        max_retries = 1;
    }
    
    memset(ctx, 0, sizeof(ResetContext));
    ctx->max_retries = max_retries;
    ctx->current_retry = 0;
    
    return RESET_STATUS_SUCCESS;
}

/**
 * Cleanup and free reset handler context
 */
void reset_handler_free(ResetContext *ctx)
{
    if (ctx) {
        memset(ctx, 0, sizeof(ResetContext));
    }
}

/**
 * Get current reset statistics
 */
ResetStats* reset_handler_get_stats(ResetContext *ctx)
{
    if (!ctx) {
        return NULL;
    }
    return &ctx->stats;
}

/**
 * Format reset statistics for logging
 * Caller must free the returned string
 */
char* reset_stats_format(ResetStats *stats)
{
    char *buffer = NULL;
    int size;
    
    if (!stats) {
        return NULL;
    }
    
    /* Calculate buffer size needed */
    size = snprintf(NULL, 0,
        "Reset Statistics: TCP_closed=%u, TCP_aborted=%u, UDP_removed=%u, "
        "Errors=%u, Duration=%" PRIu64 "us",
        stats->tcp_connections_closed,
        stats->tcp_connections_aborted,
        stats->udp_peers_removed,
        stats->cleanup_errors,
        stats->cleanup_duration_us);
    
    if (size < 0) {
        return NULL;
    }
    
    /* Allocate buffer and format */
    buffer = (char *)malloc(size + 1);
    if (!buffer) {
        return NULL;
    }
    
    snprintf(buffer, size + 1,
        "Reset Statistics: TCP_closed=%u, TCP_aborted=%u, UDP_removed=%u, "
        "Errors=%u, Duration=%" PRIu64 "us",
        stats->tcp_connections_closed,
        stats->tcp_connections_aborted,
        stats->udp_peers_removed,
        stats->cleanup_errors,
        stats->cleanup_duration_us);
    
    return buffer;
}

#endif /* ANDROID */
