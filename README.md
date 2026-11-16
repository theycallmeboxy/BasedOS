# BasedOS for the GKD 350H Ultra

A small base OS for the eMMC of the GKD 350H Ultra (RK3576). Its only job
is to boot fast and hand the device to a frontend on a portable SD card, such
as spruceOS (NextUI later). That card stays an ordinary spruce card, so it
keeps working in your other spruce devices.

BasedOS follows the conventions of the two BaseOS projects it borrows from:
[apommel/baseos-my355](https://github.com/apommel/baseos-my355) (Miyoo Flip)
and [pvaibhav/BaseOS](https://github.com/pvaibhav/BaseOS) (Anbernic H700).
Frontends detect it the same way they detect BaseOS: `/etc/baseos-release`,
`BASEOS_TARGET=gkd350hultra`.

**Nothing vendor-made is in this repository or its releases.** The kernel,
GPU driver, Wi-Fi firmware and C library come from your own device's stock
firmware, harvested during installation. See [docs/plan.md](docs/plan.md).

Status: v0 boots on the device (installed next to stock, for developers).
Not ready for general use.

## What's here

| Path | What |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | **start here**: install, everyday use, safeguards, recovery |
| [docs/spruce-on-gkd.md](docs/spruce-on-gkd.md) | spruce support: the kit, status, what's left |
| [docs/plan.md](docs/plan.md) | design, conventions, status |
| [docs/boot-time.md](docs/boot-time.md), [docs/power.md](docs/power.md) | measurements |
| [docs/recovery.md](docs/recovery.md) | eMMC backup, rescue SD card, USB disk mode, maskrom, full restore (all tested) |
| [docs/recon.md](docs/recon.md) | hardware and stock-firmware notes |
| [docs/spruce-handoff.md](docs/spruce-handoff.md) | what spruce needs to run on BasedOS |
| `overlay/`, `initrd/` | BasedOS's own init, scripts and config |
| `manifest/` | the stock harvest list and known stock-build fingerprints |
| `tools/` | prepare-stock, harvest, rootfs and boot-file builders, dev install |
| `tools/dev/` | SSH helper, recon script, eMMC backup |
| `tools/rescue/` | rescue SD card built on the device from its own files |
| `tools/maskrom/` | builds the RK3576 maskrom USB loader from Rockchip's `rkbin` |

## License

MIT for everything in this repository (see `LICENSE`). Credits, third-party parts and why
built images are never published: [NOTICE.md](NOTICE.md).
