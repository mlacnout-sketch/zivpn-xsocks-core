#include <jni.h>
#include <string.h>

// Forward declarations of wrapped functions
int hysteria_connect(const char *server, int port, const char *auth);
int hysteria_send(int handle, const void *data, size_t len);
int hysteria_recv(int handle, void *data, size_t len);
void hysteria_close(int handle);

JNIEXPORT jint JNICALL Java_com_minizivpn_app_core_Hysteria_connect(JNIEnv *env, jclass clazz, jstring server, jint port, jstring auth) {
    const char *server_cstr = (*env)->GetStringUTFChars(env, server, 0);
    const char *auth_cstr = (*env)->GetStringUTFChars(env, auth, 0);

    int handle = hysteria_connect(server_cstr, port, auth_cstr);

    (*env)->ReleaseStringUTFChars(env, server, server_cstr);
    (*env)->ReleaseStringUTFChars(env, auth, auth_cstr);

    return handle;
}

JNIEXPORT jint JNICALL Java_com_minizivpn_app_core_Hysteria_send(JNIEnv *env, jclass clazz, jint handle, jbyteArray data) {
    jint len = (*env)->GetArrayLength(env, data);
    void *buf = (*env)->GetPrimitiveArrayCritical(env, data, 0);

    int sent = hysteria_send(handle, buf, len);

    (*env)->ReleasePrimitiveArrayCritical(env, data, buf, 0);

    return sent;
}

JNIEXPORT jint JNICALL Java_com_minizivpn_app_core_Hysteria_recv(JNIEnv *env, jclass clazz, jint handle, jbyteArray data) {
    jint len = (*env)->GetArrayLength(env, data);
    void *buf = (*env)->GetPrimitiveArrayCritical(env, data, 0);

    int received = hysteria_recv(handle, buf, len);

    (*env)->ReleasePrimitiveArrayCritical(env, data, buf, 0);

    return received;
}

JNIEXPORT void JNICALL Java_com_minizivpn_app_core_Hysteria_close(JNIEnv *env, jclass clazz, jint handle) {
    hysteria_close(handle);
}
