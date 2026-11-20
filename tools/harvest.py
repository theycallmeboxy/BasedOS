#!/usr/bin/env python3
"""Copy the harvest list out of an unpacked root (stock's, or BasedOS's Buildroot output), plus
every library those files need (a closed set), into a staging tree.

  harvest.py <source root> <list> <staging root> [--provided <root>] [--report <file>]
             [--lib32 <dir>]

--provided: a root whose libraries count as there already (the system layer's, when harvesting
the vendor layer's blobs), so they aren't copied from the source again.
--lib32: where 32-bit (armhf) libraries are looked for, in every root (default /usr/lib32, as
the system layer and stock lay them out; /usr/lib for BasedOS's 32-bit Buildroot root, whose
libraries build-rootfs.sh then moves to /usr/lib32). 64-bit ones are looked for in /usr/lib.
--report: where the report goes (default <staging root>/../harvest-report.txt).

Run it on a filesystem with real symlinks (WSL's ext4, not /mnt/c).
Fails if any DT_NEEDED can't be found, like baseos-my355's prepare_stock.py.
Writes <staging>/../harvest-report.txt listing what was copied and why.
"""
import os
import shutil
import struct
import sys

LIBDIRS = ("/usr/lib",)


def elf_class(path):
    """64 or 32 for an ELF file, None for anything else."""
    try:
        with open(path, "rb") as f:
            b = f.read(5)
    except OSError:
        return None
    if b[:4] != b"\x7fELF":
        return None
    return {1: 32, 2: 64}.get(b[4])


def elf_needed(path):
    try:
        with open(path, "rb") as f:
            b = f.read()
    except OSError:
        return None
    if b[:4] != b"\x7fELF" or b[4] not in (1, 2):
        return None
    if b[4] == 2:
        phoff, = struct.unpack_from("<Q", b, 0x20)
        phentsize, phnum = struct.unpack_from("<HH", b, 0x36)
        # p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz
        ph, ph_fields, dyn_fmt, dyn_size = "<IIQQQQ", (0, 2, 3, 5), "<qQ", 16
    else:
        phoff, = struct.unpack_from("<I", b, 0x1C)
        phentsize, phnum = struct.unpack_from("<HH", b, 0x2A)
        # p_type, p_offset, p_vaddr, p_paddr, p_filesz
        ph, ph_fields, dyn_fmt, dyn_size = "<IIIII", (0, 1, 2, 4), "<iI", 8
    dyn = None
    loads = []
    for i in range(phnum):
        f = struct.unpack_from(ph, b, phoff + i * phentsize)
        p_type, p_off, p_vaddr, p_filesz = (f[j] for j in ph_fields)
        if p_type == 2:
            dyn = (p_off, p_filesz)
        elif p_type == 1:
            loads.append((p_vaddr, p_off, p_filesz))
    if not dyn:
        return []
    needed, strtab = [], None
    for o in range(dyn[0], dyn[0] + dyn[1], dyn_size):
        tag, val = struct.unpack_from(dyn_fmt, b, o)
        if tag == 0:
            break
        if tag == 1:
            needed.append(val)
        elif tag == 5:
            strtab = val
    if strtab is None:
        return []
    for vaddr, off, size in loads:
        if vaddr <= strtab < vaddr + size:
            base = strtab - vaddr + off
            break
    else:
        return []
    return [b[base + n:b.index(b"\0", base + n)].decode() for n in needed]


