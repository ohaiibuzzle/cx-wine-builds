#!/bin/bash
# Installs Wine's host-side dependencies from Homebrew.
# Intel macOS is Homebrew Tier 3: formulae without an x86_64 bottle
# (openssl@3, glib, gettext, pkgconf, sdl3, ...) get built from source.
set -euo pipefail

build_tools=(
    bison       # Wine needs >= 3.0, macOS ships 2.3
    flex
    pkgconf
    gettext     # msgfmt for translations
    meson
    ninja
    nasm        # FFmpeg asm
)

wine_deps=(
    freetype        # fonts (required)
    gnutls          # schannel / bcrypt
    sdl2-compat     # joysticks via winebus
    molten-vk       # Vulkan -> Metal
    libusb          # wineusb
    krb5            # Kerberos + GSSAPI
    fontconfig
    sane-backends   # scanners
    libgphoto2      # cameras
    unixodbc        # odbc32
    pulseaudio      # winepulse.drv (CoreAudio is still the default)
    dbus
)

media_deps=(
    glib    # GStreamer
    dav1d   # FFmpeg AV1 decoding
)

brew update --quiet || true
brew install --quiet "${build_tools[@]}" "${wine_deps[@]}" "${media_deps[@]}"
brew list --versions
