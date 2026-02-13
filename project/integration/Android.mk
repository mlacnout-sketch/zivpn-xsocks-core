LOCAL_PATH := $(call my-dir)

# ═══ ORIGINAL LIBUZ (PREBUILT) ═══
include $(CLEAR_VARS)
LOCAL_MODULE := uz_original
LOCAL_SRC_FILES := ../binaries/original/libuz.so
include $(PREBUILT_SHARED_LIBRARY)

# ═══ OPTIMIZED WRAPPER ═══
include $(CLEAR_VARS)
LOCAL_MODULE := uz_optimized
LOCAL_SRC_FILES := libuz_wrapper.c jni_wrapper.c
LOCAL_CFLAGS := -O3 -Wall -Werror
LOCAL_SHARED_LIBRARIES := uz_original
LOCAL_LDLIBS := -llog -ldl
include $(BUILD_SHARED_LIBRARY)
