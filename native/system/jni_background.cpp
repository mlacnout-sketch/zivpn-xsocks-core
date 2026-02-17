/**
 * JNI Interface for Background Operations
 * 
 * Provides JNI bindings for background manager and signal handling
 */

#include "jni.h"
#include "background_manager.h"
#include "signal_handler.h"
#include <android/log.h>
#include <string.h>
#include <stdlib.h>

#define LOG_TAG "JniBackground"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/**
 * Global background manager instance
 */
static bg_manager_t *g_manager = NULL;

/**
 * JNI method: Initialize background manager
 */
static void jni_bg_init(JNIEnv *env, jobject thiz) {
    if (g_manager != NULL) {
        LOGI("Background manager already initialized");
        return;
    }
    
    g_manager = bg_manager_create();
    if (g_manager == NULL) {
        LOGE("Failed to create background manager");
        return;
    }
    
    signal_handler_init();
    LOGI("Background manager initialized via JNI");
}

/**
 * JNI method: Cleanup background manager
 */
static void jni_bg_cleanup(JNIEnv *env, jobject thiz) {
    if (g_manager == NULL) return;
    
    bg_manager_destroy(g_manager);
    g_manager = NULL;
    
    signal_handler_cleanup();
    LOGI("Background manager cleaned up via JNI");
}

/**
 * JNI method: Set background state
 */
static void jni_bg_set_state(JNIEnv *env, jobject thiz, jint state) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return;
    }
    
    bg_manager_set_state(g_manager, (bg_state_t)state);
}

/**
 * JNI method: Get background state
 */
static jint jni_bg_get_state(JNIEnv *env, jobject thiz) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return (jint)bg_manager_get_state(g_manager);
}

/**
 * JNI method: Register process
 */
static jint jni_bg_register_process(JNIEnv *env, jobject thiz, jint pid, jint priority) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return bg_manager_register_process(g_manager, (pid_t)pid, (bg_priority_t)priority);
}

/**
 * JNI method: Unregister process
 */
static jint jni_bg_unregister_process(JNIEnv *env, jobject thiz, jint pid) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return bg_manager_unregister_process(g_manager, (pid_t)pid);
}

/**
 * JNI method: Set process priority
 */
static jint jni_bg_set_priority(JNIEnv *env, jobject thiz, jint pid, jint priority) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return bg_manager_set_process_priority(g_manager, (pid_t)pid, (bg_priority_t)priority);
}

/**
 * JNI method: Graceful shutdown
 */
static jint jni_bg_graceful_shutdown(JNIEnv *env, jobject thiz, jint pid, jint timeout_ms) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return bg_manager_graceful_shutdown(g_manager, (pid_t)pid, (uint32_t)timeout_ms);
}

/**
 * JNI method: Get memory stats
 */
static jintArray jni_bg_get_memory_stats(JNIEnv *env, jobject thiz) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return NULL;
    }
    
    uint32_t rss_mb, vms_mb;
    if (bg_manager_get_memory_stats(g_manager, &rss_mb, &vms_mb) != 0) {
        return NULL;
    }
    
    jintArray result = env->NewIntArray(2);
    if (result == NULL) return NULL;
    
    jint values[2] = { (jint)rss_mb, (jint)vms_mb };
    env->SetIntArrayRegion(result, 0, 2, values);
    
    return result;
}

/**
 * JNI method: Check if low memory
 */
static jint jni_bg_is_low_memory(JNIEnv *env, jobject thiz) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    uint32_t available_mb;
    return bg_manager_is_low_memory(g_manager, &available_mb);
}

/**
 * JNI method: Request cleanup
 */
static jint jni_bg_request_cleanup(JNIEnv *env, jobject thiz, jint severity) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return bg_manager_request_cleanup(g_manager, severity);
}

/**
 * JNI method: Check if doze mode
 */
static jint jni_bg_is_doze_mode(JNIEnv *env, jobject thiz) {
    if (g_manager == NULL) {
        LOGE("Background manager not initialized");
        return -1;
    }
    
    return bg_manager_is_doze_mode(g_manager);
}

