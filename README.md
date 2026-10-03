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
| FreeType, GnuTLS, SDL2 (sdl2-compat), Vulkan loader, libusb, krb5/GSSAPI, fontconfig, SANE, libgphoto2, unixODBC, PulseAudio, D-Bus, gettext | Homebrew | enabled |
| CoreAudio, OpenCL, PCSC, CUPS, libpcap, libunwind | macOS SDK | enabled |
| FFmpeg 9.0.2 (winedmo) | built from source | enabled |
| GStreamer 1.24 core/base/good | built from the CrossOver-bundled tree | enabled |
| MoltenVK 1.2.10 (CodeWeavers-patched) | built from the CrossOver-bundled tree | enabled, default Vulkan driver |
| KosmicKrisp (Mesa main + [!44786](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44786) geometry shaders, pinned by `MESA_GIT_SHA`) | cross-built to x86_64 on an arm64 runner | enabled, opt-in |
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

## Vulkan drivers

Wine is linked against the Khronos Vulkan loader rather than directly against
MoltenVK, and both drivers ship with manifests in `share/vulkan/icd.d`:

| Driver | Select with | Notes |
|---|---|---|
| MoltenVK (CodeWeavers-patched) | default | geometry shader emulation and the other changes CrossOver's DXVK relies on |
| KosmicKrisp | `WINE_VK_DRIVER=kosmickrisp` | conformant Vulkan 1.3+ on Metal 4; **Apple silicon + macOS 26 only** |

Setting `VK_DRIVER_FILES`, `VK_ICD_FILENAMES` or `VK_ADD_DRIVER_FILES`
yourself overrides both (`patches/wine/0006`).

## DXVK for KosmicKrisp

`lib/dxvk/{x64,x32}` holds DXVK 2.7.1 with `patches/dxvk` applied. It's
built separately and not installed over Wine's own d3d/dxgi:

| Patch | Why |
|---|---|
| 0001, 0002 | upstream build fixes for LLVM 22/23 (llvm-mingw 20260922) |
| 0003 | upstream: `VK_KHR_pipeline_library` is optional |
| 0004 | `fillModeNonSolid` is optional; wireframe/point fill renders solid without it |

KosmicKrisp still needs geometry shaders for this to work (DXVK requires
them for all of D3D8–11), i.e. a Mesa with
[!44786](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44786).
CrossOver's MoltenVK won't work either way: DXVK 2.x needs Vulkan 1.3.

To use it in a prefix:

```sh
cp lib/dxvk/x64/*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp lib/dxvk/x32/*.dll "$WINEPREFIX/drive_c/windows/syswow64/"
WINE_VK_DRIVER=kosmickrisp WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi=n,b" wine game.exe
```
