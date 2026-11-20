#!/usr/bin/env python3
"""Which 32-bit libraries does stock's /usr/lib32 have that BasedOS's doesn't?

  lib32-gaps.py <stock root> <BasedOS root (system layer, or the merged view)>

PortMaster's 32-bit ports are built for ROCKNIX-style systems, whose /usr/lib32 is stock's, so a
library they load from the system and BasedOS lacks is likely in this list (docs/lib32.md).
Prints each missing library name (versioned .so.N names in /usr/lib32 itself), leaving out what
BasedOS doesn't carry on purpose (KNOWN_ABSENT). Prints only; build-rootfs.sh writes it beside
its reports, it doesn't fail the build.
"""
import os
import re
import sys

# Stock carries these for its own desktop, services and Mesa, and BasedOS has no use for them; or
# they are the 32-bit Mali driver's (EGL, GLES, gbm, wayland-egl), which are the vendor layer's.
KNOWN_ABSENT = re.compile(
    r"^lib(EGL\.|mali|gbm\.|wayland-egl\.|X|xcb|ICE|SM|GL|GLX|GLdispatch|OpenGL|EGL_mesa|GLX_mesa|glapi|xkb|xshmfence|xcvt|fontenc|"
    r"cups|avahi|pulse|pipewire|bluetooth|ldacBT|systemd|dbus|seat|input|bemenu|fcft|display-info|"
    r"vdpau|av|sw|postproc|dav1d|fdk-aac|ass|rockchip_|cairo|pango|gdk_pixbuf|gio|gobject|gmodule|"
    r"gthread|girepository|json-glib|nss_|BrokenLocale|c_malloc_debug|thread_db|nsl|asm|dw|elf|"
    r"pcap|pciaccess|kmod|mount|blkid|smartcols|gnutls|hogweed|nettle|idn2|gmp|asprintf|"
    r"gettextpo|textstyle|history|readline|form|menu|panel|ncurses\.|tinfow|crypt\.|vulkan_|"
    r"atopology|harfbuzz-|tiffxx|FLAC\+\+|out123|syn123|opusurl|jsoncpp|wavpack|pulse)")


def sonames(d):
    out = set()
    if os.path.isdir(d):
        for n in os.listdir(d):
            if re.search(r"\.so\.\d+$", n):
                out.add(n)
    return out


def main():
    stock, mine = sys.argv[1], sys.argv[2]
    have = sonames(os.path.join(mine, "usr/lib32"))
    missing = sorted(n for n in sonames(os.path.join(stock, "usr/lib32")) - have if not KNOWN_ABSENT.match(n))
    for n in missing:
        print(n)
    print(f"{len(missing)} in stock's /usr/lib32 and not BasedOS's", file=sys.stderr)


if __name__ == "__main__":
    main()
