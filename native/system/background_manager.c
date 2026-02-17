/**
 * Background Process Manager Implementation
 * 
 * Manages process lifecycle, resource cleanup, and background constraints
 */

#include "background_manager.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <android/log.h>

#define LOG_TAG "BgManager"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

#define MAX_PROCESSES 64
#define MAX_CALLBACKS 8
#define LOW_MEMORY_THRESHOLD_MB 100

/**
 * Process entry structure
 */
typedef struct {
    pid_t pid;
    bg_priority_t priority;
    int32_t nice_value;
    int active;
} process_entry_t;

/**
 * Background manager structure
 */
struct bg_manager {
    pthread_mutex_t lock;
    bg_state_t current_state;
    process_entry_t processes[MAX_PROCESSES];
    int process_count;
    
    bg_state_callback state_callbacks[MAX_CALLBACKS];
    void *state_callback_data[MAX_CALLBACKS];
    int state_callback_count;
    
    bg_constraint_callback constraint_callbacks[MAX_CALLBACKS];
    void *constraint_callback_data[MAX_CALLBACKS];
    int constraint_callback_count;
};

/**
 * Map priority to nice value
 */
static int32_t priority_to_nice(bg_priority_t priority) {
    switch (priority) {
        case PRIORITY_CRITICAL:     return -10;
        case PRIORITY_HIGH:         return -5;
        case PRIORITY_NORMAL:       return 0;
        case PRIORITY_LOW:          return 5;
        case PRIORITY_BACKGROUND:   return 15;
        default:                    return 0;
    }
}

/**
 * Read memory info from /proc/meminfo
 */
static int read_meminfo(const char *field, uint32_t *value_mb) {
    FILE *fp = fopen("/proc/meminfo", "r");
    if (!fp) return -1;
    
    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        uint32_t val_kb;
        if (sscanf(line, "%s %u kB", (char*)field, &val_kb) == 2) {
            *value_mb = val_kb / 1024;
            fclose(fp);
            return 0;
        }
    }
    
    fclose(fp);
    return -1;
}

/**
 * Read process memory stats
 */
static int read_process_memory(pid_t pid, uint32_t *rss_mb, uint32_t *vms_mb) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/statm", pid);
    
    FILE *fp = fopen(path, "r");
    if (!fp) return -1;
    
    unsigned long vms, rss;
    if (fscanf(fp, "%lu %lu", &vms, &rss) != 2) {
        fclose(fp);
        return -1;
    }
    
    fclose(fp);
    
    long page_size = sysconf(_SC_PAGE_SIZE);
    *vms_mb = (vms * page_size) / (1024 * 1024);
    *rss_mb = (rss * page_size) / (1024 * 1024);
    
    return 0;
}

/**
 * Create background manager
 */
bg_manager_t* bg_manager_create(void) {
    bg_manager_t *manager = (bg_manager_t*)malloc(sizeof(bg_manager_t));
    if (!manager) return NULL;
    
    memset(manager, 0, sizeof(bg_manager_t));
    pthread_mutex_init(&manager->lock, NULL);
    manager->current_state = BG_STATE_FOREGROUND;
    manager->process_count = 0;
    manager->state_callback_count = 0;
    manager->constraint_callback_count = 0;
    
    LOGI("Background manager created");
    return manager;
}

/**
 * Destroy background manager
 */
void bg_manager_destroy(bg_manager_t *manager) {
    if (!manager) return;
    
    pthread_mutex_lock(&manager->lock);
    
    // Cleanup processes
    for (int i = 0; i < manager->process_count; i++) {
        if (manager->processes[i].active) {
            bg_manager_graceful_shutdown(manager, manager->processes[i].pid, 5000);
        }
    }
    
    pthread_mutex_unlock(&manager->lock);
    pthread_mutex_destroy(&manager->lock);
    
    free(manager);
    LOGI("Background manager destroyed");
}

/**
 * Register state callback
 */
int bg_manager_register_state_callback(bg_manager_t *manager,
                                       bg_state_callback callback,
                                       void *userdata) {
    if (!manager || !callback) return -1;
    
    pthread_mutex_lock(&manager->lock);
    
    if (manager->state_callback_count >= MAX_CALLBACKS) {
        pthread_mutex_unlock(&manager->lock);
        return -1;
    }
    
    manager->state_callbacks[manager->state_callback_count] = callback;
    manager->state_callback_data[manager->state_callback_count] = userdata;
    manager->state_callback_count++;
    
    pthread_mutex_unlock(&manager->lock);
    return 0;
}

