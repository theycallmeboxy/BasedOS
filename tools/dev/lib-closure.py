#!/usr/bin/env python3
"""Run ON the device: what does a folder of libraries need that neither it nor BasedOS has?

  lib-closure.py [<folder> [<harvest.py's folder>]]

Default folder: spruce's spruce/flip/lib, which spruce puts on every program's library path (its
libraries for ports, PortMaster's GUI and its Python). Each library's DT_NEEDED is looked up in
that folder and BasedOS's /usr/lib; what's in neither is printed with the libraries that need it.
A missing one breaks everything that loads those libraries, however far down (2026-11-19:
libbsd.so.0, for flip's libXdmcp on its PulseAudio client chain, broke ports' music libraries).
Needs harvest.py beside it or in the folder given (push both to /tmp), and any Python 3
(spruce's: LD_LIBRARY_PATH=/mnt/SDCARD/spruce/flip/lib /mnt/SDCARD/spruce/flip/bin/python3.10).
"""
import collections
import os
import sys

here = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from harvest import elf_needed  # noqa: E402

folder = sys.argv[1] if len(sys.argv) > 1 else "/mnt/SDCARD/spruce/flip/lib"
have = set(os.listdir(folder)) | set(os.listdir("/usr/lib"))
miss = collections.defaultdict(list)
for n in sorted(os.listdir(folder)):
    p = os.path.join(folder, n)
    if os.path.islink(p) or ".so" not in n or not os.path.isfile(p):
        continue
    for lib in elf_needed(p) or []:
        if lib not in have and not lib.startswith("$ORIGIN"):
            miss[lib].append(n)
for lib, users in sorted(miss.items(), key=lambda x: -len(x[1])):
    print(f"{lib}: {len(users)} ({', '.join(users[:6])})")
print(f"{len(miss)} missing")
