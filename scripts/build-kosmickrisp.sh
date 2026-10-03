#!/bin/bash
# Builds Mesa's KosmicKrisp (Vulkan on Metal 4) as an x86_64 ICD for the
# Rosetta-hosted Wine build. Runs on an arm64 runner, not the Intel one:
# Mesa's CLC tools need LLVM, libclc and SPIRV-LLVM-Translator, and Homebrew
# has no x86_64 bottles for any of them (building LLVM on Intel would eat
# most of the job's time limit).
#
# So it's two builds of the same tree:
#   1. native arm64, only to produce the build-time shader compilers
#      (mesa_clc, vtn_bindgen2, kk_clc);
#   2. a cross build for x86_64 that uses those (-D*=system), which drops the
#      LLVM/SPIR-V dependencies from the x86_64 side entirely.
#
# The driver only runs on Apple silicon with macOS 26+ (Metal 4); under
# Rosetta it still talks to the Apple GPU.
#
# Source: a release tarball (MESA_VERSION + MESA_SHA256), or, when
# MESA_GIT_SHA is set, that exact commit from mesa/mesa. Unmerged MR heads
# are fetchable there too (GitLab mirrors them as refs/merge-requests/*).
# A shallow fetch by hash rather than a GitLab archive: the archives are
# generated on the fly and not guaranteed byte-stable, while git verifies
# the commit's content itself.
#
# Output: $OUT/lib/libvulkan_kosmickrisp.dylib
set -euo pipefail

work="${RUNNER_TEMP:-/tmp}/kosmickrisp"
out="${OUT:-$work/out}"
host_tools="$work/host-tools"
brew_prefix="$(brew --prefix)"

rm -rf "$work"
mkdir -p "$work" "$out/lib"
cd "$work"

if [ -n "${MESA_GIT_SHA:-}" ]; then
    src="$work/mesa-$MESA_GIT_SHA"
    git init -q "$src"
    git -C "$src" fetch -q --depth 1 https://gitlab.freedesktop.org/mesa/mesa.git "$MESA_GIT_SHA"
    git -C "$src" checkout -q FETCH_HEAD
    [ "$(git -C "$src" rev-parse HEAD)" = "$MESA_GIT_SHA" ] ||
        { echo "fetched $(git -C "$src" rev-parse HEAD), wanted $MESA_GIT_SHA" >&2; exit 1; }
    git -C "$src" log -1 --format='Mesa %H (%cs): %s'
else
    : "${MESA_VERSION:?}" "${MESA_SHA256:?}"
    curl -fL --retry 3 -o "mesa-$MESA_VERSION.tar.xz" \
        "https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz"
    echo "$MESA_SHA256  mesa-$MESA_VERSION.tar.xz" | shasum -a 256 -c -
    tar -xJf "mesa-$MESA_VERSION.tar.xz"
    src="$work/mesa-$MESA_VERSION"
fi
cat "$src/VERSION"

python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet mako packaging pyyaml 'meson>=1.9.1'
export PATH="$work/venv/bin:$brew_prefix/opt/llvm/bin:$brew_prefix/opt/bison/bin:$brew_prefix/opt/flex/bin:$PATH"
llvm-config --version

common=(
    --buildtype=release
    -Dplatforms=macos
    -Dgallium-drivers=
    -Dopengl=false
    -Dzstd=disabled
    -Dvulkan-icd-dir=share/vulkan/icd.d
)

# 1. Native tools. kk_clc lives under src/kosmickrisp, so the driver has to be
#    enabled here too; it's thrown away.
meson setup "$work/build-native" "$src" "${common[@]}" \
    --prefix="$host_tools" \
    --prefer-static \
    -Dvulkan-drivers=kosmickrisp \
    -Dmesa-clc=enabled \
    -Dinstall-mesa-clc=true \
    -Dinstall-precomp-compiler=true
meson install -C "$work/build-native"
ls "$host_tools/bin"

# 2. x86_64 driver. needs_exe_wrapper keeps meson from running x86_64 build
#    products through Rosetta; everything it needs to run comes from step 1.
sdk="$(xcrun --sdk macosx --show-sdk-path)"
cat > "$work/x86_64-darwin.ini" <<EOF
[binaries]
c = ['clang', '-arch', 'x86_64']
cpp = ['clang++', '-arch', 'x86_64']
objc = ['clang', '-arch', 'x86_64']
objcpp = ['clang++', '-arch', 'x86_64']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true
sys_root = '$sdk'
# Don't let the x86_64 side pick up arm64 Homebrew .pc files.
pkg_config_libdir = []

[built-in options]
c_args = ['-mmacosx-version-min=26.0']
cpp_args = ['-mmacosx-version-min=26.0']
objc_args = ['-mmacosx-version-min=26.0']
c_link_args = ['-mmacosx-version-min=26.0']
cpp_link_args = ['-mmacosx-version-min=26.0']

[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

PATH="$host_tools/bin:$PATH" meson setup "$work/build-x86_64" "$src" "${common[@]}" \
    --cross-file "$work/x86_64-darwin.ini" \
    --prefix="$work/install-x86_64" \
    --prefer-static \
    --wrap-mode=default \
    -Dvulkan-drivers=kosmickrisp \
    -Dmesa-clc=system \
    -Dprecomp-compiler=system \
    -Dllvm=disabled \
    -Dspirv-tools=disabled
PATH="$host_tools/bin:$PATH" meson install -C "$work/build-x86_64" --tags runtime

dylib="$work/install-x86_64/lib/libvulkan_kosmickrisp.dylib"
cp "$dylib" "$out/lib/"
lipo -info "$out/lib/libvulkan_kosmickrisp.dylib"
otool -L "$out/lib/libvulkan_kosmickrisp.dylib"
# Anything outside the system would need bundling; there shouldn't be any.
if otool -L "$out/lib/libvulkan_kosmickrisp.dylib" | tail -n +2 |
    grep -v -e '/usr/lib/' -e '/System/' -e 'libvulkan_kosmickrisp'; then
    echo "libvulkan_kosmickrisp.dylib links non-system libraries" >&2
    exit 1
fi
