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
    libusb          # wineusb
    krb5            # Kerberos + GSSAPI
    fontconfig
    sane-backends   # scanners
    libgphoto2      # cameras
    unixodbc        # odbc32
    vulkan-loader   # libvulkan.1.dylib; picks MoltenVK or KosmicKrisp via ICD manifests
)

media_deps=(
    glib    # GStreamer
    dav1d   # FFmpeg AV1 decoding
)

brew update --quiet || true

# The runner image hand-symlinks openssl@1.1 into /usr/local (not via
# `brew link`, so `brew unlink` removes nothing). Those links make linking a
# freshly built openssl@3 (pulled in via meson/python) fail the whole install.
find /usr/local/bin /usr/local/include /usr/local/lib -maxdepth 1 -type l \
    -lname '*openssl@1.1*' -print -delete

brew install --quiet "${build_tools[@]}" "${wine_deps[@]}" "${media_deps[@]}"
brew list --versions