class Harvest:
    def __init__(self, stock, dest, provided=None, lib32="/usr/lib32"):
        self.stock, self.dest, self.provided, self.why = stock, dest, provided, {}
        self.lib32 = (lib32,)

    def libdirs(self, path):
        """Where the libraries an ELF file needs are: its own class's directory."""
        return self.lib32 if elf_class(path) == 32 else LIBDIRS

    def s(self, p):
        return os.path.join(self.stock, p.lstrip("/"))

    def d(self, p):
        return os.path.join(self.dest, p.lstrip("/"))

    def resolve(self, p, depth=0):
        """Follow a stock-side symlink chain (absolute links stay inside the stock root)."""
        full = self.s(p)
        if depth > 20 or not os.path.islink(full):
            return p
        t = os.readlink(full)
        nxt = t if t.startswith("/") else os.path.normpath(os.path.join(os.path.dirname(p), t))
        return self.resolve(nxt, depth + 1)

    def copy(self, src, dst, why):
        full = self.s(src)
        if os.path.isdir(full) and not os.path.islink(full):
            for root, dirs, files in os.walk(full):
                rel = os.path.relpath(root, full)
                for n in dirs + files:
                    sub = os.path.normpath(os.path.join(src, rel, n))
                    if os.path.islink(self.s(sub)) or not os.path.isdir(self.s(sub)):
                        self.copy(sub, os.path.normpath(os.path.join(dst, rel, n)), why)
            return
        out = self.d(dst)
        if os.path.lexists(out):
            return
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if os.path.islink(full) and src == dst:
            t = os.readlink(full)
            os.symlink(t, out)
            self.why[dst] = why + " (symlink)"
            # Follow one hop at a time, so every link in a chain a -> b -> c is copied too.
            nxt = t if t.startswith("/") else os.path.normpath(os.path.join(os.path.dirname(src), t))
            self.copy(nxt, nxt, why)
        else:
            real = self.resolve(src)
            if not os.path.exists(self.s(real)):
                sys.exit(f"missing in stock: {src} ({why})")
            shutil.copy2(self.s(real), out, follow_symlinks=True)
            self.why[dst] = why

    def find_lib(self, name, dirs):
        for d in dirs:
            p = f"{d}/{name}"
            if os.path.lexists(self.s(p)):
                return p
        return None

    def close(self):
        done, missing = set(), []
        while True:
            todo = [p for p in list(self.why) if p not in done]
            if not todo:
                break
            for p in todo:
                done.add(p)
                full = self.d(p)
                if os.path.islink(full) or not os.path.isfile(full):
                    continue
                dirs = self.libdirs(full)
                for lib in elf_needed(full) or []:
                    if any(os.path.lexists(self.d(f"{d}/{lib}")) for d in dirs):
                        continue
                    # Beside the file that needs it ($ORIGIN): glibc's gconv modules and their
                    # helper libraries (libJIS.so, libGB.so, ...) in /usr/lib/gconv.
                    if os.path.lexists(os.path.join(os.path.dirname(full), lib)):
                        continue
                    if self.provided and any(
                            os.path.lexists(os.path.join(self.provided, d.lstrip("/"), lib)) for d in dirs):
                        continue
                    src = self.find_lib(lib, dirs)
                    if not src:
                        missing.append(f"{lib} (needed by {p})")
                        continue
                    self.copy(src, src, f"needed by {p}")
        return missing


def main():
    args, opts = [], {}
    it = iter(sys.argv[1:])
    for a in it:
        if a in ("--provided", "--report", "--lib32"):
            opts[a] = next(it, None)
        else:
            args.append(a)
    if len(args) != 3 or None in opts.values():
        sys.exit(__doc__)
    stock, listfile, dest = args
    h = Harvest(stock, dest, opts.get("--provided"), opts.get("--lib32", "/usr/lib32"))
    for line in open(listfile, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        src, _, dst = (x.strip() for x in line.partition("=>"))
        h.copy(src, dst or src, "listed")
    missing = h.close()
    report = opts.get("--report") or os.path.join(os.path.dirname(os.path.abspath(dest)), "harvest-report.txt")
    with open(report, "w", encoding="utf-8") as r:
        for p in sorted(h.why):
            r.write(f"{p}\t{h.why[p]}\n")
    size = sum(os.path.getsize(h.d(p)) for p in h.why if not os.path.islink(h.d(p)))
    print(f"harvested {len(h.why)} paths, {size / 2**20:.1f} MiB; report: {report}")
    if missing:
        sys.exit("UNRESOLVED:\n  " + "\n  ".join(sorted(set(missing))))


if __name__ == "__main__":
    main()
