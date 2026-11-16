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

## What builds contain, and why none are published

A BasedOS image built with these tools contains:

| Part | From | License | In this repo? |
|---|---|---|---|
| BasedOS scripts and config (`overlay/`, `initrd/`) | this repo | MIT | yes |
| BusyBox (`busybox-static`, aarch64) | Alpine Linux v3.20, downloaded at build time | GPL-2.0 | no |
| Kernel, DTBs, libmali, Wi-Fi firmware and module, glibc, SDL2, Python, OpenSSH, ALSA, ... | the user's own stock firmware (harvested from their backup) | various: GPL, LGPL, proprietary (libmali, Broadcom firmware) | no, hashes only (`manifest/`) |

Because of the vendor parts, **built images are personal and must not be published.** The
BasedOS releases this repo makes carry only its own files and tools, and every device builds the
rest from its own firmware. If BasedOS images ever were distributed, BusyBox's GPL-2.0 would
also require offering its source (Alpine's `busybox` APKBUILD and source).

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
