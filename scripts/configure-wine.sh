#!/bin/bash
# Configures CrossOver's Wine as a wow64 (i386 + x86_64 PE) build for macOS.
#
# Every dependency that works on macOS is passed as --with-*, which makes
# configure fail outright instead of printing a notice when it's missing.
# Everything that can't work on macOS (or is deliberately skipped) is --without-*.
set -euo pipefail
: "${WINE_PREFIX:?}" "${CX_SRC:?}" "${LLVM_MINGW:?}"

brew_prefix="$(brew --prefix)"
build="${RUNNER_TEMP:-/tmp}/wine-build"
mkdir -p "$build"
cd "$build"

export PATH="$LLVM_MINGW/bin:$brew_prefix/opt/bison/bin:$brew_prefix/opt/flex/bin:$PATH"
export PKG_CONFIG_PATH="$WINE_PREFIX/lib/pkgconfig:$brew_prefix/opt/krb5/lib/pkgconfig:$brew_prefix/lib/pkgconfig"
export KRB5_CONFIG="$brew_prefix/opt/krb5/bin/krb5-config"

# configure only probes for i386_CC/x86_64_CC when they're unset, so this
# routes the PE side through ccache as well as the host compiler.
if command -v ccache >/dev/null; then
    export CC="ccache clang"
    export i386_CC="ccache i686-w64-mingw32-clang"
    export x86_64_CC="ccache x86_64-w64-mingw32-clang"
fi
# No CPPFLAGS/LDFLAGS: /usr/local is already on clang's and ld64's default
# search paths on Intel, and an explicit -I would shadow pkg-config's.

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
    --with-vulkan       # MoltenVK
    --with-usb
    --with-krb5
    --with-gssapi
    --with-fontconfig
    --with-sane
    --with-gphoto
    --with-ffmpeg
    --with-gstreamer
    --with-dbus
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
)

"$CX_SRC/wine/configure" \
    --prefix="$WINE_PREFIX" \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    "${required[@]}" \
    "${not_on_macos[@]}" \
    2>&1 | tee configure.out
