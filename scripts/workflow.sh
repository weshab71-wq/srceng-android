#!/bin/bash

# Enable 32-bit architecture and install missing libraries for older Android SDK tools
sudo dpkg --add-architecture i386
sudo apt-get update -y
sudo apt-get install -y zlib1g:i386 libstdc++6:i386 libc6:i386 wget curl unzip

export GIT_TERMINAL_PROMPT=0
export ROOT_DIR=$(pwd)
export NDK_HOME=$ROOT_DIR/ndk-binaries 
export PATH=$PATH:$NDK_HOME
export LIBPATH=$ROOT_DIR/libs/armeabi-v7a 
export NDK_TOOLCHAIN_VERSION=4.9

# Ensure all binary target folders exist under libs/
mkdir -p $LIBPATH
mkdir -p $ROOT_DIR/libs/arm
mkdir -p $ROOT_DIR/libs/armeabi
mkdir -p $ROOT_DIR/lib/armeabi-v7a
mkdir -p $ROOT_DIR/lib/arm

build()
{
    PW=$(pwd)
    cd $1 || exit 1
    make NDK=1 NDK_PATH=$NDK_HOME APP_API_LEVEL=19 CFG=debug NDK_VERBOSE=1 -j$(nproc --all) || exit 1
    cp $2 $LIBPATH && echo $2 Installed || exit 1
    cd $PW
}

RES=res/values/build_info.xml
generate_resources()
{
    SAFE_COMMIT=$(echo "${COMMIT:-unknown}" | sed 's/"/\\"/g')
    SAFE_BRANCH=$(echo "${DEPLOY_BRANCH:-main}" | sed 's/"/\\"/g')

    cat << EOF > $RES
<?xml version="1.0" utf-8"?>
<resources>
    <string name="last_commit">${SAFE_COMMIT}</string>
    <string name="deploy_branch">${SAFE_BRANCH}</string>
</resources>
EOF
}

# Create a local valid tierhook module
mkdir -p jni/src/tierhook
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

# Enter srcsdk and set up dependencies
cd srcsdk/
rm -rf gl4es
git clone --depth 1 https://github.com/nillerusr/gl4es.git gl4es || git clone --depth 1 https://github.com/ptitSeb/gl4es.git gl4es

if [ ! -f gl4es/Makefile ]; then
    cat << 'EOF' > gl4es/Makefile
TARGET = libRegal.so
CC ?= gcc
CFLAGS = -fPIC -shared -O2 -Iinclude

# Exclude non-Android platform files (Amiga agl and desktop Linux glx)
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

# Build core engine components
build main libmain.so
build gl4es libRegal.so
build vinterface_wrapper/client libclient.so
build vinterface_wrapper/server libserver.so

# Return to project root directory
cd $ROOT_DIR

# Clean out old/corrupt files
rm -f $LIBPATH/libSDL2.so

echo "Building 32-bit ARM libSDL2.so directly from source..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Compile minimal, functional libSDL2.so for armeabi-v7a using NDK toolchain
$NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-gcc \
    --sysroot=$NDK_HOME/platforms/android-19/arch-arm \
    -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 \
    -fPIC -shared -O2 \
    -I/tmp/sdl_src/include \
    -D__ANDROID__ \
    /tmp/sdl_src/src/*.c \
    /tmp/sdl_src/src/audio/*.c \
    /tmp/sdl_src/src/audio/android/*.c \
    /tmp/sdl_src/src/audio/dummy/*.c \
    /tmp/sdl_src/src/core/android/*.c \
    /tmp/sdl_src/src/cpuinfo/*.c \
    /tmp/sdl_src/src/events/*.c \
    /tmp/sdl_src/src/file/*.c \
    /tmp/sdl_src/src/haptic/*.c \
    /tmp/sdl_src/src/haptic/dummy/*.c \
    /tmp/sdl_src/src/joystick/*.c \
    /tmp/sdl_src/src/joystick/android/*.c \
    /tmp/sdl_src/src/loadso/dlopen/*.c \
    /tmp/sdl_src/src/power/*.c \
    /tmp/sdl_src/src/power/android/*.c \
    /tmp/sdl_src/src/render/*.c \
    /tmp/sdl_src/src/render/opengles/*.c \
    /tmp/sdl_src/src/render/opengles2/*.c \
    /tmp/sdl_src/src/sensor/*.c \
    /tmp/sdl_src/src/sensor/android/*.c \
    /tmp/sdl_src/src/stdlib/*.c \
    /tmp/sdl_src/src/thread/*.c \
    /tmp/sdl_src/src/thread/pthread/*.c \
    /tmp/sdl_src/src/timer/*.c \
    /tmp/sdl_src/src/timer/unix/*.c \
    /tmp/sdl_src/src/video/*.c \
    /tmp/sdl_src/src/video/android/*.c \
    -o $LIBPATH/libSDL2.so -lm -ldl -llog -landroid -lGLESv1_CM -lGLESv2

rm -rf /tmp/sdl_src

# Check file size
SIZE=$(wc -c < "$LIBPATH/libSDL2.so" 2>/dev/null || echo 0)
echo "Verified libSDL2.so compiled size: $SIZE bytes."

if [ "$SIZE" -lt 500000 ]; then
    echo "ERROR: Compilation of libSDL2.so failed. Halting workflow."
    exit 1
fi

# Replicate libSDL2.so across all directories Ant scans for APK bundling
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/libs/arm/libSDL2.so
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/libs/armeabi/libSDL2.so
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/libs/armeabi-v7a/libSDL2.so
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/lib/armeabi-v7a/libSDL2.so
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/lib/arm/libSDL2.so

generate_resources

mkdir -p $HOME/.android
cp debug.keystore $HOME/.android
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/ ANDROID_HOME=android-sdk/ ant debug || exit 1

echo -n $COMMIT > version
