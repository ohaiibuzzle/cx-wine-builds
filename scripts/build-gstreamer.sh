#!/bin/bash
# Builds GStreamer core + base + a curated set of good plugins from the
# CrossOver-bundled 1.24 tree. Homebrew's gstreamer has no x86_64 bottle and
# its source build pulls in gtk3/gtk4/rust/python/libX11.
# gst-libav is skipped: 1.24 predates the FFmpeg 9 API.
set -euo pipefail
: "${WINE_PREFIX:?}" "${CX_SRC:?}"

src="$CX_SRC/gstreamer/subprojects"
build="${RUNNER_TEMP:-/tmp}/gst-build"
brew_prefix="$(brew --prefix)"

export PATH="$brew_prefix/opt/bison/bin:$brew_prefix/opt/flex/bin:$PATH"
export PKG_CONFIG_PATH="$WINE_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

common=(
    --prefix="$WINE_PREFIX"
    --libdir=lib
    --buildtype=release
    --wrap-mode=nofallback
    -Dexamples=disabled
    -Dtests=disabled
    -Ddoc=disabled
    -Dnls=disabled
)
# gst-plugins-good has no introspection option, so that one is per-project.

meson setup "$build/gstreamer" "$src/gstreamer" "${common[@]}" \
    -Dintrospection=disabled \
    -Dptp-helper=disabled \
    -Dlibunwind=disabled \
    -Dlibdw=disabled \
    -Dbash-completion=disabled
meson install -C "$build/gstreamer"

meson setup "$build/base" "$src/gst-plugins-base" "${common[@]}" \
    -Dintrospection=disabled \
    -Dauto_features=disabled \
    -Dadder=enabled \
    -Dapp=enabled \
    -Daudioconvert=enabled \
    -Daudiomixer=enabled \
    -Daudiorate=enabled \
    -Daudioresample=enabled \
    -Dcompositor=enabled \
    -Dgio=enabled \
    -Dgio-typefinder=enabled \
    -Doverlaycomposition=enabled \
    -Dpbtypes=enabled \
    -Dplayback=enabled \
    -Drawparse=enabled \
    -Dsubparse=enabled \
    -Dtypefind=enabled \
    -Dvideoconvertscale=enabled \
    -Dvideorate=enabled \
    -Dvolume=enabled
meson install -C "$build/base"

meson setup "$build/good" "$src/gst-plugins-good" "${common[@]}" \
    -Dauto_features=disabled \
    -Dapetag=enabled \
    -Daudioparsers=enabled \
    -Dautodetect=enabled \
    -Davi=enabled \
    -Ddeinterlace=enabled \
    -Did3demux=enabled \
    -Dicydemux=enabled \
    -Disomp4=enabled \
    -Dmatroska=enabled \
    -Dosxaudio=enabled \
    -Dvideofilter=enabled \
    -Dwavparse=enabled
meson install -C "$build/good"
