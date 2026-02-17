/**
 * JNI Background Operations Interface
 * 
 * Provides JNI bindings for background management,
 * allowing Kotlin/Android layer to control native background operations.
 */

#include "jni.h"
#include "background_manager.h"
#include <android/log.h>
#include <cstring>
#include <unistd.h>

#define LOG_TAG "JNI_BG"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Global background manager instance */
static bg_manager_t *g_bg_manager = nullptr;

/**
 * Native state change callback wrapper
 */
static void native_state_callback(bg_state_t old_state, bg_state_t new_state, void *userdata) {
    JNIEnv *env = static_cast<JNIEnv*>(userdata);
    if (!env) return;
    
    LOGI("Background state changed: %s -> %s", 
         bg_manager_state_to_string(old_state),
         bg_manager_state_to_string(new_state));
}

/**
 * Native constraint callback wrapper
 */
static void native_constraint_callback(const char *constraint, int severity, void *userdata) {
    JNIEnv *env = static_cast<JNIEnv*>(userdata);
    if (!env) return;
    
    LOGI("Resource constraint: %s (severity: %d)", constraint, severity);
}

/**
 * Initialize background manager - called once during JNI load
 * Signature: ()V
 */
static void init_background_manager(JNIEnv *env, jobject thiz) {
    if (g_bg_manager != nullptr) {
        LOGI("Background manager already initialized");
        return;
    }
    
    g_bg_manager = bg_manager_create();
    if (!g_bg_manager) {
        LOGE("Failed to create background manager");
        return;
    }
    
    /* Register callbacks */
    bg_manager_register_state_callback(g_bg_manager, native_state_callback, env);
    bg_manager_register_constraint_callback(g_bg_manager, native_constraint_callback, env);
    
    LOGI("Background manager initialized");
}

/**
 * Cleanup background manager
 * Signature: ()V
 */
static void cleanup_background_manager(JNIEnv *env, jobject thiz) {
    if (!g_bg_manager) return;
    
    bg_manager_destroy(g_bg_manager);
    g_bg_manager = nullptr;
    
    LOGI("Background manager cleaned up");
}

/**
 * Set background state
 * Signature: (I)V
 */
static void set_background_state(JNIEnv *env, jobject thiz, jint state) {
    if (!g_bg_manager) {
        LOGE("Background manager not initialized");
        return;
    }
    
    if (bg_manager_set_state(g_bg_manager, (bg_state_t)state) == 0) {
        LOGI("Background state set to %d", state);
    } else {
        LOGE("Failed to set background state");
    }
}

/**
 * Get background state
 * Signature: ()I
 */
static jint get_background_state(JNIEnv *env, jobject thiz) {
    if (!g_bg_manager) {
        return (jint)BG_STATE_FOREGROUND;
    }
    
    return (jint)bg_manager_get_state(g_bg_manager);
}

/**
 * Register process for background management
 * Signature: (II)I
 */
static jint register_process(JNIEnv *env, jobject thiz, jint pid, jint priority) {
    if (!g_bg_manager) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    if (bg_manager_register_process(g_bg_manager, (pid_t)pid, (bg_priority_t)priority) == 0) {
        LOGI("Process %d registered with priority %d", pid, priority);
        return 0;
    }
    
    LOGE("Failed to register process %d", pid);
    return -1;
}

/**
 * Unregister process
 * Signature: (I)I
 */
static jint unregister_process(JNIEnv *env, jobject thiz, jint pid) {
    if (!g_bg_manager) {
        return -1;
    }
    
    if (bg_manager_unregister_process(g_bg_manager, (pid_t)pid) == 0) {
        LOGI("Process %d unregistered", pid);
        return 0;
    }
    
    return -1;
}

/**
 * Set process priority
 * Signature: (II)I
 */
static jint set_process_priority(JNIEnv *env, jobject thiz, jint pid, jint priority) {
    if (!g_bg_manager) {
        return -1;
    }
    
    return (jint)bg_manager_set_process_priority(g_bg_manager, (pid_t)pid, (bg_priority_t)priority);
}

/**
 * Gracefully shutdown process
 * Signature: (II)I
 */
static jint graceful_shutdown(JNIEnv *env, jobject thiz, jint pid, jint timeout_ms) {
    if (!g_bg_manager) {
        return -1;
    }
    
    return (jint)bg_manager_graceful_shutdown(g_bg_manager, (pid_t)pid, (uint32_t)timeout_ms);
}

