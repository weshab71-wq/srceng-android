#!/usr/bin/env bash
set -e

echo "=== Starting Full Build Script ==="

# 1. Environment & Setup
export WORKSPACE_DIR=$(pwd)
export NDK_HOME=$WORKSPACE_DIR/android-ndk-r10e

if [ ! -d "$NDK_HOME" ]; then
    echo "Downloading NDK r10e..."
    wget -q https://dl.google.com/android/repository/android-ndk-r10e-linux-x86_64.zip -O /tmp/ndk.zip
    unzip -q /tmp/ndk.zip -d $WORKSPACE_DIR
    rm -f /tmp/ndk.zip
fi

# 2. Fix Toolchain GCC Wrappers for NDK r10e
GCC_WRAPPER_DIR=$WORKSPACE_DIR/gcc_wrappers
mkdir -p $GCC_WRAPPER_DIR

REAL_GCC=$NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-gcc
REAL_GPP=$NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-g++

cat << EOF > $GCC_WRAPPER_DIR/arm-linux-androideabi-gcc
#!/bin/bash
ARGS=()
for arg in "\$@"; do
    case \$arg in
        -mthumb|-marm|-Wl,--fix-cortex-a8|-Wl,--no-undefined|-Wl,-z,defs) ;;
        *) ARGS+=("\$arg") ;;
    esac
done
exec "$REAL_GCC" "\${ARGS[@]}"
EOF

cat << EOF > $GCC_WRAPPER_DIR/arm-linux-androideabi-g++
#!/bin/bash
ARGS=()
for arg in "\$@"; do
    case \$arg in
        -mthumb|-marm|-Wl,--fix-cortex-a8|-Wl,--no-undefined|-Wl,-z,defs) ;;
        *) ARGS+=("\$arg") ;;
    esac
done
exec "$REAL_GPP" "\${ARGS[@]}"
EOF

chmod +x $GCC_WRAPPER_DIR/arm-linux-androideabi-gcc
chmod +x $GCC_WRAPPER_DIR/arm-linux-androideabi-g++

export PATH=$GCC_WRAPPER_DIR:$PATH

# 3. Patch NDK Headers for Legacy Compatibility
STL_HEADER=$NDK_HOME/sources/cxx-stl/stlport/stlport/stl/_threads.h
if [ -f "$STL_HEADER" ]; then
    sed -i 's/__atomic_add/stlport_atomic_add/g' "$STL_HEADER"
fi

SYS_HEADER=$NDK_HOME/platforms/android-19/arch-arm/usr/include/sys/cdefs.h
if [ -f "$SYS_HEADER" ]; then
    sed -i 's/__attribute_const__//g' "$SYS_HEADER"
fi

# 4. Build Dependencies (libjpeg-turbo)
echo "Building libjpeg..."
rm -rf /tmp/libjpeg_src
mkdir -p /tmp/libjpeg_src
git clone --depth 1 -b 2.0.6 https://github.com/libjpeg-turbo/libjpeg-turbo.git /tmp/libjpeg_src
cd /tmp/libjpeg_src

cat << 'EOF' > jconfig.h
#ifndef JCONFIG_H
#define JCONFIG_H
#define JPEG_LIB_VERSION 62
#define LIBJPEG_TURBO_VERSION "2.0.6"
#define LIBJPEG_TURBO_VERSION_NUMBER 2000006
#define HAVE_PROTOTYPES 1
#define HAVE_UNSIGNED_CHAR 1
#define HAVE_UNSIGNED_SHORT 1
#define HAVE_STDDEF_H 1
#define HAVE_STDLIB_H 1
#define HAVE_LOCALE_H 1
#define BITS_IN_JSAMPLE 8
#define MEM_SRCDST_SUPPORTED 1
#define INLINE __inline__
#define NEED_SYS_TYPES_H 1
#endif
EOF

cat << 'EOF' > jconfigint.h
#ifndef JCONFIGINT_H
#define JCONFIGINT_H
#define BUILD "20260811"
#define PACKAGE_NAME "libjpeg-turbo"
#define VERSION "2.0.6"
#define SIZEOF_SIZE_T 4
#define INLINE __inline__
#define THREAD_LOCAL
#define HAVE_BUILTIN_CTZ 1
#define HAVE_MEMCPY 1
#define HAVE_MEMSET 1
#define RIGHT_SHIFT_IS_UNSIGNED 0
#endif
EOF

cat << 'EOF' > Android.mk
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := jpeg

LOCAL_SRC_FILES := \
    jcapimin.c jcapistd.c jccoefct.c jccolor.c jcdctmgr.c jchuff.c \
    jcinit.c jcmainct.c jcmarker.c jcmaster.c jcomapi.c jcparam.c \
    jcphuff.c jcsample.c jctrans.c jdapimin.c jdapistd.c jdatadst.c \
    jdatasrc.c jdcoefct.c jdcolor.c jddctmgr.c jdhuff.c jdmainct.c \
    jdmarker.c jdmerge.c jdpostct.c jdsample.c jdtrans.c \
    jerror.c jfdctflt.c jfdctfst.c jfdctint.c jidctflt.c jidctfst.c \
    jidctint.c jidctred.c jmemmgr.c jmemnobs.c jquant1.c jquant2.c \
    jutils.c jsimd_none.c

