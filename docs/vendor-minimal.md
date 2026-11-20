# A minimal vendor layer

> **Since 2026-11-20 (evening) there is no vendor layer to ship:** BasedOS runs next to stock and
> uses stock's files in place. The files listed under "Stays stock" are links in the system layer
> into stock's own SYSTEM, mounted read-only at `/stock` (plan.md, Architecture), and stock's
> kernel and DTBs are booted from stock's boot partition. The inventory below still says which
> stock files BasedOS uses; the "vendor set" and its ids are history.

Goal (decided 2026-11-19): the vendor layer holds only what can't be BasedOS's own, the closed
GPU drivers, the Wi-Fi and Bluetooth firmware and the stock kernel's modules, and so changes only
when GKD ships a new kernel or GPU driver. Everything else becomes part of the system layer, built
by BasedOS from source, carried by `.bosupd` updates and publishable.

This is the inventory (phase 1). Phase 2 builds the replacements; phase 3 verifies them.

## Today (stock c8ed06c, vendor 7e0fbd18746b)

173 MB, 844 files (997 paths with links), from 54 lines of `manifest/harvest.list` plus the
libraries they need (`out/harvest-report.txt` says why each path is there).

- By size it is nearly all blobs: the Mali GPU and Vulkan drivers and the Wi-Fi firmware are about
  110 MB, the kernel modules 22 MB.
- By count it is mostly not: ALSA's configuration data is 714 of the 997 paths, the stock kernel's
  whole module tree 167 (mostly DVB tuner drivers; BasedOS loads only `bcmdhd`), and the rest is
  ordinary open-source userland: glibc, OpenSSL, libstdc++, glib, sqlite, ncurses, ALSA,
  wpa_supplicant (which brings D-Bus and libsystemd), OpenSSH, the filesystem tools, and stock's
  SDL2 2.32.6, which BasedOS's own SDL2 overrides (dead weight).

## Stays stock: the target vendor layer

| What | Files | Why it can't be ours |
|---|---|---|
| Mali Bifrost G52 GLES/EGL driver | `libmali.so.1.9.0` (+ `libmali.so`, `.so.1`), `libmali-hook.so.1.9.0` (+ `.so.1`) | closed (Arm, Rockchip build `g24p0`) |
| Mali's GL API wrappers | `libEGL.so.1`, `libGLESv1_CM.so.1`, `libGLESv2.so.2`, `libgbm.so.1`, `libwayland-egl.so.1` (stock's `/usr/lib/mali/`, real files, not links) | part of the Mali package |
| Mali GLES/EGL driver, 32-bit, and its wrappers | stock's `/usr/lib32`: the same files as above (38 MB), for PortMaster's 32-bit ports (docs/lib32.md, 2026-11-19) | closed |
| Mali Vulkan driver | `libmali-vulkan-g52.so` (+ `libMaliVulkan.so.1`), `/usr/share/vulkan/icd.d/mali.json` | closed |
| Wi-Fi and Bluetooth firmware | `/usr/lib/firmware/`: `fw_bcm4345*.bin`, `nvram_ap625*.txt`, `BCM4345C*.hcd` (10 files) | Broadcom, redistributable only as is |
| Kernel modules | `/usr/lib/modules/6.1.118/` (`bcmdhd.ko` is the one BasedOS loads) | must match stock's kernel, which BasedOS boots |
| Kernel and DTBs (since 2026-11-20) | stock's `Image` and `rk3576-gkd-atom{,-hdmi,-usbdp}.dtb`, as plain files beside `vendor.squashfs` in the vendor set (U-Boot loads them) | stock's build; in the vendor set so BasedOS boots its own copy of the kernel its modules came from, never stock's files (docs/plan.md, Architecture) |

What the closed drivers need, read from their ELF headers (2026-11-19): glibc 2.28 or newer, with
no versioned libstdc++ or CXXABI symbols; `libstdc++.so.6`, `libgcc_s.so.1`,
`libwayland-client.so.0`, `libwayland-server.so.0`, and for Vulkan `libdrm.so.2`. All of it is
open source, so the system layer can provide it, and the glibc version is BasedOS's choice.

Open: keep the whole module tree (static anyway, 22 MB), or only the modules anything loads
(`bcmdhd`, and filesystems such as `ntfs3` for USB storage if that comes).

## Replaced by BasedOS's own (the system layer)

Build tool: Buildroot at a pinned release, with a glibc toolchain (glibc 2.40 or newer, so that
ports built for ROCKNIX, PortMaster's main target, find what they were built against; GCC 14 or
newer), as a `br2-external` tree in this repo. Packages are Buildroot's names.

