# Notices

## BasedOS

Everything in this repository is under the MIT license (`LICENSE`), copyright theycallmeboxy.
Parts were written with Claude (Anthropic); commits say so in their `Co-Authored-By` lines.

## Credits

BasedOS follows the design and conventions of two projects. **No code is copied from either**:
the overlay scripts, initrd, build and recovery tools here were written for this device.

- **BaseOS for Allwinner H700 handhelds** by Prashant Vaibhav,
  https://github.com/pvaibhav/BaseOS: the product model (a base OS on internal storage that boots a
  frontend from a separate, portable card), the frontend entry points including spruce's
  `runtime.sh`, `/etc/baseos-release` with the frontend environment.
- **BaseOS for the Miyoo Flip** by Aurélien Pommel (MIT), https://github.com/apommel/baseos-my355:
  BusyBox init with `rcS`/`frontend-session`/`rcK`, the stock-harvest approach with a closed-set
  library check, `.bosupd` naming, the `/mnt/SDCARD` mount, and its NOTICE's stance on vendor files.
- **spruceOS**, https://github.com/spruceUI/spruceOS: the frontend BasedOS exists to run.
- **ROCKNIX** and **GKD (GameKiddy)**: the stock firmware whose kernel and userland BasedOS reuses
  from the user's own device.

## What builds contain, and what can be published

A BasedOS build is two read-only layers. The **system layer** (`rootfs.squashfs`, and the
`.bosupd` update that carries it) holds only the parts marked "this repo" or "built from
source" below; the build fails if any stock file is in it. The **vendor layer**
(`vendor-<id>.squashfs`) holds the parts from the user's own stock firmware. Together they contain:

| Part | From | License | In this repo? |
|---|---|---|---|
| BasedOS scripts and config (`overlay/`, `initrd/`) | this repo | MIT | yes |
| The boot screen's font (`tools/boot-ui/font.h`, in `basedos-splash`) | converted from Terminus Font (bold 16x32), Copyright (c) 2010 Dimitar Toshkov Zhekov, by `tools/boot-ui/mkfont.py` | SIL Open Font License 1.1 (`tools/boot-ui/OFL-Terminus.txt`, also in the image at `/usr/share/licenses/basedos-splash/`) | yes |
| BusyBox (`busybox-static`, aarch64) | Alpine Linux v3.20, downloaded at build time | GPL-2.0 | no |
| BasedOS's userland (`manifest/base.list`): glibc 2.41 and GCC 14's runtime, OpenSSH, wpa_supplicant and `wpa_cli`, iw, e2fsprogs, dosfstools, exfatprogs, ALSA, Wayland's and libdrm's libraries, the Vulkan loader, OpenSSL, the D-Bus library, glib, SDL2_image, SDL2_ttf, and the libraries spruce and PortMaster's ports expect | built from source by Buildroot 2025.02.20 (sha256 pinned) with this repo's `buildroot/` tree (`tools/buildroot/build.sh`) | each package's own: GPL-2.0/3.0, LGPL-2.1, BSD, MIT, zlib and others; Buildroot's `make legal-info` lists every package with its licence and source | the build configuration only |
| bash 5.2.37 (GNU, https://www.gnu.org/software/bash/) | built from GNU's release tarball (sha256 pinned) by `tools/bash/build.sh`, against glibc only, for PortMaster and its ports | GPL-3.0-or-later (in the image at `/usr/share/licenses/bash/COPYING`) | build script only |
| SDL2 2.32.10 with ArkOS's SDL2 patches (christianhaitian/rk3566_core_builds, MIT; copies in `tools/sdl2/patches/`), and librga 1.10.5 (Rockchip, JeffyCN/mirrors linux-rga-multi) | built from source by `tools/sdl2/build.sh` | zlib (SDL), MIT (patches), Apache-2.0 (librga) | patches and build script only |
| Kernel, DTBs (boot files on p1); in the vendor layer: the Mali GPU and Vulkan drivers, the Wi-Fi and Bluetooth firmware, the kernel's modules (`manifest/harvest.list`) | the user's own stock firmware (harvested from their backup) | proprietary (Mali, Broadcom firmware), GPL-2.0 (the modules) | no, hashes only (`manifest/`) |

Because of the vendor parts, **the vendor layer, and any whole image, are personal and must not be
published.** Each device builds its own from its own firmware. The system layer and `.bosupd`
updates hold BasedOS's own files only and can be released; a release that ships them must also
offer BusyBox's source (GPL-2.0: Alpine's `busybox` APKBUILD and source), bash's
(GPL-3.0: `bash-5.2.37.tar.gz` from ftp.gnu.org, unmodified) and the GPL and LGPL packages of the
Buildroot userland (the sources `make legal-info` collects), and carries the
licences above (`/usr/share/licenses/`).

## Tools that use third-party files at run time

- `tools/maskrom/mk-usb-loader.py` builds a maskrom loader from Rockchip's `rkbin` blobs
  (https://github.com/rockchip-linux/rkbin, under Rockchip's own license), which the user
  downloads. No `rkbin` file is in this repo.
- `tools/dev/gkdssh.py` uses paramiko (LGPL-2.1); the build scripts use squashfs-tools (GPL-2.0)
  and, optionally, zstandard (BSD). None are bundled.

## spruce changes

The spruce changes for this device live in the spruce fork
(https://github.com/theycallmeboxy/spruceOS, branch `gkd350h-ultra`) under spruce's own license.
`tools/spruce-kit.py` packages them as an overlay and patches with release notes.
