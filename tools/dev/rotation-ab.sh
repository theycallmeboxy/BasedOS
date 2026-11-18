#!/bin/sh
# The same game on each SDL rotation path (BasedOS's SDL, patch 0005), with SDL's rotation timer
# on: the rotation's time per frame and the game's frame pacing, every 300 frames. Run on the
# device as root (or spruce) with spruce up, from SSH:
#   rotation-ab.sh <Emu dir> <rom> <seconds> <process name> [rga gpu ...]
# e.g.  rotation-ab.sh N64 "/mnt/SDCARD/Roms/N64/Perfect Dark.z64" 90 mupen64plus
# The game is launched the way spruce launches it (standard_launch.sh through
# /tmp/cmd_to_run.sh and a MainUI restart), left alone for <seconds>, then its process is ended
# and spruce brings the menu back. The backlight is put back after each launch, since killing
# MainUI can leave PyUI's screensaver dim level in place. Results: /tmp/rotation-ab.log.
SYS=$1 ROM=$2 SECS=$3 PROC=$4
[ -n "$PROC" ] || { sed -n '2,12p' "$0"; exit 2; }
shift 4
PATHS=${*:-rga gpu}
L=/mnt/SDCARD/Emu/$SYS/../../spruce/scripts/emu/standard_launch.sh
[ -f "$ROM" ] || { echo "no $ROM"; exit 1; }
[ -x "$L" ] || [ -f "$L" ] || { echo "no $L"; exit 1; }
BL=$(ls -d /sys/class/backlight/* | head -1)
OUT=/tmp/rotation-ab.log
echo "== $(date) $SYS $ROM, ${SECS}s each, kernel $(uname -r)" >> "$OUT"

for p in $PATHS; do
	level=$(cat "$BL/brightness")
	rm -f "/tmp/rot-$p.log"
	cat > /tmp/cmd_to_run.sh <<EOF
export SDL_KMSDRM_ROTATION=$p SDL_KMSDRM_ROTATION_STATS=1 SDL_KMSDRM_ROTATION_LOG=/tmp/rot-$p.log
chmod a+x "$L"; "$L" "$ROM"
EOF
	killall MainUI 2>/dev/null
	sleep 6
	echo "$level" > "$BL/brightness"
	sleep "$SECS"
	pid=$(pidof "$PROC" | cut -d' ' -f1)
	[ -n "$pid" ] && kill "$pid"
	sleep 8
	[ -n "$(pidof "$PROC")" ] && kill -9 $(pidof "$PROC")
	sleep 6
	{
		echo "-- $p"
		cat "/tmp/rot-$p.log" 2>/dev/null || echo "(no timer output: is the game using BasedOS's SDL on KMSDRM?)"
	} >> "$OUT"
done
sed -n "/^== /h; /^== /!H; \${x; p}" "$OUT"
