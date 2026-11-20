#!/usr/bin/env python3
"""What do PortMaster's ports load from the system? A scan of the ports themselves.

  pm-libscan.py <catalogue json> <download dir> <BasedOS root> <stock root> <out dir>
                [<frontend libs>]

<frontend libs>: a file of library file names the frontend itself puts on the ports' library
path (for spruce: `ls spruce/flip/lib Persistent/portmaster/lib` on the card); they count as
there for 64-bit ports, as BasedOS's own do.

<catalogue json> is PortMaster's port list (its ports.json, "data" -> "info"); <download dir>
holds ports/<name>.zip and runtimes/<arch>-<name>.squashfs (fetched from the URLs in that list).
For every ELF file in a port (any architecture), its DT_NEEDED names are taken; whatever the port
ships itself (any .so in its zip, by file name and SONAME) or gets from the runtimes it names
(their .so files) counts as bundled, and the rest is what it needs from the system. Each such
library is looked up in BasedOS (/usr/lib for 64-bit, /usr/lib32 for 32-bit) and in stock
(ROCKNIX: /usr/lib, its compat folder /usr/lib/compat/compat, /usr/lib32).

Also notes which launch scripts call system tools (box64, box86, jq, ffmpeg, python3, ...) or
ROCKNIX's compat path (clibs). x86 binaries (run by box64/box86) are counted apart: box emulates
their libraries.

Writes <out dir>/libscan.json (everything) and libscan.md (the tables). Needs unsquashfs.
"""
import collections
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

MACHINES = {183: "aarch64", 40: "armhf", 62: "x86_64", 3: "x86"}
TOOLS = ["box64", "box86", "jq", "ffmpeg", "ffprobe", "python3", "python", "7z", "7za", "unzip", "zip",
         "xdelta3", "innoextract", "mono", "dotnet", "java", "love", "squashfuse", "fusermount",
         "wget", "curl", "convert", "magick", "sox", "mpv", "sqlite3", "patchelf", "gl4es"]


def elf(b):
    """(arch, needed, soname) of ELF bytes, or None."""
    if len(b) < 64 or b[:4] != b"\x7fELF" or b[4] not in (1, 2) or b[5] != 1:
        return None
    is64 = b[4] == 2
    mach, = struct.unpack_from("<H", b, 0x12)
    arch = MACHINES.get(mach, f"m{mach}")
    try:
        if is64:
            phoff, = struct.unpack_from("<Q", b, 0x20)
            phentsize, phnum = struct.unpack_from("<HH", b, 0x36)
            ph, fields, dfmt, dsz = "<IIQQQQ", (0, 2, 3, 5), "<qQ", 16
        else:
            phoff, = struct.unpack_from("<I", b, 0x1C)
            phentsize, phnum = struct.unpack_from("<HH", b, 0x2A)
            ph, fields, dfmt, dsz = "<IIIII", (0, 1, 2, 4), "<iI", 8
        dyn, loads = None, []
        for i in range(phnum):
            f = struct.unpack_from(ph, b, phoff + i * phentsize)
            t, off, va, fs = (f[j] for j in fields)
            if t == 2:
                dyn = (off, fs)
            elif t == 1:
                loads.append((va, off, fs))
        if not dyn:
            return arch, [], None
        needed, sonames, strtab = [], [], None
        for o in range(dyn[0], dyn[0] + dyn[1], dsz):
            tag, val = struct.unpack_from(dfmt, b, o)
            if tag == 0:
                break
            if tag == 1:
                needed.append(val)
            elif tag == 14:
                sonames.append(val)
            elif tag == 5:
                strtab = val
        if strtab is None:
            return arch, [], None
        for va, off, fs in loads:
            if va <= strtab < va + fs:
                base = strtab - va + off
                break
        else:
            return arch, [], None
        s = lambda n: b[base + n:b.index(b"\0", base + n)].decode(errors="replace")
        return arch, [s(n) for n in needed], (s(sonames[0]) if sonames else None)
    except (struct.error, ValueError):
        return None


