#!/bin/sh
# Start spruce's RetroArch on the GKD the way spruce does (its HOME, its platform config), with a
# core that boots without content, for display/input/audio checks. Run on the device:
#   ra-test.sh <core name, e.g. dosbox_pure> [seconds]
# Needs the display free (no PyUI): stop it first. Logs to /tmp/ra-test.log.
CORE=${1:?core}
SECS=${2:-20}
R=/mnt/SDCARD/RetroArch
for p in $(pidof MainUI) $(pidof ra64.universal); do kill "$p"; done
sleep 1
cd "$R" || exit 1
export HOME="$R"
export LD_LIBRARY_PATH="/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"
export SDL_VIDEODRIVER=kmsdrm SDL_JOYSTICK_DISABLE_UDEV=1
"$R/ra64.universal" -v --config /mnt/SDCARD/Saves/ra-configs/retroarch-GKD350HUltra.cfg \
	-L "$R/.retroarch/cores64/${CORE}_libretro.so" > /tmp/ra-test.log 2>&1 &
echo "started pid $! (log /tmp/ra-test.log, stopping in ${SECS}s)"
( sleep "$SECS"; kill $(pidof ra64.universal) 2>/dev/null ) >/dev/null 2>&1 &
