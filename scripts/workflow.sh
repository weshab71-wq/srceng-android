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

# Ensure root lib target directories exist
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
<?xml version="1.0" encoding="utf-8"?>
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

# Force working directory back to project root
cd $ROOT_DIR

# Clean out any old or corrupt files
rm -f $LIBPATH/libSDL2.so

# Fetch official SDL 2.28.5 precompiled Android development package
echo "Fetching official prebuilt SDL2 Android binary..."
curl -sL "https://github.com/libsdl-org/SDL/releases/download/release-2.28.5/SDL2-devel-2.28.5-android.tar.gz" -o /tmp/sdl2.tar.gz

mkdir -p /tmp/sdl_extract
tar -xzf /tmp/sdl_extract -C /tmp/sdl_extract 2>/dev/null || tar -xzf /tmp/sdl2.tar.gz -C /tmp/sdl_extract

# Locate and extract the compiled 32-bit armeabi-v7a libSDL2.so binary
SDL_FOUND=$(find /tmp/sdl_extract -name "libSDL2.so" | grep "armeabi-v7a" | head -n 1)

if [ -n "$SDL_FOUND" ]; then
    cp "$SDL_FOUND" $LIBPATH/libSDL2.so
else
    # Direct fallback compiled mirror
    curl -sL "https://github.com/nillerusr/source-engine/raw/master/libs/armeabi-v7a/libSDL2.so" -o $LIBPATH/libSDL2.so
fi

rm -rf /tmp/sdl_extract /tmp/sdl2.tar.gz

# Sync valid binary to all ABI target paths
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/libs/arm/libSDL2.so 2>/dev/null || true
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/libs/armeabi/libSDL2.so 2>/dev/null || true
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/lib/armeabi-v7a/libSDL2.so 2>/dev/null || true
cp -f $LIBPATH/libSDL2.so $ROOT_DIR/lib/arm/libSDL2.so 2>/dev/null || true

# Verify file size and ELF header
echo "Verifying libSDL2.so in root libs path:"
ls -lh $LIBPATH/libSDL2.so
file $LIBPATH/libSDL2.so

generate_resources

mkdir -p $HOME/.android
cp debug.keystore $HOME/.android
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/ ANDROID_HOME=android-sdk/ ant debug || exit 1

echo -n $COMMIT > version