LOCAL_CFLAGS := -w -O3 -DJPEG_LIB_VERSION=62 -DINLINE=__inline__ -DNO_GETENV
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)
include $(BUILD_STATIC_LIBRARY)
EOF

"$NDK_HOME/ndk-build" \
    NDK_PROJECT_PATH=/tmp/libjpeg_src \
    APP_BUILD_SCRIPT=/tmp/libjpeg_src/Android.mk \
    APP_ABI=armeabi-v7a \
    APP_PLATFORM=android-19 \
    APP_STL=stlport_static \
    NDK_TOOLCHAIN_VERSION=4.9 \
    -j$(nproc --all)

cd $WORKSPACE_DIR

# 5. Clean SDL2 Build with OpenSL ES Enabled
echo "Building SDL2 natively with OpenSL ES audio support..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Disable warnings
sed -i '/-W/d' /tmp/sdl_src/Android.mk

# Stub out hid.cpp to bypass GCC 4.9 template parsing bug in hidapi
if [ -f "/tmp/sdl_src/src/hidapi/android/hid.cpp" ]; then
    cat << 'EOF' > /tmp/sdl_src/src/hidapi/android/hid.cpp
#include <stddef.h>
#include <wchar.h>

extern "C" {
    int hid_init(void) { return 0; }
    int hid_exit(void) { return 0; }
    struct hid_device_info* hid_enumerate(unsigned short vendor_id, unsigned short product_id) { return NULL; }
    void hid_free_enumeration(struct hid_device_info *devs) {}
    void* hid_open(unsigned short vendor_id, unsigned short product_id, const wchar_t *serial_number) { return NULL; }
    void* hid_open_path(const char *path, int b) { return NULL; }
    int hid_write(void *device, const unsigned char *data, size_t length) { return -1; }
    int hid_read_timeout(void *dev, unsigned char *data, size_t length, int milliseconds) { return -1; }
    int hid_read(void *device, unsigned char *data, size_t length) { return -1; }
    int hid_set_nonblocking(void *device, int nonblock) { return -1; }
    int hid_send_feature_report(void *device, const unsigned char *data, size_t length) { return -1; }
    int hid_get_feature_report(void *device, unsigned char *data, size_t length) { return -1; }
    void hid_close(void *device) {}
    int hid_get_manufacturer_string(void *device, wchar_t *string, size_t maxlen) { return -1; }
    int hid_get_product_string(void *device, wchar_t *string, size_t maxlen) { return -1; }
    int hid_get_serial_number_string(void *device, wchar_t *string, size_t maxlen) { return -1; }
    int hid_get_indexed_string(void *device, int string_index, wchar_t *string, size_t maxlen) { return -1; }
    const wchar_t* hid_error(void *device) { return NULL; }
}
EOF
fi

# Patch SDL_androidvideo.c with fallback defines for AHardwareBuffer formats
if [ -f "/tmp/sdl_src/src/video/android/SDL_androidvideo.c" ]; then
    sed -i '1s/^/#ifndef AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM\n#define AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM 1\n#endif\n#ifndef AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM\n#define AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM 2\n#endif\n#ifndef AHARDWAREBUFFER_FORMAT_R8G8B8_UNORM\n#define AHARDWAREBUFFER_FORMAT_R8G8B8_UNORM 3\n#endif\n#ifndef AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM\n#define AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM 4\n#endif\n/' /tmp/sdl_src/src/video/android/SDL_androidvideo.c
fi

# Patch SDL_egl.h with full suite of EGL 1.5 / KHR extension typedefs
if [ -f "/tmp/sdl_src/include/SDL_egl.h" ]; then
    sed -i '1s/^/#include <stdint.h>\n#include <EGL\/egl.h>\n#include <EGL\/eglplatform.h>\ntypedef void *EGLImage;\ntypedef void *EGLImageKHR;\ntypedef void *EGLSync;\ntypedef void *EGLSyncKHR;\ntypedef void *EGLStreamKHR;\ntypedef intptr_t EGLAttrib;\ntypedef intptr_t EGLAttribKHR;\ntypedef uint64_t EGLTime;\ntypedef uint64_t EGLTimeKHR;\ntypedef uint64_t EGLGLuint64KHR;\ntypedef int EGLNativeFileDescriptorKHR;\n/' /tmp/sdl_src/include/SDL_egl.h
fi

# Application configuration: Keep OpenSL ES active, disable AAudio (unsupported on NDK r10e / API 19)
cat << 'EOF' > /tmp/sdl_src/Application.mk
APP_ABI := armeabi-v7a
APP_PLATFORM := android-19
APP_STL := stlport_static
APP_CFLAGS := -w -Wno-error -DSDL_HIDAPI_DISABLED=1 -DSDL_AUDIO_DRIVER_OPENSLES=1 -DSDL_AUDIO_DRIVER_AAUDIO=0
APP_LDFLAGS := -lOpenSLES
EOF

# Build SDL2
NDK_MODULE_PATH="$NDK_HOME/sources" "$NDK_HOME/ndk-build" \
    NDK_PROJECT_PATH=/tmp/sdl_src \
    APP_BUILD_SCRIPT=/tmp/sdl_src/Android.mk \
    NDK_APPLICATION_MK=/tmp/sdl_src/Application.mk \
    NDK_TOOLCHAIN_VERSION=4.9 \
    -j$(nproc --all) || exit 1

echo "=== Build Workflow Script Finished Successfully ==="
