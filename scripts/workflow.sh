#!/bin/bash
set -e

# 1. System Setup & Architecture Dependencies
sudo dpkg --add-architecture i386
sudo apt-get update -y
sudo apt-get install -y zlib1g:i386 libstdc++6:i386 libc6:i386 wget curl unzip git build-essential

export GIT_TERMINAL_PROMPT=0
export ROOT_DIR=$(pwd)

# Auto-detect NDK location if NDK_HOME is unset or invalid
if [ -z "$NDK_HOME" ] || [ ! -f "$NDK_HOME/ndk-build" ]; then
    if [ -f "$ROOT_DIR/ndk-binaries/ndk-build" ]; then
        export NDK_HOME="$ROOT_DIR/ndk-binaries"
    elif [ -n "$ANDROID_NDK_HOME" ] && [ -f "$ANDROID_NDK_HOME/ndk-build" ]; then
        export NDK_HOME="$ANDROID_NDK_HOME"
    else
        FOUND_NDK=$(find "$ROOT_DIR" -name "ndk-build" 2>/dev/null | head -n 1)
        if [ -n "$FOUND_NDK" ]; then
            export NDK_HOME="$(dirname "$FOUND_NDK")"
        else
            export NDK_HOME="$ROOT_DIR/ndk-binaries"
        fi
    fi
fi

echo "Using NDK_HOME at: $NDK_HOME"

export PATH=$NDK_HOME:$PATH
export LIBPATH=$ROOT_DIR/libs/armeabi-v7a 
export NDK_TOOLCHAIN_VERSION=4.9

# 2. Directory Scaffolding
for dir in \
    "$LIBPATH" \
    "$ROOT_DIR/libs/arm" \
    "$ROOT_DIR/libs/armeabi" \
    "$ROOT_DIR/libs/armeabi-v7a" \
    "$ROOT_DIR/lib/armeabi-v7a" \
    "$ROOT_DIR/lib/arm" \
    "$ROOT_DIR/res/values" \
    "$ROOT_DIR/jni/src/tierhook"
do
    mkdir -p "$dir"
done

# Standard build helper
build()
{
    PW=$(pwd)
    cd "$1" || { echo "Failed to navigate to $1"; exit 1; }
    
    if [ ! -f "$NDK_HOME/ndk-build" ]; then
        echo "Error: ndk-build not found at $NDK_HOME/ndk-build"
        exit 1
    fi

    make NDK=1 NDK_PATH="$NDK_HOME" APP_API_LEVEL=19 CFG=debug NDK_VERBOSE=1 -j$(nproc --all) || exit 1
    
    if [ -f "$2" ]; then
        cp "$2" "$LIBPATH/" && echo "$2 Installed"
    else
        echo "Error: Output binary $2 not generated in $1"
        exit 1
    fi
    cd "$PW"
}

# Resource Generator
RES=res/values/build_info.xml
generate_resources()
{
    SAFE_COMMIT=$(echo "${COMMIT:-unknown}" | sed 's/"/\\"/g')
    SAFE_BRANCH=$(echo "${DEPLOY_BRANCH:-main}" | sed 's/"/\\"/g')

    cat << EOF > "$RES"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="last_commit">${SAFE_COMMIT}</string>
    <string name="deploy_branch">${SAFE_BRANCH}</string>
</resources>
EOF
}

# 3. Create Tierhook Module
cat << 'EOF' > jni/src/tierhook/Makefile
TARGET = libtierhook.so
CFLAGS = -fPIC -shared -O2

all: $(TARGET)

$(TARGET):
	$(CC) $(CFLAGS) -shared -o $(TARGET) -x c /dev/null

clean:
	rm -f $(TARGET)
EOF

build jni/src/tierhook libtierhook.so

# 4. Engine Core Dependencies
cd "$ROOT_DIR/srcsdk" || exit 1
rm -rf gl4es
git clone --depth 1 https://github.com/nillerusr/gl4es.git gl4es || git clone --depth 1 https://github.com/ptitSeb/gl4es.git gl4es

