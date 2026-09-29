#!/bin/bash
# Builds CrossOver's patched MoltenVK (1.2.10 + CodeWeavers changes: geometry
# shader emulation, VK_EXT_transform_feedback, features DXVK needs for
# D3D10/10level9, AMD driver workarounds). Homebrew's upstream MoltenVK has
# none of these, so DXVK can't run on it.
set -euo pipefail
: "${WINE_PREFIX:?}" "${CX_SRC:?}"

work="${RUNNER_TEMP:-/tmp}/moltenvk"
rm -rf "$work"
mkdir -p "$work"
# fetchDependencies and the build write into the tree; keep the extracted sources pristine.
cp -R "$CX_SRC/moltenvk" "$work/src"
cd "$work/src"

# The pinned SPIRV-Cross commit only exists in CodeWeavers' fork, which ships
# in External/. Without --spirv-cross-root, fetchDependencies would derive the
# URL from this tree's git remote (there is none). With it, it rm -rf's
# External/SPIRV-Cross before symlinking the root, so move the fork out first.
mv External/SPIRV-Cross "$work/SPIRV-Cross"
./fetchDependencies --macos --spirv-cross-root "$work/SPIRV-Cross"

make macos

mkdir -p "$WINE_PREFIX/lib"
cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib "$WINE_PREFIX/lib/"
otool -D "$WINE_PREFIX/lib/libMoltenVK.dylib"
lipo -info "$WINE_PREFIX/lib/libMoltenVK.dylib"
