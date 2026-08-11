# 5. Robust SDL2 Source Compilation
echo "Building SDL2 natively using NDK..."
rm -rf /tmp/sdl_src
git clone --depth 1 -b release-2.0.22 https://github.com/libsdl-org/SDL.git /tmp/sdl_src

# Disable external cpufeatures import
sed -i 's/$(call import-module,android\/cpufeatures)/# disabled cpufeatures import/g' /tmp/sdl_src/Android.mk

# Strip Clang-specific warning flags that break GCC 4.9 compilation
sed -i 's/-Wmissing-variable-declarations//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wshorten-64-to-32//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wunreachable-code-return//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wshift-sign-overflow//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wkeyword-macro//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wdocumentation-unknown-command//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wdocumentation//g' /tmp/sdl_src/Android.mk
sed -i 's/-Wunneeded-internal-declaration//g' /tmp/sdl_src/Android.mk

cat << 'EOF' > /tmp/sdl_src/Application.mk
APP_ABI := armeabi-v7a
APP_PLATFORM := android-19
APP_STL := stlport_static
EOF

# Run ndk-build with inline module path assignment
NDK_MODULE_PATH="$NDK_HOME/sources" $NDK_HOME/ndk-build \
    NDK_PROJECT_PATH=/tmp/sdl_src \
    APP_BUILD_SCRIPT=/tmp/sdl_src/Android.mk \
    NDK_APPLICATION_MK=/tmp/sdl_src/Application.mk \
    -j$(nproc --all) || exit 1
