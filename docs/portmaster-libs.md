# What PortMaster's ports need from the system

PortMaster doesn't publish a list of the libraries a system must provide: its packaging guide
asks ports to carry anything unusual in `libs.<arch>` and leaves "usual" undefined (2026-11-19).
So this is measured from the ports themselves.

## Method (2026-11-19)

PortMaster's catalogue of that day: all 1,511 ports (31 GB) and all 67 runtimes (Godot, Mono,
.NET, Java, Python, Weston, ...; 2.3 GB), downloaded to the PC (never to the device), each checked
against the catalogue's MD5.
`tools/pm-libscan.py` reads every ELF file in each port (and each runtime, unpacked): what it
needs (DT_NEEDED), less what the port ships (any `.so` in it) and what the runtimes it names
ship, is what it needs from the system. That is checked against BasedOS (64-bit `/usr/lib`,
32-bit `/usr/lib32`, the build of 2026-11-19) and stock ROCKNIX (`/usr/lib`, its compat folder,
`/usr/lib32`). The full table is [portmaster-libscan.md](portmaster-libscan.md).

Not seen by this: libraries loaded with `dlopen()` (SDL's ALSA and udev, GL through GL4ES),
and the libraries of x86 games run by box64/box86 (the game's binaries come from the buyer). A port whose zip has several binaries counts if any of them needs a missing
library, even one the port might not run on this device. GameMaker's Android libraries (which ask
for bionic's `libc.so`, `liblog.so`; gmloader supplies those) are not counted.

## Results

| | 64-bit ports | 32-bit ports |
|---|---|---|
| With binaries that load system libraries | 1,075 | 252 |
| Needing a library BasedOS alone lacks | 392 | 18 |
| ... counting spruce's own libraries too (what ports see on spruce) | 75 | 18 |
| ... after the additions below (build of 2026-11-19) | **41** | **14** |
| ... and FLAC 1.3 (2026-11-23) | **28** | **14** |

**spruce supplies most of it.** spruce puts its `spruce/flip/lib` (and PortMaster's `lib`) on
every port's library path on this platform (`BasedOSCommon.cfg`); it has SDL2_mixer, OpenAL,
libvorbisfile, PulseAudio's client libraries, mpg123, libmodplug and most of what ports load. So
BasedOS adds only what neither has, rather than shadowing spruce's copies (`/usr/lib` comes first
on that path):

- 64-bit: glib's gobject, gmodule and gio (47, 40 and 2 ports; glib was built already) and what
  `flip/lib` itself needs from the base and doesn't carry (`tools/dev/lib-closure.py` on the
  device): libbsd, for its libXdmcp and libICE on its PulseAudio client chain (the
  `libmikmod`/`libfluidsynth` that ports bundle link `libpulse-simple`), and libtheora's encoder
  for its FFmpeg 4. Without libbsd every port whose music libraries go through that chain failed
  to load them (Apricots: "Error loading libfluidsynth.so.1"), though the port scan, which looks
  only at a port's own binaries, counted them as covered.
- 32-bit: dbus, libgpg-error, LAME, glib's gobject/gmodule (spruce has no 32-bit libraries).

Checked on the device: Meritous didn't start (libgmodule, then libbsd) and now loads every library
(it then aborts with "buffer overflow detected" in the game itself, not looked into); Apricots
runs with its music library loaded.

**FLAC 1.3** (`libFLAC.so.8`, 13 ports, 2026-11-23): built from source by BasedOS's own Buildroot
package `flac13` (`buildroot/package/flac13`), the library alone, beside Buildroot's FLAC 1.4
(`libFLAC.so.12`). A7Xpg needed it (its `SDL_mixer`) and runs with it.

**OpenAL Soft, 64-bit, and `libopenal.so`** (2026-11-24): ports on PortMaster's Weston pack never
see spruce's `flip/lib` (the pack's `westonwrap.sh` sets the library path to its own folders and
the game's), so for them OpenAL has to be the system's. LWJGL 2 (libGDX games on Java) also finds
it only by the unversioned `libopenal.so` (or `libopenal64.so`) on Java's library path, which ends
in `/lib` and `/usr/lib`. BasedOS now builds OpenAL Soft 1.22 for 64-bit as it did for 32-bit, with
the `libopenal.so` link in both folders. Slay the Spire (Weston pack, Java) ran silent ("Could not
locate OpenAL library") and now has sound. Other 64-bit ports now get BasedOS's OpenAL before
`flip/lib`'s, as `/usr/lib` comes first on their path.

**What's left** (64-bit, 28 ports): old ABI versions Buildroot can't build, most of them in stock's
compat folder: OpenSSL 1.1 (`libcrypto.so.1.1`, 7 including
the Python runtimes; spruce's own `libssl.so.1.1` and `libzip.so.5` need it too), `libxml2.so.2`
(7), readline 7 and 8, desktop GL and X11 test libraries (Half-Life, Quake 2, Bugdom, the Java
runtimes), and single cases. 32-bit (14 ports): mostly OpenSSL 1.1 (`libcrypto.so.1.1`: Climb,
Super Hydorah, Mable and the Wood, Relic Hunters, Sulka and two more), which stock's `/usr/lib32`
lacks too: those ports were made for another system.

Tools ports call by bare name: `zip` (246 ports, mostly GameMaker setup steps), `unzip` (44),
`python3` (19), `mono`/`java`/`dotnet` (their runtimes provide them). spruce supplies `zip`
(`spruce/bin64`) and `python3` (`spruce/flip/bin`) on the ports' `PATH`; BusyBox has `unzip`.
Only one port calls a system `box64` (Super Hexagon). No port uses ROCKNIX's `clibs`: its compat
folder reaches ports only through ROCKNIX's own `get_controls`.

## Next

The rest of the old-ABI set (OpenSSL 1.1, libxml2.so.2, ...) only if particular ports are wanted,
built from source as FLAC 1.3 was where Buildroot can't, or as a separate compat folder rather than on the normal library path. A frontend other than spruce
would need the libraries spruce supplies (rerun the scan without its list to see them).
To rerun: the scan with spruce's library list (`ls spruce/flip/lib Persistent/portmaster/lib`
on the card) as the last argument, and `lib-closure.py` on the device after any change to
either side.
