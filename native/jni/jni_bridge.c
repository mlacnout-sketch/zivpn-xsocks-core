#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>
#include "tun2socks/tun2socks.h"

#define TAG "JNI_Bridge"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)

static JavaVM *g_vm = NULL;
static jclass g_native_system_class = NULL;

// Cache class references
JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env;
    if ((*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        return -1;
    }
    g_vm = vm;

    jclass cls = (*env)->FindClass(env, "com/minizivpn/app/NativeSystem");
    if (cls) {
        g_native_system_class = (jclass)(*env)->NewGlobalRef(env, cls);
    } else {
        LOGE("Failed to find class com/minizivpn/app/NativeSystem");
    }

    return JNI_VERSION_1_6;
}

JNIEXPORT void JNI_OnUnload(JavaVM *vm, void *reserved) {
    JNIEnv *env;
    if ((*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        return;
    }
    if (g_native_system_class) {
        (*env)->DeleteGlobalRef(env, g_native_system_class);
    }
}

JNIEXPORT jint JNICALL Java_com_minizivpn_app_NativeSystem_tun2socksRun(JNIEnv *env, jclass clazz, jobjectArray args) {
    int argc = (*env)->GetArrayLength(env, args);
    char **argv = (char **)malloc(sizeof(char *) * (argc + 1));

    if (!argv) {
        LOGE("Failed to allocate argv");
        return -1;
    }

    // Convert args
    for (int i = 0; i < argc; i++) {
        jstring string = (jstring)(*env)->GetObjectArrayElement(env, args, i);
        const char *rawString = (*env)->GetStringUTFChars(env, string, 0);
        argv[i] = strdup(rawString);
        (*env)->ReleaseStringUTFChars(env, string, rawString);
        (*env)->DeleteLocalRef(env, string);
    }
    argv[argc] = NULL;

    // Run tun2socks (blocking call)
    int ret = tun2socks_main(argc, argv);

    // Cleanup
    for (int i = 0; i < argc; i++) {
        free(argv[i]);
    }
    free(argv);

    return ret;
}

JNIEXPORT void JNICALL Java_com_minizivpn_app_NativeSystem_tun2socksStop(JNIEnv *env, jclass clazz) {
    terminate();
}
