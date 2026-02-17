/**
 * Signal Handler Utilities
 * 
 * Provides safe signal handling for background operations
 */

#ifndef SIGNAL_HANDLER_H
#define SIGNAL_HANDLER_H

#include <signal.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Signal handler callback
 */
typedef void (*signal_callback)(int signum, void *userdata);

/**
 * Initialize signal handling
 * @return 0 on success, -1 on error
 */
int signal_handler_init(void);

/**
 * Register signal handler
 * @param signum Signal number
 * @param callback Callback function
 * @param userdata User-provided data
 * @return 0 on success, -1 on error
 */
int signal_handler_register(int signum, signal_callback callback, void *userdata);

/**
 * Unregister signal handler
 * @param signum Signal number
 * @return 0 on success, -1 on error
 */
int signal_handler_unregister(int signum);

/**
 * Block signal for current thread
 * @param signum Signal number
 * @return 0 on success, -1 on error
 */
int signal_handler_block(int signum);

/**
 * Unblock signal for current thread
 * @param signum Signal number
 * @return 0 on success, -1 on error
 */
int signal_handler_unblock(int signum);

/**
 * Block all signals
 * @return 0 on success, -1 on error
 */
int signal_handler_block_all(void);

/**
 * Unblock all signals
 * @return 0 on success, -1 on error
 */
int signal_handler_unblock_all(void);

/**
 * Cleanup signal handling
 */
void signal_handler_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* SIGNAL_HANDLER_H */
