#!/bin/bash
# Builds a decode-focused FFmpeg for winedmo.
# Homebrew's ffmpeg has no x86_64 bottle and drags in x265/libvmaf/libvpx/sdl,
# so we build a lean one ourselves.
set -euo pipefail
: "${WINE_PREFIX:?}" "${FFMPEG_VERSION:?}" "${FFMPEG_SHA256:?}"

work="${RUNNER_TEMP:-/tmp}/ffmpeg"
mkdir -p "$work"
cd "$work"

tarball="ffmpeg-$FFMPEG_VERSION.tar.xz"
curl -fL --retry 3 -o "$tarball" "https://ffmpeg.org/releases/$tarball"
echo "$FFMPEG_SHA256  $tarball" | shasum -a 256 -c -
tar -xJf "$tarball"
cd "ffmpeg-$FFMPEG_VERSION"

./configure \
    --prefix="$WINE_PREFIX" \
    --enable-shared \
    --disable-static \
    --enable-pic \
    --disable-programs \
    --disable-doc \
    --disable-avdevice \
    --disable-xlib \
    --disable-libxcb \
    --disable-sdl2 \
    --enable-libdav1d \
    --enable-videotoolbox \
    --enable-audiotoolbox

make -j"$(sysctl -n hw.ncpu)"
make install
