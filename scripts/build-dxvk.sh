#!/bin/bash
# Builds DXVK $DXVK_VERSION with patches/dxvk applied, for running on
# KosmicKrisp: the series backports two LLVM 22/23 build fixes and makes
# KHR_pipeline_library and fillModeNonSolid optional (the latter falls back
# to solid fill). Geometry shaders still have to come from the driver.
#
# The output is PE DLLs, so this runs on any host; the workflow uses the
# arm64 runner. llvm-mingw's *-w64-mingw32-* tools must be on PATH (DXVK's
# cross files call them by their -gcc/-g++ names, which llvm-mingw provides).
#
# Output: $OUT/x64/*.dll and $OUT/x32/*.dll
set -euo pipefail
: "${DXVK_VERSION:?}" "${DXVK_COMMIT:?}" "${GLSLANG_VERSION:?}" "${GLSLANG_SHA256:?}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="${RUNNER_TEMP:-/tmp}/dxvk"
out="${OUT:-$work/out}"

rm -rf "$work"
mkdir -p "$work" "$out"
cd "$work"

# Khronos' release build is static and universal; Homebrew's glslang needs
# spirv-tools at runtime.
glslang="glslang-$GLSLANG_VERSION-macos-universal-release.tar.gz"
curl -fL --retry 3 -o "$glslang" \
    "https://github.com/KhronosGroup/glslang/releases/download/$GLSLANG_VERSION/$glslang"
echo "$GLSLANG_SHA256  $glslang" | shasum -a 256 -c -
mkdir glslang
tar -xzf "$glslang" -C glslang

python3 -m venv venv
venv/bin/pip install --quiet meson
export PATH="$work/venv/bin:$work/glslang/bin:$PATH"
glslangValidator --version | head -1
command -v x86_64-w64-mingw32-g++ >/dev/null ||
    { echo "llvm-mingw's *-w64-mingw32-* tools are not on PATH" >&2; exit 1; }

git clone -q --depth 1 --branch "v$DXVK_VERSION" --recurse-submodules --shallow-submodules \
    https://github.com/doitsujin/dxvk.git src
[ "$(git -C src rev-parse HEAD)" = "$DXVK_COMMIT" ] ||
    { echo "v$DXVK_VERSION is $(git -C src rev-parse HEAD), expected $DXVK_COMMIT" >&2; exit 1; }

for p in "$repo"/patches/dxvk/*.patch; do
    echo "::group::$(basename "$p")"
    git -C src apply -v "$p"
    echo "::endgroup::"
done

for bits in 64 32; do
    meson setup "build$bits" src \
        --cross-file "src/build-win$bits.txt" \
        --buildtype release \
        --prefix "$out" \
        --bindir "x$bits" \
        --libdir "x$bits" \
        -Dbuild_id=false
    ninja -C "build$bits" install
done

# Import libraries aren't needed to run anything.
rm -f "$out"/x*/*.dll.a
ls -l "$out"/x64 "$out"/x32
