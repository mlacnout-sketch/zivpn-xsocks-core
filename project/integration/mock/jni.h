#ifndef JNI_H
#define JNI_H

#include <stdint.h>

#define JNIEXPORT
#define JNICALL

typedef void* jobject;
typedef void* jclass;
typedef void* jstring;
typedef int32_t jint;
typedef int64_t jlong;
typedef void* jbyteArray;
typedef unsigned char jboolean;

struct JNINativeInterface_;
typedef const struct JNINativeInterface_ *JNIEnv;

struct JNINativeInterface_ {
    void* reserved0;
    void* reserved1;
    void* reserved2;
    void* reserved3;

    jint (*GetVersion)(JNIEnv*);

    jclass (*DefineClass)(JNIEnv*, const char*, jobject, const jbyteArray, jint);
    jclass (*FindClass)(JNIEnv*, const char*);

    // ... skipping many ...

    const char* (*GetStringUTFChars)(JNIEnv*, jstring, jboolean*);
    void (*ReleaseStringUTFChars)(JNIEnv*, jstring, const char*);

    jint (*GetArrayLength)(JNIEnv*, jbyteArray);

    void* (*GetPrimitiveArrayCritical)(JNIEnv*, jbyteArray, jboolean*);
    void (*ReleasePrimitiveArrayCritical)(JNIEnv*, jbyteArray, void*, jint);
};

#endif
