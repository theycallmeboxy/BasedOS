#!/usr/bin/env python3
"""Build a BasedOS update payload (.bosupd) from a finished build.

  mkupdate.py <system rootfs.squashfs> <initrd.uimg> <stock build id> <version> <build> <out dir>

Writes <out dir>/baseos-gkd350hultra-<version>.bosupd: an uncompressed tar of `manifest`,
`rootfs.squashfs` (the system layer) and `initrd.uimg`. Only BasedOS's own files: BasedOS uses
the device's own stock files in place (links into /stock), so the manifest names the stock build
this system layer's links are made against (`stock`, its BUILD_ID), and a device with another
stock refuses the payload. The name is spruce's (baseos_local_update_file looks for baseos-<target>-*.bosupd at the
card root); the format is BasedOS's own (`basedos-update/1`; overlay/usr/sbin/basedos-update
applies it). Integrity is a SHA-256 per file, checked again after writing; no signature, as the
BaseOS projects: a key would be a single point of failure, and these files carry no secrets.
"""
import hashlib
import io
import os
import sys
import tarfile

TARGET = "gkd350hultra"
FORMAT = "basedos-update/1"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    rootfs, initrd, stock, version, build, outdir = sys.argv[1:]
    fields = [
        ("format", FORMAT),
        ("target", TARGET),
        ("version", version),
        ("build", build),
        ("stock", stock),
        ("rootfs-sha256", sha256(rootfs)),
        ("initrd-sha256", sha256(initrd)),
    ]
    manifest = "".join(f"{k}={v}\n" for k, v in fields).encode()
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"baseos-{TARGET}-{version}.bosupd")
    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as tar:
        def add(name, data=None, path=None):
            info = tarfile.TarInfo(name)
            info.size = len(data) if data is not None else os.path.getsize(path)
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mode = 0o644
            if data is not None:
                tar.addfile(info, io.BytesIO(data))
            else:
                with open(path, "rb") as f:
                    tar.addfile(info, f)
        add("manifest", data=manifest)
        add("rootfs.squashfs", path=rootfs)
        add("initrd.uimg", path=initrd)
    print(f"{out} ({os.path.getsize(out)} bytes)")
    print(manifest.decode(), end="")


if __name__ == "__main__":
    main()