/**
 * Register constraint callback
 */
int bg_manager_register_constraint_callback(bg_manager_t *manager,
                                            bg_constraint_callback callback,
                                            void *userdata) {
    if (!manager || !callback) return -1;
    
    pthread_mutex_lock(&manager->lock);
    
    if (manager->constraint_callback_count >= MAX_CALLBACKS) {
        pthread_mutex_unlock(&manager->lock);
        return -1;
    }
    
    manager->constraint_callbacks[manager->constraint_callback_count] = callback;
    manager->constraint_callback_data[manager->constraint_callback_count] = userdata;
    manager->constraint_callback_count++;
    
    pthread_mutex_unlock(&manager->lock);
    return 0;
}

/**
 * Set background state
 */
int bg_manager_set_state(bg_manager_t *manager, bg_state_t state) {
    if (!manager) return -1;
    
    pthread_mutex_lock(&manager->lock);
    
    if (manager->current_state != state) {
        bg_state_t old_state = manager->current_state;
        manager->current_state = state;
        
        LOGI("State change: %s -> %s", 
             bg_manager_state_to_string(old_state),
             bg_manager_state_to_string(state));
        
        // Call state change callbacks
        for (int i = 0; i < manager->state_callback_count; i++) {
            manager->state_callbacks[i](old_state, state, 
                                       manager->state_callback_data[i]);
        }
    }
    
    pthread_mutex_unlock(&manager->lock);
    return 0;
}

/**
 * Get current state
 */
bg_state_t bg_manager_get_state(bg_manager_t *manager) {
    if (!manager) return BG_STATE_FOREGROUND;
    
    pthread_mutex_lock(&manager->lock);
    bg_state_t state = manager->current_state;
    pthread_mutex_unlock(&manager->lock);
    
    return state;
}

/**
 * Register process
 */
int bg_manager_register_process(bg_manager_t *manager, pid_t pid, bg_priority_t priority) {
    if (!manager || pid <= 0) return -1;
    
    pthread_mutex_lock(&manager->lock);
    
    if (manager->process_count >= MAX_PROCESSES) {
        pthread_mutex_unlock(&manager->lock);
        return -1;
    }
    
    manager->processes[manager->process_count].pid = pid;
    manager->processes[manager->process_count].priority = priority;
    manager->processes[manager->process_count].nice_value = priority_to_nice(priority);
    manager->processes[manager->process_count].active = 1;
    manager->process_count++;
    
    // Set initial nice value
    if (setpriority(PRIO_PROCESS, pid, manager->processes[manager->process_count-1].nice_value) == 0) {
        LOGI("Registered process %d with priority %d", pid, priority);
    }
    
    pthread_mutex_unlock(&manager->lock);
    return 0;
}

/**
 * Unregister process
 */
int bg_manager_unregister_process(bg_manager_t *manager, pid_t pid) {
    if (!manager || pid <= 0) return -1;
    
    pthread_mutex_lock(&manager->lock);
    
    for (int i = 0; i < manager->process_count; i++) {
        if (manager->processes[i].pid == pid) {
            manager->processes[i].active = 0;
            LOGI("Unregistered process %d", pid);
            pthread_mutex_unlock(&manager->lock);
            return 0;
        }
    }
    
    pthread_mutex_unlock(&manager->lock);
    return -1;
}

/**
 * Set process priority
 */
int bg_manager_set_process_priority(bg_manager_t *manager, pid_t pid, bg_priority_t priority) {
    if (!manager || pid <= 0) return -1;
    
    pthread_mutex_lock(&manager->lock);
    
    int32_t nice_value = priority_to_nice(priority);
    
    for (int i = 0; i < manager->process_count; i++) {
        if (manager->processes[i].pid == pid && manager->processes[i].active) {
            manager->processes[i].priority = priority;
            manager->processes[i].nice_value = nice_value;
            
            if (setpriority(PRIO_PROCESS, pid, nice_value) == 0) {
                LOGI("Set process %d priority to %d (nice=%d)", pid, priority, nice_value);
                pthread_mutex_unlock(&manager->lock);
                return 0;
            }
            
            LOGE("Failed to set priority for process %d: %s", pid, strerror(errno));
            pthread_mutex_unlock(&manager->lock);
            return -1;
        }
    }
    
    pthread_mutex_unlock(&manager->lock);
    return -1;
}

