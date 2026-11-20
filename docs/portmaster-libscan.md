# PortMaster ports: libraries loaded from the system (scan of 2026-11-19, generated)

1511 ports and 67 runtimes scanned (tools/pm-libscan.py). 64-bit libraries count as there when BasedOS or the frontend's own folders (154 files) have them.

## aarch64

1075 ports have aarch64 binaries that load system libraries; 41 of them need at least one BasedOS lacks, and for 29 of those stock (ROCKNIX) has every one.

Libraries BasedOS lacks, by how many ports (and runtimes) need them:

| Library | Ports | Stock | Examples |
|---|---|---|---|
| `libFLAC.so.8` | 13 | compat | A7Xpg, Alien Blaster, Call to Power 2, Doom Engines |
| `libcrypto.so.1.1` | 7 | compat | Hurrican, Moonlight Old, runtime python_3.11.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs |
| `libxml2.so.2` | 7 | lib | Armagetron Advanced, Me and My Shadow, mReader, Morrowind |
| `libreadline.so.8` | 6 | lib | Doom Engines, The Swapper, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs |
| `libXtst.so.6` | 5 | lib | runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs, runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs, runtime zulu17.54.21-ca-jre17.0.13-linux.squashfs, runtime zulu23.32.11-ca-jre23.0.2-linux.squashfs |
| `libpanelw.so.6` | 5 | lib | runtime python_3.11.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs, runtime pyxel_2.4.6_python_3.11.squashfs |
| `libGL.so.1` | 4 | lib | Half-Life, Quake 2, SuperTux, runtime renpy_8.1.3.squashfs |
| `libdb-5.3.so` | 4 | no | runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs, runtime pyxel_2.4.6_python_3.11.squashfs, runtime pyxel_2.9.5_python_3.11.squashfs |
| `libavahi-client.so.3` | 3 | lib | Moonlight Old, Moonlight New, runtime weston_pkg_0.2.squashfs |
| `libavahi-common.so.3` | 3 | lib | Moonlight Old, Moonlight New, runtime weston_pkg_0.2.squashfs |
| `liblttng-ust.so.0` | 3 | no | Stardew Valley, runtime dotnet-3.1.32.squashfs, runtime dotnet-8.0.12.squashfs |
| `libGLX.so.0` | 2 | lib | Bugdom, Nanosaur |
| `libOpenGL.so.0` | 2 | lib | Bugdom, Nanosaur |
| `libSDL-1.2.so.0` | 2 | lib | Morrowind, Stunt Car Racer |
| `libreadline.so.7` | 2 | no | Wizznic, Yatka |
| `librga.so.2` | 2 | lib | Star Wars Jedi Knight - Jedi Academy, Star Wars Jedi Knight II - Jedi Outcast |
| `libsndio.so.7.0` | 2 | no | Minecraft - Java Edition, Revenge of the Titans |
| `libthread_db.so.1` | 2 | lib | runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs, runtime zulu8.86.0.25-ca-jdk8.0.452-linux.squashfs |
| `libOpenThreadsrd.so.21` | 1 | no | Morrowind |
| `libSDL2.so` | 1 | lib | Biolab Disaster |
| `libWildMidi.so.2` | 1 | lib | F2bgl |
| `libX11-xcb.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libXxf86vm.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libass.so.9` | 1 | lib | YTC |
| `libbluray.so.2` | 1 | compat | Morrowind |
| `libboost_system.so.1.67.0` | 1 | no | Wargus |
| `libchromaprint.so.1` | 1 | compat | Morrowind |
| `libgdbm.so.6` | 1 | no | runtime pyxel_2.9.5_python_3.11.squashfs |
| `libgo2.so` | 1 | no | Moonlight Old |
| `libgsm.so.1` | 1 | compat | Morrowind |
| `libicudata.so.66` | 1 | no | LieroLibre |
| `libjack.so.0` | 1 | no | Doom Engines |
| `libnsl.so.2` | 1 | no | runtime python_3.11.squashfs |
| `libnuma.so.1` | 1 | compat | Morrowind |
| `libopenjp2.so.7` | 1 | compat | Morrowind |
| `libphysfs.so.1` | 1 | no | runtime solarus-1.6.5.squashfs |
| `librga.so` | 1 | lib | Moonlight Old |
| `librsvg-2.so.2` | 1 | compat | Morrowind |
| `libshine.so.3` | 1 | compat | Morrowind |
| `libsnappy.so.1` | 1 | compat | Morrowind |
| `libsoxr.so.0` | 1 | compat | Morrowind |
| `libtirpc.so.3` | 1 | no | runtime python_3.11.squashfs |
| `libtwolame.so.0` | 1 | compat | Morrowind |
| `libva-drm.so.2` | 1 | compat | Morrowind |
| `libva-x11.so.2` | 1 | compat | Morrowind |
| `libva.so.2` | 1 | compat | Morrowind |
| `libvdpau.so.1` | 1 | lib | Morrowind |
| `libwebpdemux.so.2` | 1 | no | Blupimania |
| `libwebpmux.so.3` | 1 | compat | Morrowind |
| `libxcb-dri2.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-dri3.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-glx.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-present.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-randr.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-sync.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-xfixes.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxshmfence.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxvidcore.so.4` | 1 | compat | Morrowind |
| `libzip.so.4` | 1 | no | mReader |
| `libzvbi.so.0` | 1 | compat | Morrowind |

