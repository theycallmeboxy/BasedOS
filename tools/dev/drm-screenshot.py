#!/usr/bin/env python3
"""Save what the panel shows as a PNG, straight from DRM (no kmsgrab needed). Run as root:
    drm-screenshot.py out.png
Finds the active CRTC's framebuffer (GETFB2), exports it as a dma-buf (PRIME) and maps it.
Works for linear XRGB/ARGB8888 buffers; a compressed (AFBC) buffer is reported, not decoded.
"""
import ctypes
import fcntl
import mmap
import os
import struct
import sys
import zlib


def iowr(nr, size):
    return (3 << 30) | (size << 16) | (ord("d") << 8) | nr


class ModeInfo(ctypes.Structure):
    _fields_ = [("clock", ctypes.c_uint32)] + [(n, ctypes.c_uint16) for n in
               ("hdisplay", "hsync_start", "hsync_end", "htotal", "hskew",
                "vdisplay", "vsync_start", "vsync_end", "vtotal", "vscan")] + \
              [("vrefresh", ctypes.c_uint32), ("flags", ctypes.c_uint32), ("type", ctypes.c_uint32),
               ("name", ctypes.c_char * 32)]


class CardRes(ctypes.Structure):
    _fields_ = [(n, ctypes.c_uint64) for n in ("fb_id_ptr", "crtc_id_ptr", "connector_id_ptr", "encoder_id_ptr")] + \
              [(n, ctypes.c_uint32) for n in ("count_fbs", "count_crtcs", "count_connectors", "count_encoders",
                                              "min_width", "max_width", "min_height", "max_height")]


class Crtc(ctypes.Structure):
    _fields_ = [("set_connectors_ptr", ctypes.c_uint64)] + \
              [(n, ctypes.c_uint32) for n in ("count_connectors", "crtc_id", "fb_id", "x", "y", "gamma_size", "mode_valid")] + \
              [("mode", ModeInfo)]


class Fb2(ctypes.Structure):
    _fields_ = [(n, ctypes.c_uint32) for n in ("fb_id", "width", "height", "pixel_format", "flags")] + \
              [("handles", ctypes.c_uint32 * 4), ("pitches", ctypes.c_uint32 * 4), ("offsets", ctypes.c_uint32 * 4),
               ("modifier", ctypes.c_uint64 * 4)]


class Prime(ctypes.Structure):
    _fields_ = [("handle", ctypes.c_uint32), ("flags", ctypes.c_uint32), ("fd", ctypes.c_int32)]


def png(path, w, h, rows):
    raw = b"".join(b"\0" + r for r in rows)
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def main():
    out = sys.argv[1]
    dev = os.open("/dev/dri/card0", os.O_RDWR)
    res = CardRes()
    fcntl.ioctl(dev, iowr(0xA0, ctypes.sizeof(res)), res)
    ids = (ctypes.c_uint32 * res.count_crtcs)()
    res2 = CardRes(crtc_id_ptr=ctypes.addressof(ids), count_crtcs=res.count_crtcs)
    fcntl.ioctl(dev, iowr(0xA0, ctypes.sizeof(res2)), res2)
    for cid in ids:
        crtc = Crtc(crtc_id=cid)
        fcntl.ioctl(dev, iowr(0xA1, ctypes.sizeof(crtc)), crtc)
        if crtc.fb_id:
            break
    else:
        sys.exit("no active CRTC")
    fb = Fb2(fb_id=crtc.fb_id)
    fcntl.ioctl(dev, iowr(0xCE, ctypes.sizeof(fb)), fb)
    fourcc = struct.pack("<I", fb.pixel_format).decode("ascii", "replace")
    print(f"crtc {cid} fb {fb.fb_id}: {fb.width}x{fb.height} {fourcc} pitch {fb.pitches[0]} modifier {fb.modifier[0]:#x}")
    if fb.modifier[0] not in (0, 0xFFFFFFFFFFFFFF) and fb.flags & 2:
        sys.exit("framebuffer is compressed/tiled (modifier set); not decoded")
    prime = Prime(handle=fb.handles[0], flags=os.O_RDWR | 0o2000000)
    fcntl.ioctl(dev, iowr(0x2D, ctypes.sizeof(prime)), prime)
    size = fb.pitches[0] * fb.height + fb.offsets[0]
    m = mmap.mmap(prime.fd, size, mmap.MAP_SHARED, mmap.PROT_READ)
    w, h, pitch, off = fb.width, fb.height, fb.pitches[0], fb.offsets[0]
    rows = []
    for y in range(h):
        line = m[off + y * pitch: off + y * pitch + w * 4]
        b, g, r = line[0::4], line[1::4], line[2::4]
        row = bytearray(w * 3)
        row[0::3], row[1::3], row[2::3] = r, g, b
        rows.append(bytes(row))
    png(out, w, h, rows)
    print(f"wrote {out} ({w}x{h})")


if __name__ == "__main__":
    main()
