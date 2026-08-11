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

# Create all necessary native library target paths
mkdir -p $LIBPATH
mkdir -p $(pwd)/libs/arm
mkdir -p $(pwd)/libs/armeabi
mkdir -p $(pwd)/lib/armeabi-v7a
mkdir -p $(pwd)/lib/arm

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
cd ../

# Clean out invalid libSDL2 binaries
rm -f $LIBPATH/libSDL2.so

# Clone official SDL repository and cross-compile clean ARM shared binary
echo "Compiling native ARM libSDL2.so from source..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Explicit cross-compile with Android NDK GCC compiler target
$NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-gcc \
    --sysroot=$NDK_HOME/platforms/android-19/arch-arm \
    -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 \
    -fPIC -shared -O2 \
    -I/tmp/sdl_src/include \
    $(find /tmp/sdl_src/src -name "*.c" ! -path "*/dummy/*" ! -path "*/win32/*" ! -path "*/cocoa/*" ! -path "*/wayland/*" ! -path "*/x11/*" ! -path "*/directfb/*" ! -path "*/kmsdrm/*" ! -path "*/psp/*" ! -path "*/vita/*" ! -path "*/n3ds/*") \
    -o $LIBPATH/libSDL2.so -lm -ldl -llog -landroid
rm -rf /tmp/sdl_src

# Verify ELF magic header (Must output ELF 32-bit LSB shared object, ARM)
file $LIBPATH/libSDL2.so

# Synchronize valid binary to all ABI locations
cp -f $LIBPATH/libSDL2.so libs/arm/libSDL2.so
cp -f $LIBPATH/libSDL2.so libs/armeabi/libSDL2.so
cp -f $LIBPATH/libSDL2.so lib/armeabi-v7a/libSDL2.so
cp -f $LIBPATH/libSDL2.so lib/arm/libSDL2.so

generate_resources

mkdir -p $HOME/.android
cp debug.keystore $HOME/.android
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/ ANDROID_HOME=android-sdk/ ant debug || exit 1

echo -n $COMMIT > version
