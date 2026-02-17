/**
 * background_manager.h
 * 
 * Background operation management for Android VPN service.
 * Provides lifecycle management, graceful shutdown, and resource cleanup.
 */

#ifndef BACKGROUND_MANAGER_H
#define BACKGROUND_MANAGER_H

#include <pthread.h>
#include <signal.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Background operation states */
typedef enum {
    BG_STATE_IDLE,
    BG_STATE_RUNNING,
    BG_STATE_BACKGROUND,
    BG_STATE_MEMORY_PRESSURE,
    BG_STATE_DOZE_MODE,
    BG_STATE_SHUTDOWN
} bg_state_t;

/* Background manager handle */
typedef struct bg_manager bg_manager_t;

/* Process info structure */
typedef struct {
    pid_t pid;
    int priority;
    int thread_count;
    unsigned long memory_usage;
    int cpu_usage_percent;
    int is_background;
} bg_process_info_t;

/* Callback function types */
typedef void (*bg_state_change_callback_t)(bg_state_t old_state, bg_state_t new_state);
typedef void (*bg_memory_pressure_callback_t)(int pressure_level);
typedef void (*bg_shutdown_callback_t)(void);

/**
 * Initialize background manager
 * @return Manager handle or NULL on failure
 */
bg_manager_t* bg_manager_init(void);

/**
 * Destroy background manager and cleanup resources
 */
void bg_manager_destroy(bg_manager_t* manager);

/**
 * Set current background state
 */
int bg_manager_set_state(bg_manager_t* manager, bg_state_t state);

/**
 * Get current background state
 */
bg_state_t bg_manager_get_state(bg_manager_t* manager);

/**
 * Register state change callback
 */
void bg_manager_register_state_callback(bg_manager_t* manager, 
                                        bg_state_change_callback_t callback);

/**
 * Register memory pressure callback
 */
void bg_manager_register_memory_callback(bg_manager_t* manager,
                                         bg_memory_pressure_callback_t callback);

/**
 * Register shutdown callback
 */
void bg_manager_register_shutdown_callback(bg_manager_t* manager,
                                           bg_shutdown_callback_t callback);

/**
 * Adjust process priority based on background state
 */
int bg_manager_adjust_priority(bg_manager_t* manager, pid_t pid, int is_background);

/**
 * Graceful shutdown with timeout
 */
int bg_manager_graceful_shutdown(bg_manager_t* manager, int timeout_ms);

/**
 * Get process information
 */
int bg_manager_get_process_info(bg_manager_t* manager, bg_process_info_t* info);

/**
 * Handle memory pressure level (0-100)
 */
int bg_manager_handle_memory_pressure(bg_manager_t* manager, int pressure_level);

/**
 * Check if device is in doze mode
 */
int bg_manager_is_doze_mode(bg_manager_t* manager);

/**
 * Notify background constraint (e.g., battery saver)
 */
int bg_manager_notify_constraint(bg_manager_t* manager, const char* constraint_type);

/**
 * Request resource optimization
 */
int bg_manager_optimize_resources(bg_manager_t* manager);

/**
 * Get manager statistics
 */
int bg_manager_get_stats(bg_manager_t* manager, char* buffer, int buffer_size);

#ifdef __cplusplus
}
#endif

#endif /* BACKGROUND_MANAGER_H */