/**
 * Graceful shutdown
 */
int bg_manager_graceful_shutdown(bg_manager_t *manager, pid_t pid, uint32_t timeout_ms) {
    if (!manager || pid <= 0) return -1;
    
    LOGI("Initiating graceful shutdown for process %d (timeout=%dms)", pid, timeout_ms);
    
    // Send SIGTERM first
    if (kill(pid, SIGTERM) != 0) {
        LOGE("Failed to send SIGTERM to process %d: %s", pid, strerror(errno));
        return -1;
    }
    
    // Wait for process to exit
    uint32_t waited = 0;
    const uint32_t check_interval = 100; // 100ms
    
    while (waited < timeout_ms) {
        int status;
        pid_t result = waitpid(pid, &status, WNOHANG);
        
        if (result == pid) {
            LOGI("Process %d exited gracefully", pid);
            return 0;
        }
        
        if (result == -1 && errno == ECHILD) {
            LOGI("Process %d already exited", pid);
            return 0;
        }
        
        usleep(check_interval * 1000);
        waited += check_interval;
    }
    
    // Force kill if timeout exceeded
    LOGD("Timeout waiting for graceful shutdown, sending SIGKILL to process %d", pid);
    if (kill(pid, SIGKILL) == 0) {
        waitpid(pid, NULL, 0);
        LOGI("Process %d force killed", pid);
        return 0;
    }
    
    LOGE("Failed to kill process %d: %s", pid, strerror(errno));
    return -1;
}

/**
 * Get memory statistics
 */
int bg_manager_get_memory_stats(bg_manager_t *manager, uint32_t *rss_mb, uint32_t *vms_mb) {
    if (!manager || !rss_mb || !vms_mb) return -1;
    
    pid_t self = getpid();
    return read_process_memory(self, rss_mb, vms_mb);
}

/**
 * Check if low memory
 */
int bg_manager_is_low_memory(bg_manager_t *manager, uint32_t *available_mb) {
    if (!manager) return -1;
    
    uint32_t memavailable;
    if (read_meminfo("MemAvailable:", &memavailable) != 0) {
        if (read_meminfo("MemFree:", &memavailable) != 0) {
            return -1;
        }
    }
    
    if (available_mb) {
        *available_mb = memavailable;
    }
    
    int is_low = memavailable < LOW_MEMORY_THRESHOLD_MB;
    
    if (is_low) {
        pthread_mutex_lock(&manager->lock);
        
        // Trigger constraint callbacks
        for (int i = 0; i < manager->constraint_callback_count; i++) {
            manager->constraint_callbacks[i]("low_memory", 8, 
                                            manager->constraint_callback_data[i]);
        }
        
        pthread_mutex_unlock(&manager->lock);
    }
    
    return is_low ? 1 : 0;
}

/**
 * Request cleanup
 */
int bg_manager_request_cleanup(bg_manager_t *manager, int severity) {
    if (!manager || severity < 1 || severity > 10) return -1;
    
    LOGI("Cleanup requested with severity %d", severity);
    
    pthread_mutex_lock(&manager->lock);
    
    // Trigger cleanup callbacks
    char severity_str[16];
    snprintf(severity_str, sizeof(severity_str), "%d", severity);
    
    for (int i = 0; i < manager->constraint_callback_count; i++) {
        manager->constraint_callbacks[i]("cleanup_request", severity, 
                                        manager->constraint_callback_data[i]);
    }
    
    pthread_mutex_unlock(&manager->lock);
    return 0;
}

/**
 * Check if doze mode
 */
int bg_manager_is_doze_mode(bg_manager_t *manager) {
    if (!manager) return -1;
    return (manager->current_state == BG_STATE_DOZE) ? 1 : 0;
}

/**
 * State to string
 */
const char* bg_manager_state_to_string(bg_state_t state) {
    switch (state) {
        case BG_STATE_FOREGROUND:   return "FOREGROUND";
        case BG_STATE_BACKGROUND:   return "BACKGROUND";
        case BG_STATE_DOZE:         return "DOZE";
        case BG_STATE_LOW_MEMORY:   return "LOW_MEMORY";
        case BG_STATE_BATTERY_SAVER: return "BATTERY_SAVER";
        default:                    return "UNKNOWN";
    }
}