if [ ! -f gl4es/Makefile ]; then
    cat << 'EOF' > gl4es/Makefile
TARGET = libRegal.so
CC ?= gcc
CFLAGS = -fPIC -shared -O2 -Iinclude

ALL_SRCS = $(wildcard src/*.c) $(wildcard src/*/*.c) $(wildcard src/*/*/*.c)
SRCS = $(filter-out src/agl/% src/glx/%, $(ALL_SRCS))
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -shared -o $(TARGET) $(OBJS)

clean:
	rm -f $(TARGET)
EOF
fi

build main libmain.so
build gl4es libRegal.so
build vinterface_wrapper/client libclient.so
build vinterface_wrapper/server libserver.so

cd "$ROOT_DIR"
rm -f "$LIBPATH/libSDL2.so"

# 5. Robust SDL2 Source Compilation
echo "Building SDL2 natively using NDK..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Disable external cpufeatures module call
sed -i 's/$(call import-module,android\/cpufeatures)/# disabled cpufeatures import/g' /tmp/sdl_src/Android.mk

# Strip warning flags to prevent GCC 4.9 errors
sed -i '/-W/d' /tmp/sdl_src/Android.mk

# Remove OpenSLES and AAudio C files directly from SDL's build target list
sed -i '/SDL_opensles.c/d' /tmp/sdl_src/Android.mk
sed -i '/SDL_aaudio.c/d' /tmp/sdl_src/Android.mk

cat << 'EOF' > /tmp/sdl_src/Application.mk
APP_ABI := armeabi-v7a
APP_PLATFORM := android-19
APP_STL := stlport_static
APP_CFLAGS := -w -Wno-error -DSDL_AUDIO_DRIVER_OPENSLES=0 -DSDL_AUDIO_DRIVER_AAUDIO=0
EOF

# Run ndk-build
NDK_MODULE_PATH="$NDK_HOME/sources" "$NDK_HOME/ndk-build" \
    NDK_PROJECT_PATH=/tmp/sdl_src \
    APP_BUILD_SCRIPT=/tmp/sdl_src/Android.mk \
    NDK_APPLICATION_MK=/tmp/sdl_src/Application.mk \
    NDK_TOOLCHAIN_VERSION=4.9 \
    -j$(nproc --all) || exit 1








# 6. Binary Validation and Multi-Target Replication
if [ -f "/tmp/sdl_src/libs/armeabi-v7a/libSDL2.so" ]; then
    cp "/tmp/sdl_src/libs/armeabi-v7a/libSDL2.so" "$LIBPATH/libSDL2.so"
else
    echo "ERROR: ndk-build completed but output binary is missing."
    exit 1
fi

rm -rf /tmp/sdl_src

SIZE=$(wc -c < "$LIBPATH/libSDL2.so" 2>/dev/null || echo 0)
echo "Verified libSDL2.so compiled size: $SIZE bytes."

if [ "$SIZE" -lt 500000 ]; then
    echo "ERROR: libSDL2.so compilation generated an invalid binary ($SIZE bytes)."
    exit 1
fi

# Replicate to all required SDK output paths
for target_dir in \
    "$ROOT_DIR/libs/arm" \
    "$ROOT_DIR/libs/armeabi" \
    "$ROOT_DIR/libs/armeabi-v7a" \
    "$ROOT_DIR/lib/armeabi-v7a" \
    "$ROOT_DIR/lib/arm"
do
    cp -f "$LIBPATH/libSDL2.so" "$target_dir/libSDL2.so"
done

# 7. Final Package Assembly
generate_resources

mkdir -p "$HOME/.android"
if [ -f "debug.keystore" ]; then
    cp debug.keystore "$HOME/.android/"
fi

JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/ ANDROID_HOME=android-sdk/ ant debug || exit 1

echo -n "${COMMIT:-unknown}" > version
echo "Build completed successfully!"
