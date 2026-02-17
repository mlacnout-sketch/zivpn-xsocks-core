/**
 * Signal Handler Implementation
 */

#include "signal_handler.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <errno.h>
#include <android/log.h>

#define LOG_TAG "SignalHandler"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define MAX_SIGNALS 32

/**
 * Signal handler entry
 */
typedef struct {
    int signum;
    signal_callback callback;
    void *userdata;
    int active;
} signal_entry_t;

/**
 * Global signal handler table
 */
static signal_entry_t signal_table[MAX_SIGNALS];
static pthread_mutex_t signal_lock = PTHREAD_MUTEX_INITIALIZER;
static sigset_t original_mask;

/**
 * Unified signal handler
 */
static void unified_signal_handler(int signum) {
    pthread_mutex_lock(&signal_lock);
    
    for (int i = 0; i < MAX_SIGNALS; i++) {
        if (signal_table[i].active && signal_table[i].signum == signum) {
            if (signal_table[i].callback) {
                signal_table[i].callback(signum, signal_table[i].userdata);
            }
            break;
        }
    }
    
    pthread_mutex_unlock(&signal_lock);
}

/**
 * Initialize signal handling
 */
int signal_handler_init(void) {
    pthread_mutex_lock(&signal_lock);
    
    memset(signal_table, 0, sizeof(signal_table));
    pthread_sigmask(SIG_SETMASK, NULL, &original_mask);
    
    LOGD("Signal handler initialized");
    
    pthread_mutex_unlock(&signal_lock);
    return 0;
}

/**
 * Register signal handler
 */
int signal_handler_register(int signum, signal_callback callback, void *userdata) {
    if (!callback || signum < 0 || signum >= MAX_SIGNALS) return -1;
    
    pthread_mutex_lock(&signal_lock);
    
    // Find empty slot
    signal_entry_t *entry = NULL;
    for (int i = 0; i < MAX_SIGNALS; i++) {
        if (!signal_table[i].active) {
            entry = &signal_table[i];
            break;
        }
    }
    
    if (!entry) {
        LOGE("No available slots for signal handler");
        pthread_mutex_unlock(&signal_lock);
        return -1;
    }
    
    // Set up struct sigaction
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = unified_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    
    if (sigaction(signum, &sa, NULL) != 0) {
        LOGE("Failed to register signal handler for signal %d: %s", 
             signum, strerror(errno));
        pthread_mutex_unlock(&signal_lock);
        return -1;
    }
    
    entry->signum = signum;
    entry->callback = callback;
    entry->userdata = userdata;
    entry->active = 1;
    
    LOGD("Registered signal handler for signal %d", signum);
    
    pthread_mutex_unlock(&signal_lock);
    return 0;
}

/**
 * Unregister signal handler
 */
int signal_handler_unregister(int signum) {
    if (signum < 0 || signum >= MAX_SIGNALS) return -1;
    
    pthread_mutex_lock(&signal_lock);
    
    for (int i = 0; i < MAX_SIGNALS; i++) {
        if (signal_table[i].active && signal_table[i].signum == signum) {
            // Reset to default handler
            signal(signum, SIG_DFL);
            signal_table[i].active = 0;
            signal_table[i].callback = NULL;
            
            LOGD("Unregistered signal handler for signal %d", signum);
            
            pthread_mutex_unlock(&signal_lock);
            return 0;
        }
    }
    
    pthread_mutex_unlock(&signal_lock);
    return -1;
}

/**
 * Block signal
 */
int signal_handler_block(int signum) {
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, signum);
    
    if (pthread_sigmask(SIG_BLOCK, &set, NULL) != 0) {
        LOGE("Failed to block signal %d: %s", signum, strerror(errno));
        return -1;
    }
    
    return 0;
}

/**
 * Unblock signal
 */
int signal_handler_unblock(int signum) {
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, signum);
    
    if (pthread_sigmask(SIG_UNBLOCK, &set, NULL) != 0) {
        LOGE("Failed to unblock signal %d: %s", signum, strerror(errno));
        return -1;
    }
    
    return 0;
}

/**
 * Block all signals
 */
int signal_handler_block_all(void) {
    sigset_t set;
    sigfillset(&set);
    
    if (pthread_sigmask(SIG_BLOCK, &set, NULL) != 0) {
        LOGE("Failed to block all signals: %s", strerror(errno));
        return -1;
    }
    
    return 0;
}

/**
 * Unblock all signals
 */
int signal_handler_unblock_all(void) {
    if (pthread_sigmask(SIG_SETMASK, &original_mask, NULL) != 0) {
        LOGE("Failed to restore signal mask: %s", strerror(errno));
        return -1;
    }
    
    return 0;
}

/**
 * Cleanup
 */
void signal_handler_cleanup(void) {
    pthread_mutex_lock(&signal_lock);
    
    for (int i = 0; i < MAX_SIGNALS; i++) {
        if (signal_table[i].active) {
            signal(signal_table[i].signum, SIG_DFL);
            signal_table[i].active = 0;
        }
    }
    
    LOGD("Signal handler cleanup complete");
    
    pthread_mutex_unlock(&signal_lock);
}
