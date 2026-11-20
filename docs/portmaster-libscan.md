# PortMaster ports: libraries loaded from the system (scan of 2026-11-19, generated)

1469 ports and 67 runtimes scanned (tools/pm-libscan.py).

## aarch64

1041 ports have aarch64 binaries that load system libraries; 371 of them need at least one BasedOS lacks, and for 356 of those stock (ROCKNIX) has every one.

Libraries BasedOS lacks, by how many ports (and runtimes) need them:

| Library | Ports | Stock | Examples |
|---|---|---|---|
| `libvorbisfile.so.3` | 173 | lib | A7Xpg, L'Abbaye des Morts, Abe's Amazing Adventure, Abombniball |
| `libSDL2_mixer-2.0.so.0` | 124 | lib | Abuse, Adonthell - Waste's Edge, Afternoon Stalker, Alchemy Quest |
| `libopenal.so.1` | 121 | lib | A7Xpg, Abe's Amazing Adventure, Abombniball, Absolute Reflex |
| `libpulse-simple.so.0` | 80 | lib | A7Xpg, L'Abbaye des Morts, Abe's Amazing Adventure, Abombniball |
| `libgobject-2.0.so.0` | 44 | lib | A7Xpg, Abe's Amazing Adventure, Abombniball, Aleph-One Marathon 1 |
| `libmpg123.so.0` | 44 | lib | Absolute Reflex, AREA2048, Arkovs Tower, BLUE REVOLVER |
| `libgmodule-2.0.so.0` | 37 | lib | A7Xpg, Abe's Amazing Adventure, Abombniball, Alien Blaster |
| `libtheoradec.so.1` | 32 | compat | Absolute Reflex, Arkovs Tower, BLUE REVOLVER, Brad Has A Pain |
| `libmodplug.so.1` | 31 | lib | Amoebax, AREA2048, Braid, Don Ceferino Hazaña |
| `libpixman-1.so.0` | 24 | lib | Brad Has A Pain, Crysalis, Disc Creatures, Doom Engines |
| `libcairo.so.2` | 22 | lib | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Bos Wars |
| `libgmp.so.10` | 22 | lib | Crysalis, Enigma, F1 Spirit, Finding Paradise |
| `libpulse.so.0` | 15 | lib | Anarch, Beat2x, ColorLines, Descent |
| `libSDL2_gfx-1.0.so.0` | 14 | lib | Afternoon Stalker, Blockdude Playdate, Burger Space, Cosmosmash |
| `libSDL2_net-2.0.so.0` | 14 | lib | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Blob Wars: Metal Blob Solid |
| `libFLAC.so.8` | 13 | compat | A7Xpg, Alien Blaster, Call to Power 2, Doom Engines |
| `libX11.so.6` | 11 | lib | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Doom Engines |
| `libavcodec.so.58` | 10 | compat | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Chicory: A Colorful Tale |
| `libavutil.so.56` | 10 | compat | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Chicory: A Colorful Tale |
| `libopusfile.so.0` | 9 | lib | AREA2048, Counter-Strike 1.6, Call to Power 2, DungeonRush |
| `libXext.so.6` | 8 | lib | Doom Engines, Moonlight Old, runtime mesa_pkg_0.1.squashfs, runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs |
| `libavformat.so.58` | 8 | compat | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Chicory: A Colorful Tale |
| `libswscale.so.5` | 8 | compat | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity, Chicory: A Colorful Tale |
| `libcrypto.so.1.1` | 7 | compat | Hurrican, Moonlight Old, runtime python_3.11.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs |
| `libssl.so.1.1` | 7 | no | Hurrican, Moonlight Old, runtime python_3.11.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs |
| `libXrender.so.1` | 6 | lib | Doom Engines, runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs, runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs, runtime zulu17.54.21-ca-jre17.0.13-linux.squashfs |
| `libgnutls.so.30` | 6 | lib | Enigma, F1 Spirit, Me and My Shadow, NetSurf Web Browser |
| `libreadline.so.8` | 6 | lib | Doom Engines, The Swapper, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs |
| `libxml2.so.2` | 6 | lib | Armagetron Advanced, Me and My Shadow, mReader, Morrowind |
| `libXi.so.6` | 5 | lib | runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs, runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs, runtime zulu17.54.21-ca-jre17.0.13-linux.squashfs, runtime zulu23.32.11-ca-jre23.0.2-linux.squashfs |
| `libXtst.so.6` | 5 | lib | runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs, runtime zulu17.48.15-ca-jdk17.0.10-linux.squashfs, runtime zulu17.54.21-ca-jre17.0.13-linux.squashfs, runtime zulu23.32.11-ca-jre23.0.2-linux.squashfs |
| `libcrypt.so.1` | 5 | no | runtime python_3.11.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs, runtime pyxel_2.4.6_python_3.11.squashfs |
| `libffi.so.7` | 5 | no | NetSurf Web Browser, runtime mesa_pkg_0.1.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs |
| `libnghttp2.so.14` | 5 | lib | Enigma, F1 Spirit, Me and My Shadow, Moonlight New |
| `libnsl.so.1` | 5 | lib | Enigma, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs, runtime pyxel_2.4.6_python_3.11.squashfs |
| `libpanelw.so.6` | 5 | lib | runtime python_3.11.squashfs, runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs, runtime pyxel_2.4.6_python_3.11.squashfs |
| `libswresample.so.3` | 5 | compat | Chicory: A Colorful Tale, Call to Power 2, Fares, Jimmy's Lost Fruits Journey |
| `libdb-5.3.so` | 4 | no | runtime pyxel_2.2.8_python_3.11.squashfs, runtime pyxel_2.3.18_python_3.11.squashfs, runtime pyxel_2.4.6_python_3.11.squashfs, runtime pyxel_2.9.5_python_3.11.squashfs |
| `libidn2.so.0` | 4 | lib | Enigma, Hurrican, Me and My Shadow, NetSurf Web Browser |
| `libGL.so.1` | 3 | lib | Half-Life, Quake 2, runtime renpy_8.1.3.squashfs |
| `libavahi-client.so.3` | 3 | lib | Moonlight Old, Moonlight New, runtime weston_pkg_0.2.squashfs |
| `libavahi-common.so.3` | 3 | lib | Moonlight Old, Moonlight New, runtime weston_pkg_0.2.squashfs |
| `libfribidi.so.0` | 3 | lib | Aleph-One Marathon 1, Aleph-One Marathon 2, Aleph-One Marathon Infinity |
| `libgssapi_krb5.so.2` | 3 | compat | Morrowind, runtime dotnet-3.1.32.squashfs, runtime qt6-eglfs-6.6.3.squashfs |
| `liblttng-ust.so.0` | 3 | no | Stardew Valley, runtime dotnet-3.1.32.squashfs, runtime dotnet-8.0.12.squashfs |
| `libxcb.so.1` | 3 | lib | Doom Engines, NetSurf Web Browser, runtime mesa_pkg_0.1.squashfs |
| `libGLX.so.0` | 2 | lib | Bugdom, Nanosaur |
| `libOpenGL.so.0` | 2 | lib | Bugdom, Nanosaur |
| `libSDL-1.2.so.0` | 2 | lib | Morrowind, Stunt Car Racer |
| `libgcrypt.so.20` | 2 | lib | Enigma, Morrowind |
| `libgio-2.0.so.0` | 2 | lib | Gmu Music Player, Tile World |
| `libreadline.so.7` | 2 | no | Wizznic, Yatka |
| `librga.so.2` | 2 | lib | Star Wars Jedi Knight - Jedi Academy, Star Wars Jedi Knight II - Jedi Outcast |
| `libsndio.so.7.0` | 2 | no | Minecraft - Java Edition, Revenge of the Titans |
| `libspeex.so.1` | 2 | lib | Gmu Music Player, Morrowind |
| `libthread_db.so.1` | 2 | lib | runtime zulu11.48.21-ca-jdk11.0.11-linux.squashfs, runtime zulu8.86.0.25-ca-jdk8.0.452-linux.squashfs |
| `libxcb-shm.so.0` | 2 | lib | Doom Engines, runtime mesa_pkg_0.1.squashfs |
| `libOpenThreadsrd.so.21` | 1 | no | Morrowind |
| `libSDL2.so` | 1 | lib | Biolab Disaster |
| `libWildMidi.so.2` | 1 | lib | F2bgl |
| `libX11-xcb.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libXau.so.6` | 1 | lib | Ken's Labyrinth |
| `libXdmcp.so.6` | 1 | lib | Ken's Labyrinth |
| `libXfixes.so.3` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libXxf86vm.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libass.so.9` | 1 | lib | YTC |
| `libbluray.so.2` | 1 | compat | Morrowind |
| `libboost_system.so.1.67.0` | 1 | no | Wargus |
| `libbsd.so.0` | 1 | no | runtime mesa_pkg_0.1.squashfs |
| `libchromaprint.so.1` | 1 | compat | Morrowind |
| `libgdbm.so.6` | 1 | no | runtime pyxel_2.9.5_python_3.11.squashfs |
| `libgme.so.0` | 1 | compat | Morrowind |
| `libgo2.so` | 1 | no | Moonlight Old |
| `libgpg-error.so.0` | 1 | lib | Ken's Labyrinth |
| `libgsm.so.1` | 1 | compat | Morrowind |
| `libicudata.so.63` | 1 | no | VCMI - Heroes of Might and Magic III |
| `libicudata.so.66` | 1 | no | LieroLibre |
| `libjack.so.0` | 1 | no | Doom Engines |
| `libnsl.so.2` | 1 | no | runtime python_3.11.squashfs |
| `libnuma.so.1` | 1 | compat | Morrowind |
| `libopenjp2.so.7` | 1 | compat | Morrowind |
| `libopenmpt.so.0` | 1 | compat | Morrowind |
| `libphysfs.so.1` | 1 | no | runtime solarus-1.6.5.squashfs |
| `librga.so` | 1 | lib | Moonlight Old |
| `librsvg-2.so.2` | 1 | compat | Morrowind |
| `libshine.so.3` | 1 | compat | Morrowind |
| `libsnappy.so.1` | 1 | compat | Morrowind |
| `libsoxr.so.0` | 1 | compat | Morrowind |
| `libtcl8.6.so` | 1 | no | runtime pyxel_2.9.5_python_3.11.squashfs |
| `libtirpc.so.3` | 1 | no | runtime python_3.11.squashfs |
| `libtk8.6.so` | 1 | no | runtime pyxel_2.9.5_python_3.11.squashfs |
| `libtwolame.so.0` | 1 | compat | Morrowind |
| `libva-drm.so.2` | 1 | compat | Morrowind |
| `libva-x11.so.2` | 1 | compat | Morrowind |
| `libva.so.2` | 1 | compat | Morrowind |
| `libvdpau.so.1` | 1 | lib | Morrowind |
| `libwayland-cursor.so.0` | 1 | lib | runtime qt6-eglfs-6.6.3.squashfs |
| `libwebpdemux.so.2` | 1 | no | Blupimania |
| `libwebpmux.so.3` | 1 | compat | Morrowind |
| `libxcb-dri2.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-dri3.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-glx.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-present.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-randr.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-render.so.0` | 1 | lib | Doom Engines |
| `libxcb-sync.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxcb-xfixes.so.0` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxshmfence.so.1` | 1 | lib | runtime mesa_pkg_0.1.squashfs |
| `libxvidcore.so.4` | 1 | compat | Morrowind |
| `libzip.so.4` | 1 | no | mReader |
| `libzvbi.so.0` | 1 | compat | Morrowind |