def scan_tree_files(items):
    """items: iterable of (path, bytes-getter). Returns (elfs, shipped names, scripts text)."""
    elfs, shipped, scripts = [], set(), []
    for path, get in items:
        base = os.path.basename(path)
        if path.endswith(".sh"):
            try:
                scripts.append((path, get().decode(errors="replace")))
            except Exception:
                pass
            continue
        if ".so" in base:
            shipped.add(base)
        try:
            head = get(64)
        except Exception:
            continue
        if head[:4] != b"\x7fELF":
            continue
        info = elf(get())
        if not info:
            continue
        arch, needed, soname = info
        if soname:
            shipped.add(soname)
        # Android libraries (GameMaker's, loaded by gmloader, which supplies bionic's libc.so,
        # libdl.so, liblog.so and the rest itself): not the system's business.
        android = any(n in ("liblog.so", "libandroid.so", "libc.so", "libOpenSLES.so") for n in needed)
        elfs.append({"path": path, "arch": arch, "needed": needed, "android": android})
    return elfs, shipped, scripts


def zip_items(z):
    for zi in z.infolist():
        if zi.is_dir() or zi.file_size == 0:
            continue
        def get(n=None, zi=zi):
            with z.open(zi) as f:
                return f.read(n) if n else f.read()
        yield zi.filename, get


def dir_items(root):
    for r, _, files in os.walk(root):
        for n in files:
            p = os.path.join(r, n)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            def get(k=None, p=p):
                with open(p, "rb") as f:
                    return f.read(k) if k else f.read()
            yield os.path.relpath(p, root), get


def names_in(d):
    return set(os.listdir(d)) if os.path.isdir(d) else set()


