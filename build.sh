#!/bin/bash

export ANDROID_HOME=/home/jusic/android-sdk

# Apply Portal 2 patches (Package ID, App Name, and Launch Mode)
find . -type f -name 'build.gradle' -exec sed -i 's/com.valvesoftware.source/com.valvesoftware.portal2/g' {} +
find . -type f -name 'strings.xml' -exec sed -i 's/Source Engine/Portal 2/g' {} +
find . -type f -name 'AndroidManifest.xml' -exec sed -i "s/launchMode='standard'/launchMode='singleTask'/g" {} +

ant debug
