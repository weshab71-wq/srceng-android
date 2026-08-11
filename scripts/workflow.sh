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
        -mthumb|-marm|-Wl,--fix-cortex-a8|-Wl,--no-undefined) ;;
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
        -mthumb|-marm|-Wl,--fix-cortex-a8|-Wl,--no-undefined) ;;
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

# 4. Build Dependencies (libjpeg)
echo "Building libjpeg..."
rm -rf /tmp/libjpeg_src
mkdir -p /tmp/libjpeg_src
git clone --depth 1 -b 2.0.6 https://github.com/libjpeg-turbo/libjpeg-turbo.git /tmp/libjpeg_src
cd /tmp/libjpeg_src

# Create a valid minimal jconfig.h configuration header
cat << 'EOF' > jconfig.h
#define HAVE_PROTOTYPES 1
#define HAVE_UNSIGNED_CHAR 1
#define HAVE_UNSIGNED_SHORT 1
#define HAVE_STDDEF_H 1
#define HAVE_STDLIB_H 1
EOF

cat << 'EOF' > Android.mk
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := jpeg
LOCAL_SRC_FILES := jcapimin.c jcapistd.c jccoefct.c jccolor.c jcdctmgr.c jchuff.c \
                   jcinit.c jcmaster.c jcmarker.c jcphuff.c jcparam.c \
                   jcsample.c jctrans.c jdapimin.c jdapistd.c jdatadst.c \
                   jdatasrc.c jdcoefct.c jdcolor.c jddctmgr.c jdhuff.c jdinput.c \
                   jdmainct.c jdmarker.c jdmaster.c jdmerge.c jdphuff.c jdsample.c \
                   jdtrans.c jerror.c jfdctflt.c jfdctfst.c jfdctint.c idctflt.c \
                   idctfst.c idctint.c jidctred.c jquant1.c jquant2.c jutils.c \
                   jmemmgr.c jmemnobs.c
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

# 5. Robust SDL2 Source Compilation
echo "Building SDL2 natively using NDK..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Disable external cpufeatures module call
sed -i 's/$(call import-module,android\/cpufeatures)/# disabled cpufeatures import/g' /tmp/sdl_src/Android.mk

# Strip warning flags to prevent GCC 4.9 errors
sed -i '/-W/d' /tmp/sdl_src/Android.mk

cat << 'EOF' > /tmp/sdl_src/Application.mk
APP_ABI := armeabi-v7a
APP_PLATFORM := android-19
APP_STL := stlport_static
APP_CFLAGS := -w -Wno-error -DSDL_AUDIO_DRIVER_OPENSLES=0 -DSDL_AUDIO_DRIVER_AAUDIO=0 -DSL_ANDROID_PCM_REPRESENTATION_FLOAT=1
EOF

# Run ndk-build
NDK_MODULE_PATH="$NDK_HOME/sources" "$NDK_HOME/ndk-build" \
    NDK_PROJECT_PATH=/tmp/sdl_src \
    APP_BUILD_SCRIPT=/tmp/sdl_src/Android.mk \
    NDK_APPLICATION_MK=/tmp/sdl_src/Application.mk \
    NDK_TOOLCHAIN_VERSION=4.9 \
    -j$(nproc --all) || exit 1

echo "=== Build Workflow Script Finished Successfully ==="
