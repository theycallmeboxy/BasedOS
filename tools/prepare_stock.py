#!/usr/bin/env python3
"""Pull the stock files BasedOS needs out of a GKD 350H Ultra eMMC backup.

  prepare_stock.py <mmcblk0.img> <out dir>

Reads p1 (FAT32 at sector 32768) inside the raw image, follows each file's
cluster chain, and keeps only files whose SHA-256 matches a known stock build
in manifest/stock-builds.txt. An unknown build stops here, so nothing
unverified gets into a BasedOS image. The outputs are your own device's
files: keep them out of git and out of releases.
"""
import hashlib
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
P1_SECTOR = 32768


def load_builds():
    builds, cur = {}, None
    for line in open(os.path.join(HERE, "..", "manifest", "stock-builds.txt"), encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            cur = builds.setdefault(line[1:-1], {})
            continue
        sha, name = line.split()
        cur[sha] = name
    return builds


class Fat32:
    def __init__(self, f, base):
        self.f, self.base = f, base
        f.seek(base)
        bs = f.read(512)
        if bs[82:87] != b"FAT32":
            sys.exit("p1 is not FAT32")
        bps, spc, res, nf = struct.unpack_from("<HBHB", bs, 11)
        fatsz, self.root = struct.unpack_from("<I", bs, 36)[0], struct.unpack_from("<I", bs, 44)[0]
        self.cl = bps * spc
        self.data = base + (res + nf * fatsz) * bps
        f.seek(base + res * bps)
        self.fat = f.read(fatsz * bps)

    def chain(self, c):
        out = []
        limit = len(self.fat) // 4
        while 2 <= c < 0x0FFFFFF8:
            if len(out) > limit:
                sys.exit("FAT cluster chain loops; the image is damaged")
            out.append(c)
            c = struct.unpack_from("<I", self.fat, c * 4)[0] & 0x0FFFFFFF
        return out

    def runs(self, c):
        ch = self.chain(c)
        start = prev = ch[0]
        for x in ch[1:]:
            if x != prev + 1:
                yield start, prev - start + 1
                start = x
            prev = x
        yield start, prev - start + 1

    def read_to(self, clus, size, out):
        h, left = hashlib.sha256(), size
        for start, n in self.runs(clus):
            self.f.seek(self.data + (start - 2) * self.cl)
            want = min(left, n * self.cl)
            while want:
                buf = self.f.read(min(want, 8 << 20))
                if not buf:
                    sys.exit("the image ends inside a file; it is truncated")
                h.update(buf)
                if out:
                    out.write(buf)
                want -= len(buf)
                left -= len(buf)
            if not left:
                break
        return h.hexdigest()

    def root_files(self):
        raw = b"".join(self._clus(c) for c in self.chain(self.root))
        for i in range(0, len(raw), 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5 or e[11] & 0x18 or e[11] == 0x0F:
                continue
            clus = (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]
            size = struct.unpack_from("<I", e, 28)[0]
            if clus and size:
                yield e[0:11].decode("latin1"), clus, size

    def _clus(self, c):
        self.f.seek(self.data + (c - 2) * self.cl)
        return self.f.read(self.cl)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    img, out = sys.argv[1:]
    builds = load_builds()
    with open(img, "rb") as f:
        fs = Fat32(f, P1_SECTOR * 512)
        found = {}
        for short, clus, size in fs.root_files():
            sha = fs.read_to(clus, size, None)
            for build, names in builds.items():
                if sha in names:
                    found.setdefault(build, {})[names[sha]] = (clus, size, sha)
            print(f"{short!r:16} {size:11} {sha[:16]}")
        build = next((b for b, files in found.items() if len(files) == len(builds[b])), None)
        if not build:
            sys.exit("no known stock build matched in full; see manifest/stock-builds.txt")
        dest = os.path.join(out, build)
        os.makedirs(dest, exist_ok=True)
        for name, (clus, size, sha) in sorted(found[build].items()):
            path = os.path.join(dest, name)
            with open(path + ".part", "wb") as o:
                got = fs.read_to(clus, size, o)
            if got != sha:
                sys.exit(f"{name}: hash changed while copying")
            os.replace(path + ".part", path)
            print(f"  {build}/{name}  ok")
    with open(os.path.join(dest, "BUILD"), "w", encoding="utf-8") as b:
        b.write(build + "\n")
    print(f"stock build {build}: {len(found[build])} files in {dest}")


if __name__ == "__main__":
    main()
