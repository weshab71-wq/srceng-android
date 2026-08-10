#!/bin/bash

# Enable 32-bit architecture and install missing libraries for older Android SDK tools
sudo dpkg --add-architecture i386
sudo apt-get update -y
sudo apt-get install -y zlib1g:i386 libstdc++6:i386 libc6:i386 wget curl unzip

export GIT_TERMINAL_PROMPT=0
export NDK_HOME=$(pwd)/ndk-binaries 
export PATH=$PATH:$(pwd)/ndk-binaries
export LIBPATH=$(pwd)/libs/armeabi-v7a 
export NDK_TOOLCHAIN_VERSION=4.9

# Ensure all lib folder variants exist
mkdir -p $LIBPATH
mkdir -p $(pwd)/lib/armeabi-v7a
mkdir -p $(pwd)/libs/arm

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
    echo '<?xml version="1.0" encoding="utf-8"?>' > $RES
    echo '<resources>' >> $RES
    echo '<string name="last_commit" >'$COMMIT'</string>' >> $RES
    echo '<string name="deploy_branch" >'$DEPLOY_BRANCH'</string>' >> $RES
    echo '</resources>' >> $RES
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
cd ../

# Clean out any dummy/corrupted libSDL2.so files
rm -f $LIBPATH/libSDL2.so

echo "Fetching valid 32-bit libSDL2.so..."
curl -L -s -o $LIBPATH/libSDL2.so "https://media.githubusercontent.com/media/nillerusr/source-engine/master/libs/armeabi-v7a/libSDL2.so" || \
curl -L -s -o $LIBPATH/libSDL2.so "https://raw.githubusercontent.com/FWGS/sdl-android/master/libs/armeabi-v7a/libSDL2.so"

FILESIZE=$(wc -c < "$LIBPATH/libSDL2.so" 2>/dev/null || echo 0)

if [ "$FILESIZE" -lt 100000 ]; then
    echo "Direct download failed. Building SDL2 from source..."
    rm -f $LIBPATH/libSDL2.so
    git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src
    
    $NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-gcc \
        --sysroot=$NDK_HOME/platforms/android-19/arch-arm \
        -fPIC -shared -O2 \
        -I/tmp/sdl_src/include \
        /tmp/sdl_src/src/*.c /tmp/sdl_src/src/*/*.c /tmp/sdl_src/src/*/*/*.c /tmp/sdl_src/src/*/*/*/*.c \
        -o $LIBPATH/libSDL2.so -lm -ldl -llog -landroid
    rm -rf /tmp/sdl_src
fi

# Sync compiled binaries into lib/ and libs/ directories so Ant packages them regardless of structure
cp -r libs/* lib/ 2>/dev/null || true
cp -r libs/armeabi-v7a/* libs/arm/ 2>/dev/null || true
cp -r libs/armeabi-v7a/* lib/armeabi-v7a/ 2>/dev/null || true

echo "Checking lib directories:"
ls -lh lib/armeabi-v7a/
ls -lh libs/armeabi-v7a/

generate_resources

mkdir -p $HOME/.android
cp debug.keystore $HOME/.android
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/ ANDROID_HOME=android-sdk/ ant debug || exit 1

echo -n $COMMIT > version