/**
 * JNI method: Get state string
 */
static jstring jni_bg_get_state_string(JNIEnv *env, jobject thiz, jint state) {
    const char *state_str = bg_manager_state_to_string((bg_state_t)state);
    return env->NewStringUTF(state_str);
}

/**
 * JNI method: Register signal handler
 */
static jint jni_signal_register(JNIEnv *env, jobject thiz, jint signum) {
    return signal_handler_register(signum, NULL, NULL);
}

/**
 * JNI method: Unregister signal handler
 */
static jint jni_signal_unregister(JNIEnv *env, jobject thiz, jint signum) {
    return signal_handler_unregister(signum);
}

/**
 * JNI method: Block signal
 */
static jint jni_signal_block(JNIEnv *env, jobject thiz, jint signum) {
    return signal_handler_block(signum);
}

/**
 * JNI method: Unblock signal
 */
static jint jni_signal_unblock(JNIEnv *env, jobject thiz, jint signum) {
    return signal_handler_unblock(signum);
}

/**
 * JNI method table
 */
static const JNINativeMethod method_table[] = {
    { "bgInit", "()V", (void *)jni_bg_init },
    { "bgCleanup", "()V", (void *)jni_bg_cleanup },
    { "bgSetState", "(I)V", (void *)jni_bg_set_state },
    { "bgGetState", "()I", (void *)jni_bg_get_state },
    { "bgRegisterProcess", "(II)I", (void *)jni_bg_register_process },
    { "bgUnregisterProcess", "(I)I", (void *)jni_bg_unregister_process },
    { "bgSetPriority", "(II)I", (void *)jni_bg_set_priority },
    { "bgGracefulShutdown", "(II)I", (void *)jni_bg_graceful_shutdown },
    { "bgGetMemoryStats", "()[I", (void *)jni_bg_get_memory_stats },
    { "bgIsLowMemory", "()I", (void *)jni_bg_is_low_memory },
    { "bgRequestCleanup", "(I)I", (void *)jni_bg_request_cleanup },
    { "bgIsDozeMode", "()I", (void *)jni_bg_is_doze_mode },
    { "bgGetStateString", "(I)Ljava/lang/String;", (void *)jni_bg_get_state_string },
    { "signalRegister", "(I)I", (void *)jni_signal_register },
    { "signalUnregister", "(I)I", (void *)jni_signal_unregister },
    { "signalBlock", "(I)I", (void *)jni_signal_block },
    { "signalUnblock", "(I)I", (void *)jni_signal_unblock },
};

/**
 * Register native methods
 */
static int register_native_methods(JNIEnv *env, const char *class_name,
                                   JNINativeMethod *methods, int num_methods) {
    jclass clazz = env->FindClass(class_name);
    if (clazz == NULL) {
        LOGE("Failed to find class %s", class_name);
        return JNI_FALSE;
    }
    
    if (env->RegisterNatives(clazz, methods, num_methods) < 0) {
        LOGE("Failed to register native methods for %s", class_name);
        return JNI_FALSE;
    }
    
    LOGI("Registered native methods for %s", class_name);
    return JNI_TRUE;
}

/**
 * JNI_OnLoad
 */
jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env = NULL;
    
    if (vm->GetEnv((void **)&env, JNI_VERSION_1_4) != JNI_OK) {
        LOGE("Failed to get JNI environment");
        return JNI_ERR;
    }
    
    if (!register_native_methods(env, "com/minizivpn/app/BackgroundManager",
                                (JNINativeMethod *)method_table,
                                sizeof(method_table) / sizeof(method_table[0]))) {
        LOGE("Failed to register background manager methods");
        return JNI_ERR;
    }
    
    LOGI("JNI_OnLoad completed successfully");
    return JNI_VERSION_1_4;
}

/**
 * JNI_OnUnload
 */
void JNI_OnUnload(JavaVM *vm, void *reserved) {
    LOGI("JNI_OnUnload");
    
    if (g_manager != NULL) {
        bg_manager_destroy(g_manager);
        g_manager = NULL;
    }
    
    signal_handler_cleanup();
}
