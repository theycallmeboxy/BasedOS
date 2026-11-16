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

Status: planning and v0 bring-up. Not ready for use.