## armhf

251 ports have armhf binaries that load system libraries; 18 of them need at least one BasedOS lacks, and for 3 of those stock (ROCKNIX) has every one.

Libraries BasedOS lacks, by how many ports (and runtimes) need them:

| Library | Ports | Stock | Examples |
|---|---|---|---|
| `libcrypto.so.1.1` | 7 | no | Climb, Super Hydorah, Mable and the Wood, Relic Hunters |
| `libdbus-1.so.3` | 6 | lib32 | Braid, Hexen 2, MineSector, Quakespasm |
| `libgpg-error.so.0` | 3 | no | Hexen 2, Ken's Labyrinth, Quakespasm |
| `libgmodule-2.0.so.0` | 2 | lib32 | MineSector, SkiFree |
| `libmp3lame.so.0` | 2 | no | MineSector, SkiFree |
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
| `libgobject-2.0.so.0` | 1 | lib32 | runtime weston_pkg_0.2.squashfs |
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
| `unzip` | 44 | Ambidextro, Arengius, Augustus, Bushido Panda, Canabalt-hf |
| `mono` | 30 | Anodyne, Axiom Verge, Bleed, Bleed 2, Blossom Tales II |
| `python3` | 19 | Antecrypt, Damocles Gaze, Disc Creatures, EAT GIRL, Fire & Brimstone |
| `java` | 9 | Gunslugs 2, Gunslugs 3 Rogue Tactics, Lost Flame, Mindustry, Pixel Wheels |
| `wget` | 2 | Canabalt-hf, Crysalis |
| `dotnet` | 2 | Jetboard Joust, Mute Crimson DX |
| `gl4es` | 1 | Jetboard Joust |
| `mpv` | 1 | mReader |
| `curl` | 1 | Morrowind |
| `python` | 1 | Push! |
| `box64` | 1 | Super Hexagon |

Scripts that use `clibs`: 0 ()
