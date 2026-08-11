# 5. Robust SDL2 Source Compilation (GCC 4.9 & API 19 Safe)
echo "Building SDL2 natively using NDK..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Disable OpenSLES directly in Android.mk by removing its source file reference
sed -i 's/$(wildcard $(LOCAL_PATH)\/src\/audio\/opensles\/*.c)/# opensles disabled/g' /tmp/sdl_src/Android.mk
sed -i 's/$(call import-module,android\/cpufeatures)/# disabled cpufeatures import/g' /tmp/sdl_src/Android.mk

# Strip all warning assignments directly from Android.mk to keep GCC 4.9 happy
sed -i '/-W/d' /tmp/sdl_src/Android.mk

cat << 'EOF' > /tmp/sdl_src/Application.mk
APP_ABI := armeabi-v7a
APP_PLATFORM := android-19
APP_STL := stlport_static
APP_CFLAGS := -w -Wno-error
EOF

# Run ndk-build passing driver disable overrides
NDK_MODULE_PATH="$NDK_HOME/sources" "$NDK_HOME/ndk-build" \
    NDK_PROJECT_PATH=/tmp/sdl_src \
    APP_BUILD_SCRIPT=/tmp/sdl_src/Android.mk \
    NDK_APPLICATION_MK=/tmp/sdl_src/Application.mk \
    NDK_TOOLCHAIN_VERSION=4.9 \
    SDL_AUDIO_DRIVER_OPENSLES=0 \
    -j$(nproc --all) || exit 1
