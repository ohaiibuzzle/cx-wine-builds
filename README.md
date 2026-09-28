# wine-cx

GitHub Actions build of the Wine tree from the
[CrossOver 26.3.0 sources](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz)
for macOS, without X11.

- **Host:** x86_64 (`macos-15-intel`), runs under Rosetta on Apple silicon like CrossOver itself
- **PE side:** wow64, `--enable-archs=i386,x86_64`, built with
  [llvm-mingw 20260922](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260922)
- **Output:** `/opt/wine-cx` as a `.tar.xz` workflow artifact, plus `config.log` / `configure.out`

## Dependencies

| Feature | Source | Status |
|---|---|---|
| FreeType, GnuTLS, SDL2 (sdl2-compat), MoltenVK, libusb, krb5/GSSAPI, fontconfig, SANE, libgphoto2, unixODBC, PulseAudio, D-Bus, gettext | Homebrew | enabled |
| CoreAudio, OpenCL, PCSC, CUPS, libpcap, libunwind | macOS SDK | enabled |
| FFmpeg 9.0.2 (winedmo) | built from source | enabled |
| GStreamer 1.24 core/base/good | built from the CrossOver-bundled tree | enabled |
| X11 | – | disabled on purpose |
| EGL | – | not available; only used by the X11/Wayland drivers |
| Wayland, ALSA, OSS, udev, V4L2, CAPI | – | Linux only |
| inotify | – | no libinotify-kqueue in Homebrew |
| hwloc | – | only used on FreeBSD |
| Samba NetAPI | – | skipped: no x86_64 bottle, huge source build |
| gst-libav | – | GStreamer 1.24 predates the FFmpeg 9 API |
| gettextpo | – | only needed to regenerate `.po` files |

`scripts/configure-wine.sh` passes every enabled feature as `--with-*`, so a
missing dependency fails configure instead of being silently dropped.

## Patches

| Patch | Content |
|---|---|
| `0001-ws2_32-hoyoverse-game-hacks.patch` | `StarRail.exe` (or any exe with `WINE_ENABLE_DISCONNECT=1`): the first `connect()` is refused; opt out with `WINE_DISABLE_DISCONNECT=1`. `GenshinImpact.exe` / `YuanShen.exe` / `ZenlessZoneZero.exe` with `WINE_ENABLE_TIMEOUT_FIX=1`: patches curl's timeout in memory to 60 s |

