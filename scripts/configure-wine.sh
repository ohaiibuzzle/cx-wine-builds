#!/bin/bash
# Configures CrossOver's Wine as a wow64 (i386 + x86_64 PE) build for macOS.
#
# Every dependency that works on macOS is passed as --with-*, which makes
# configure fail outright instead of printing a notice when it's missing.
# Everything that can't work on macOS (or is deliberately skipped) is --without-*.
set -euo pipefail
: "${WINE_PREFIX:?}" "${CX_SRC:?}"

brew_prefix="$(brew --prefix)"
build="${RUNNER_TEMP:-/tmp}/wine-build"
mkdir -p "$build"
cd "$build"

# The llvm-mingw *-w64-mingw32-* tools must already be on PATH (the workflow
# links just those). Never put llvm-mingw's bin/ itself on PATH: its bare
# `clang` would replace Apple's as the host compiler.
command -v x86_64-w64-mingw32-clang >/dev/null ||
    { echo "llvm-mingw's *-w64-mingw32-* tools are not on PATH" >&2; exit 1; }
export PATH="$brew_prefix/opt/bison/bin:$brew_prefix/opt/flex/bin:$PATH"
export PKG_CONFIG_PATH="$WINE_PREFIX/lib/pkgconfig:$brew_prefix/opt/krb5/lib/pkgconfig:$brew_prefix/lib/pkgconfig"
export KRB5_CONFIG="$brew_prefix/opt/krb5/bin/krb5-config"

# configure only probes for i386_CC/x86_64_CC when they're unset, so this
# routes the PE side through ccache as well as the host compiler.
if command -v ccache >/dev/null; then
    export CC="ccache clang"
    export i386_CC="ccache i686-w64-mingw32-clang"
    export x86_64_CC="ccache x86_64-w64-mingw32-clang"
fi
# No CPPFLAGS: /usr/local is already on clang's default search path on Intel,
# and an explicit -I would shadow pkg-config's. LDFLAGS only adds our prefix,
# for configure's libMoltenVK fallback; with Homebrew's vulkan-loader installed
# the libvulkan check wins and that fallback never runs.
export LDFLAGS="-L$WINE_PREFIX/lib"

required=(
    --with-mingw        # llvm-mingw for the i386/x86_64 PE side
    --with-freetype
    --with-gnutls
    --with-gettext
    --with-coreaudio
    --with-cups         # system libcups from the SDK
    --with-opencl       # OpenCL.framework
    --with-pcap         # system libpcap
    --with-pcsclite     # PCSC.framework
    --with-unwind       # libunwind in libSystem
    --with-sdl
    --with-vulkan       # Khronos loader -> MoltenVK or KosmicKrisp (see install-vulkan-icds.sh)
    --with-usb
    --with-krb5
    --with-gssapi
    --with-fontconfig
    --with-sane
    --with-gphoto
    --with-ffmpeg
    --with-gstreamer
)
# Not passed as --with-opengl: that would also make the missing EGL fatal.
# EGL is only used by the X11/Wayland drivers; winemac uses OpenGL.framework.
# odbc has no --with switch; it's picked up from unixodbc automatically.

not_on_macos=(
    --without-x         # requested: no X11
    --without-wayland   # needs linux/input.h
    --without-alsa
    --without-oss
    --without-udev
    --without-v4l2
    --without-capi
    --without-inotify   # no libinotify-kqueue in Homebrew
    --without-hwloc     # only used on FreeBSD
    --without-netapi    # Samba: no x86_64 bottle, huge source build
    --without-pulse     # winepulse uses robust mutexes, which macOS lacks
    --without-dbus      # only talks to UDisks/NetworkManager/BlueZ; macOS uses DiskArbitration
)

"$CX_SRC/wine/configure" \
    --prefix="$WINE_PREFIX" \
    --enable-archs=i386,x86_64 \
    --disable-win16 \
    --disable-tests \
    "${required[@]}" \
    "${not_on_macos[@]}" \
    2>&1 | tee configure.out

# Without the loader, configure silently falls back to linking libMoltenVK
# directly and the KosmicKrisp ICD would never be reachable.
grep -q '^#define SONAME_LIBVULKAN "libvulkan\.1\.dylib"' include/config.h ||
    { grep SONAME_LIBVULKAN include/config.h >&2; echo "Wine isn't using the Vulkan loader" >&2; exit 1; }