def main():
    catalogue, dl, basedos, stock, out = sys.argv[1:6]
    frontend = set()
    if len(sys.argv) > 6:
        frontend = {l.strip() for l in open(sys.argv[6], encoding="utf-8") if l.strip()}
    info = json.load(open(catalogue, encoding="utf-8"))["data"]["info"]
    os.makedirs(out, exist_ok=True)
    have = {
        "basedos64": names_in(os.path.join(basedos, "usr/lib")),
        "basedos32": names_in(os.path.join(basedos, "usr/lib32")),
        "stock64": names_in(os.path.join(stock, "usr/lib")),
        "stockcompat": names_in(os.path.join(stock, "usr/lib/compat/compat")),
        "stock32": names_in(os.path.join(stock, "usr/lib32")),
        "frontend64": frontend,
    }

    # Runtimes: what each ships (by name, per architecture), and what its own binaries need.
    runtimes = {}
    rdir = os.path.join(dl, "runtimes")
    for f in sorted(os.listdir(rdir)) if os.path.isdir(rdir) else []:
        if not f.endswith(".squashfs"):
            continue
        arch, name = f.split("-", 1)
        with tempfile.TemporaryDirectory() as t:
            subprocess.run(["unsquashfs", "-q", "-no-xattrs", "-d", t + "/r", os.path.join(rdir, f)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elfs, shipped, _ = scan_tree_files(dir_items(t + "/r"))
        runtimes[(arch, name)] = {"elfs": elfs, "shipped": shipped}
        print(f"runtime {arch} {name}: {len(elfs)} ELF files", file=sys.stderr)

    results = {}
    pdir = os.path.join(dl, "ports")
    for name, p in sorted(info.items()):
        zp = os.path.join(pdir, name)
        if not os.path.isfile(zp):
            continue
        try:
            with zipfile.ZipFile(zp) as z:
                elfs, shipped, scripts = scan_tree_files(zip_items(z))
        except zipfile.BadZipFile:
            continue
        rts = p["attr"].get("runtime") or []
        for r in rts:
            r = r if r.endswith(".squashfs") else r + ".squashfs"
            for a in ("aarch64", "armhf"):
                if (a, r) in runtimes:
                    shipped |= runtimes[(a, r)]["shipped"]
        tools = collections.Counter()
        clibs = False
        for path, text in scripts:
            body = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
            clibs |= "clibs" in body
            for t in TOOLS:
                # a bare command (not a path into the port, not $GAMEDIR/...): start of a command
                if re.search(rf"(^|[\s;&|(`]|\$\()({re.escape(t)})(\s|$)", body, re.M):
                    tools[t] += 1
        need = collections.defaultdict(set)
        archs = set()
        for e in elfs:
            archs.add(e["arch"])
            if e["android"]:
                continue
            for lib in e["needed"]:
                if lib not in shipped:
                    need[e["arch"]].add(lib)
        results[name] = {
            "title": p["attr"]["title"], "rtr": p["attr"]["rtr"], "runtime": rts,
            "archs": sorted(archs), "elf_count": len(elfs),
            "system": {a: sorted(v) for a, v in need.items()},
            "tools": sorted(tools), "clibs": clibs,
        }

    # Runtimes' own binaries count too: they run on the system like a port.
    for (arch, name), r in runtimes.items():
        need = collections.defaultdict(set)
        for e in r["elfs"]:
            if e["android"]:
                continue
            for lib in e["needed"]:
                if lib not in r["shipped"]:
                    need[e["arch"]].add(lib)
        results[f"runtime:{arch}-{name}"] = {"title": f"runtime {name}", "rtr": None, "runtime": [],
                                              "archs": sorted({e["arch"] for e in r["elfs"]}),
                                              "elf_count": len(r["elfs"]),
                                              "system": {a: sorted(v) for a, v in need.items()},
                                              "tools": [], "clibs": False}

    json.dump(results, open(os.path.join(out, "libscan.json"), "w"), indent=1)
    write_md(results, have, os.path.join(out, "libscan.md"))


def where(lib, arch, have):
    if arch == "aarch64":
        b = lib in have["basedos64"] or lib in have["frontend64"]
        s = "lib" if lib in have["stock64"] else ("compat" if lib in have["stockcompat"] else "")
    else:
        b = lib in have["basedos32"]
        s = "lib32" if lib in have["stock32"] else ""
    return b, s


def write_md(results, have, path):
    by = {"aarch64": collections.defaultdict(list), "armhf": collections.defaultdict(list)}
    broken = {"aarch64": collections.defaultdict(list), "armhf": collections.defaultdict(list)}
    tools = collections.defaultdict(list)
    clibs = []
    ports = [k for k in results if not k.startswith("runtime:")]
    for k, r in results.items():
        for arch, libs in r["system"].items():
            if arch not in by:
                continue
            for lib in libs:
                by[arch][lib].append(k)
                if not where(lib, arch, have)[0]:
                    broken[arch][k].append(lib)
        for t in r["tools"]:
            tools[t].append(k)
        if r["clibs"]:
            clibs.append(k)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# PortMaster ports: libraries loaded from the system\n\n{len(ports)} ports and "
                f"{len(results) - len(ports)} runtimes scanned (tools/pm-libscan.py)."
                + (f" 64-bit libraries count as there when BasedOS or the frontend's own folders "
                   f"({len(have['frontend64'])} files) have them." if have["frontend64"] else "")
                + "\n\n")
        for arch in ("aarch64", "armhf"):
            with_arch = [k for k in ports if arch in results[k]["system"]]
            bp = [k for k in broken[arch] if not k.startswith("runtime:")]
            stock_ok = [k for k in bp if all(where(l, arch, have)[1] for l in broken[arch][k])]
            f.write(f"## {arch}\n\n{len(with_arch)} ports have {arch} binaries that load system "
                    f"libraries; {len(bp)} of them need at least one BasedOS lacks, and for "
                    f"{len(stock_ok)} of those stock (ROCKNIX) has every one.\n\n")
            f.write("Libraries BasedOS lacks, by how many ports (and runtimes) need them:\n\n")
            f.write("| Library | Ports | Stock | Examples |\n|---|---|---|---|\n")
            for lib, ks in sorted(by[arch].items(), key=lambda x: (-len(x[1]), x[0])):
                b, s = where(lib, arch, have)
                if b:
                    continue
                ex = ", ".join(results[k]["title"] for k in ks[:4])
                f.write(f"| `{lib}` | {len(ks)} | {s or 'no'} | {ex} |\n")
            f.write("\n")
        f.write("## System tools named in launch scripts\n\n| Tool | Ports | Examples |\n|---|---|---|\n")
        for t, ks in sorted(tools.items(), key=lambda x: -len(x[1])):
            f.write(f"| `{t}` | {len(ks)} | {', '.join(results[k]['title'] for k in ks[:5])} |\n")
        f.write(f"\nScripts that use `clibs`: {len(clibs)} ({', '.join(results[k]['title'] for k in clibs[:8])})\n")


if __name__ == "__main__":
    main()