/**
 * Get memory statistics
 * Signature: ([I)I
 */
static jint get_memory_stats(JNIEnv *env, jobject thiz, jintArray stats) {
    if (!g_bg_manager) {
        return -1;
    }
    
    uint32_t rss_mb = 0, vms_mb = 0;
    if (bg_manager_get_memory_stats(g_bg_manager, &rss_mb, &vms_mb) != 0) {
        return -1;
    }
    
    jint buffer[2] = {(jint)rss_mb, (jint)vms_mb};
    env->SetIntArrayRegion(stats, 0, 2, buffer);
    
    return 0;
}

/**
 * Check if low memory condition exists
 * Signature: ([I)I
 */
static jint is_low_memory(JNIEnv *env, jobject thiz, jintArray available) {
    if (!g_bg_manager) {
        return -1;
    }
    
    uint32_t avail_mb = 0;
    int result = bg_manager_is_low_memory(g_bg_manager, &avail_mb);
    
    if (result != -1) {
        jint buf[1] = {(jint)avail_mb};
        env->SetIntArrayRegion(available, 0, 1, buf);
    }
    
    return (jint)result;
}

/**
 * Request resource cleanup
 * Signature: (I)I
 */
static jint request_cleanup(JNIEnv *env, jobject thiz, jint severity) {
    if (!g_bg_manager) {
        return -1;
    }
    
    return (jint)bg_manager_request_cleanup(g_bg_manager, (int)severity);
}

/**
 * Check if system is in doze mode
 * Signature: ()I
 */
static jint is_doze_mode(JNIEnv *env, jobject thiz) {
    if (!g_bg_manager) {
        return -1;
    }
    
    return (jint)bg_manager_is_doze_mode(g_bg_manager);
}

/**
 * Get state as string
 * Signature: (I)Ljava/lang/String;
 */
static jstring state_to_string(JNIEnv *env, jobject thiz, jint state) {
    const char *str = bg_manager_state_to_string((bg_state_t)state);
    return env->NewStringUTF(str);
}

/* JNI method table */
static const JNINativeMethod g_methods[] = {
    {"initBackgroundManager", "()V", (void*)init_background_manager},
    {"cleanupBackgroundManager", "()V", (void*)cleanup_background_manager},
    {"setBackgroundState", "(I)V", (void*)set_background_state},
    {"getBackgroundState", "()I", (void*)get_background_state},
    {"registerProcess", "(II)I", (void*)register_process},
    {"unregisterProcess", "(I)I", (void*)unregister_process},
    {"setProcessPriority", "(II)I", (void*)set_process_priority},
    {"gracefulShutdown", "(II)I", (void*)graceful_shutdown},
    {"getMemoryStats", "([I)I", (void*)get_memory_stats},
    {"isLowMemory", "([I)I", (void*)is_low_memory},
    {"requestCleanup", "(I)I", (void*)request_cleanup},
    {"isDozeMode", "()I", (void*)is_doze_mode},
    {"stateToString", "(I)Ljava/lang/String;", (void*)state_to_string},
};

static const char *g_class_name = "com/minizivpn/app/BackgroundOperationManager";

/**
 * Register native methods
 */
static jint register_native_methods(JNIEnv *env) {
    jclass clazz = env->FindClass(g_class_name);
    if (!clazz) {
        LOGE("Unable to find class %s", g_class_name);
        return JNI_FALSE;
    }
    
    if (env->RegisterNatives(clazz, g_methods, sizeof(g_methods) / sizeof(g_methods[0])) < 0) {
        LOGE("RegisterNatives failed for %s", g_class_name);
        return JNI_FALSE;
    }
    
    LOGI("Background JNI methods registered");
    return JNI_TRUE;
}

/**
 * JNI_OnLoad - called when native library is loaded
 */
jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env = nullptr;
    
    if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        LOGE("GetEnv failed");
        return -1;
    }
    
    if (!register_native_methods(env)) {
        LOGE("Failed to register native methods");
        return -1;
    }
    
    LOGI("JNI_OnLoad completed");
    return JNI_VERSION_1_6;
}

/**
 * JNI_OnUnload - called when native library is unloaded
 */
void JNI_OnUnload(JavaVM *vm, void *reserved) {
    if (g_bg_manager) {
        bg_manager_destroy(g_bg_manager);
        g_bg_manager = nullptr;
    }
    
    LOGI("JNI_OnUnload");
}
