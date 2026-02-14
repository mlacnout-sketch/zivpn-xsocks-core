LOCAL_PATH := $(call my-dir)

# ═══ ORIGINAL LIBUZ (PREBUILT) ═══
# Assuming libuz.so is available in prebuilts or similar
# For this wrapper to work, it needs to link against the original library
# or load it dynamically. Since it uses dlopen, we don't strictly need to link it
# at build time, but we might want to copy it.

# ═══ OPTIMIZED WRAPPER ═══
include $(CLEAR_VARS)
LOCAL_MODULE := uz_optimized
LOCAL_SRC_FILES := libuz_wrapper.c
LOCAL_CFLAGS := -O3 -Wall -Werror
LOCAL_LDLIBS := -llog -ldl
include $(BUILD_SHARED_LIBRARY)
