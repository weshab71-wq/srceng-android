#!/bin/bash
set -e

# Automatically detect ANDROID_HOME: checks GitHub Actions workspace path first, 
# then falls back to local user paths.
if [ -d "./android-sdk" ]; then
    export ANDROID_HOME="$(pwd)/android-sdk"
elif [ -d "$HOME/android-sdk" ]; then
    export ANDROID_HOME="$HOME/android-sdk"
elif [ -d "/home/jusic/android-sdk" ]; then
    export ANDROID_HOME="/home/jusic/android-sdk"
fi

echo "Using ANDROID_HOME at: $ANDROID_HOME"

# Apply Portal 2 patches (Package ID, App Name, and Launch Mode)
find . -type f -name 'build.gradle' -exec sed -i 's/com.valvesoftware.source/com.valvesoftware.portal2/g' {} +
find . -type f -name 'strings.xml' -exec sed -i 's/Source Engine/Portal 2/g' {} +
find . -type f -name 'AndroidManifest.xml' -exec sed -i "s/launchMode='standard'/launchMode='singleTask'/g" {} +

ant debug
