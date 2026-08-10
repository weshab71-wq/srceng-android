#!/bin/bash

export NDK_HOME=$(pwd)/ndk-binaries PATH=$PATH:$(pwd)/ndk-binaries LIBPATH=$(pwd)/libs/armeabi-v7a NDK_TOOLCHAIN_VERSION=4.9
mkdir -p $LIBPATH

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

# Fetch tierhook directly before submodule update can fail
mkdir -p jni/src
if [ ! -d "jni/src/tierhook" ] || [ -z "$(ls -A jni/src/tierhook 2>/dev/null)" ]; then
    git clone --depth 1 https://github.com/nillerusr/source-tierhook.git jni/src/tierhook || git clone --depth 1 https://github.com/nillerusr/tierhook.git jni/src/tierhook || true
fi

git submodule update --init --recursive || true

build jni/src/tierhook libtierhook.so

cd srcsdk/
build main libmain.so
build gl4es libRegal.so
build vinterface_wrapper/client libclient.so
build vinterface_wrapper/server libserver.so
cd ../

generate_resources

mkdir -p $HOME/.android
cp debug.keystore $HOME/.android
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/ ANDROID_HOME=android-sdk/ ant debug || exit 1

echo -n $COMMIT > version