| Today from stock | Used by | Buildroot package |
|---|---|---|
| glibc: `ld-linux-aarch64.so.1`, `libc`, `libm`, `libmvec`, `libdl`, `libpthread`, `librt`, `libresolv`, `libutil`, `libnss_files`, `libnss_dns` | everything | the toolchain's glibc |
| `libstdc++`, `libgcc_s` | Mali, spruce's binaries | the toolchain's GCC runtime |
| `libwayland-client`, `libwayland-server` | Mali | `wayland` (libraries only) |
| `libdrm` | Mali Vulkan, spruce's `kmsgrab`, SDL2 | `libdrm` |
| `libvulkan.so.1` (Khronos loader) | Vulkan apps (DSperate) | `vulkan-loader` |
| `sshd`, `sshd-session`, `ssh-keygen`, `sftp-server`; `libcrypt` | BasedOS's own SSH (maintenance mode) | `openssh`, `libxcrypt` (or `dropbear`, as spruce uses) |
| `wpa_supplicant`, `wpa_passphrase` (+ D-Bus, libsystemd, zstd) | Wi-Fi; spruce runs its own instance | `wpa_supplicant` without D-Bus; `wpa_cli` comes with it (replaces `tools/wpa_cli/build.sh`) |
| `iw` | spruce's Wi-Fi settings | `iw` |
| `mke2fs`, `mkfs.ext4`, `e2fsck`, `fsck.ext4`, `resize2fs` | `/data` | `e2fsprogs` |
| `fsck.fat`, `fsck.vfat`, `fsck.exfat` | the card | `dosfstools`, `exfatprogs` |
| `amixer`, `aplay`, `libasound`, `/usr/share/alsa` (714 files) | audio; BasedOS edits `alsa.conf` | `alsa-lib`, `alsa-utils` (only the cards' configs this device needs) |
| `evtest` | spruce | `evtest` |
| `libudev.so.1` | loaded at run time by SDL builds that have udev (ports, PortMaster's SDL) | `eudev` (library) |
| `libSDL2_image`, `libSDL2_ttf` (+ fontconfig, freetype, expat, png, bzip2, zlib) | spruce's `display_text.elf` (message screens, USB storage mode) | `sdl2_image`, `sdl2_ttf`, built against BasedOS's SDL2 |
| `libssl.so.3`, `libcrypto.so.3`, `libdbus-1`, `libexpat`, `libfontconfig`, `libfreetype`, `libglib-2.0`, `libncursesw`, `libtinfo`, `libsndfile` (+ FLAC, Vorbis, Ogg), `libsqlite3`, `libuuid`, `libvorbisenc`, `libz`, `liblzma` | what spruce's card binaries expect from the base (`tools/needs-check.py` against a base of the system layer plus the blobs, 2026-11-19: 25 libraries, all of them in this table) | `openssl`, `dbus` (library), `expat`, `fontconfig`, `freetype`, `libglib2`, `ncurses`, `libsndfile`, `flac`, `libvorbis`, `libogg`, `sqlite`, `util-linux` (libuuid), `zlib`, `xz` |
| stock's SDL2 2.32.6 | nothing (BasedOS's own SDL2 overrides it) | dropped |

Also from the same build, for PortMaster's ports (the list of 2026-11-19): `libgomp` (toolchain),
`luajit`, `enet`, `json-c`, `libevdev`, `speexdsp`, `libusb`, `sdl12-compat`, `libcurl`,
`fluidsynth`, `libxml2`, `harfbuzz`, `libjpeg-turbo`, `tiff`; and the commands `taskset`
(`util-linux`), `stdbuf` (`coreutils`), `getconf` and `iconv` (glibc), `file`, `zstd`.

BasedOS's own builds stay as they are or move into the same tree: SDL2 with its patches and
librga (`tools/sdl2`), bash (`tools/bash`), BusyBox (Alpine's static build today).

Not carried yet: **ROCKNIX's compat libraries** (`/usr/lib/compat/compat/`, 64-bit only, 49
files): older-ABI builds for ports made on older systems, among them `libcrypto.so.1.1`,
`libxml2.so.2`, FFmpeg 4 (`libavcodec.so.58`, ...), `libvpx.so.6`, `libwebp.so.6`, `libFLAC.so.8`,
krb5 and a second SDL2. Stock's PortMaster `control.txt` names that folder's parent as `clibs`
(`/usr/lib/compat/`) and its `get_controls` sets `LD_LIBRARY_PATH` to it, one level above the
libraries themselves as the image is laid out. spruce's `control.txt` has no `clibs`. PortMaster's
own docs don't describe `clibs` or list what a system provides (2026-11-19); they ask ports to
carry what they need in `libs.<arch>`. Buildroot builds none of these old versions.

Not in spruce's needs and not stock's either (the card brings them, or they're unused on
BasedOS): `libpython3.10`, `libbsd`, `libcrypto.so.1.1`, `libffi.so.8`, Samba's `libtalloc`,
`libtdb`, `libtevent`, `libtheoraenc`.

## Risks

- glibc and the C++ runtime are under every program: a build that breaks them breaks the system.
  The A/B slots and the boot counter fall back to the other slot; test on the unit before a
  `.bosupd`.
- The closed Mali driver against a newer glibc and libstdc++: its headers ask for nothing newer
  than glibc 2.28 and no versioned C++ symbols, so this is expected to work; it is checked first
  (menu, a GLES game, Vulkan through DSperate).
- spruce's card binaries were built against older libraries; `needs-check.py` covers names, the
  unit covers behaviour.
- BasedOS's edits of stock files (ALSA's `alsa.conf`, PipeWire's configs left out) carry over to
  the new packages.

## Phase 2 and 3

2. A `br2-external` tree and defconfig in this repo; `tools/wsl/build.sh` runs Buildroot and installs
   its output into the system layer; `manifest/harvest.list` shrinks to the table above; the
   build's existing checks (no stock file in the system layer, every library resolved) stay.
3. On the unit: boot, the menu, a GLES game, Vulkan (DSperate), Wi-Fi in spruce and in maintenance
   mode, audio and the DAC volume after sleep, sleep and wake, an update from a `.bosupd`,
   PortMaster and a port; `needs-check.py` against the card.