## armhf

252 ports have armhf binaries that load system libraries; 14 of them need at least one BasedOS lacks, and for 2 of those stock (ROCKNIX) has every one.

Libraries BasedOS lacks, by how many ports (and runtimes) need them:

| Library | Ports | Stock | Examples |
|---|---|---|---|
| `libcrypto.so.1.1` | 7 | no | Climb, Super Hydorah, Mable and the Wood, Relic Hunters |
| `libGL.so.1` | 1 | lib32 | Half-Life |
| `libHalf.so.24` | 1 | no | Waking Mars |
| `libIex-2_3.so.24` | 1 | no | Waking Mars |
| `libIlmImf-2_3.so.24` | 1 | no | Waking Mars |
| `libSDL_image-1.2.so.0` | 1 | no | Rlvm (deprecated) |
| `libSDL_mixer-1.2.so.0` | 1 | no | Rlvm (deprecated) |
| `libX11.so.6` | 1 | lib32 | runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs |
| `libXau.so.6` | 1 | lib32 | Ken's Labyrinth |
| `libXdmcp.so.6` | 1 | lib32 | Ken's Labyrinth |
| `libXext.so.6` | 1 | lib32 | runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs |
| `libXi.so.6` | 1 | lib32 | runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs |
| `libXrender.so.1` | 1 | lib32 | runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs |
| `libXtst.so.6` | 1 | lib32 | runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs |
| `libbsd.so.0` | 1 | no | SkiFree |
| `libgmp.so.10` | 1 | lib32 | runtime weston_pkg_0.2.squashfs |
| `libjxrglue.so.0` | 1 | no | Waking Mars |
| `libmd.so.0` | 1 | no | MineSector |
| `libnsl.so.1` | 1 | lib32 | Ken's Labyrinth |
| `libopenjp2.so.7` | 1 | no | Waking Mars |
| `libraw.so.19` | 1 | no | Waking Mars |
| `libssl.so.1.1` | 1 | no | Ubermosh Collection |
| `libtiff.so.5` | 1 | no | Waking Mars |
| `libwacom.so.2` | 1 | no | runtime weston_pkg_0.2.squashfs |
| `libwebp.so.6` | 1 | no | Waking Mars |
| `libwebpmux.so.3` | 1 | no | Waking Mars |

## System tools named in launch scripts

| Tool | Ports | Examples |
|---|---|---|
| `zip` | 246 | Adventure Rush, Aestheta, AlllCALL, Alruna and the Necro-Industrialists, Always Surrender |
| `unzip` | 45 | Ambidextro, Arengius, Augustus, Bushido Panda, Canabalt-hf |
| `mono` | 30 | Anodyne, Axiom Verge, Bleed, Bleed 2, Blossom Tales II |
| `python3` | 19 | Antecrypt, Damocles Gaze, Disc Creatures, EAT GIRL, Fire & Brimstone |
| `java` | 10 | FreeCol, Gunslugs 2, Gunslugs 3 Rogue Tactics, Lost Flame, Mindustry |
| `wget` | 2 | Canabalt-hf, Crysalis |
| `dotnet` | 2 | Jetboard Joust, Mute Crimson DX |
| `gl4es` | 1 | Jetboard Joust |
| `mpv` | 1 | mReader |
| `curl` | 1 | Morrowind |
| `python` | 1 | Push! |
| `box64` | 1 | Super Hexagon |

Scripts that use `clibs`: 0 ()
