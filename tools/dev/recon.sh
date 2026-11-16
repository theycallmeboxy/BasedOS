#!/bin/sh
# Phase 0 recon for the GKD 350H Ultra on stock (GKD's ROCKNIX fork).
# READ-ONLY: prints everything to stdout and writes nothing on the device.
# Run on the device:  sh recon.sh > recon.txt   (or pipe it in over ssh)

. /etc/profile >/dev/null 2>&1

sec() { printf '\n===== %s =====\n' "$*"; }
run() { printf '\n$ %s\n' "$*"; sh -c "$*" 2>&1; }
have() { command -v "$1" >/dev/null 2>&1; }
to() { if have timeout; then timeout "$@"; else shift; "$@"; fi; }

sec "identity"
run 'cat /etc/os-release'
run 'uname -a'
run 'cat /proc/cmdline'
run 'hostname'
run 'cat /proc/device-tree/model; echo'
run "tr '\\0' '\\n' < /proc/device-tree/compatible"
run 'cat /proc/cpuinfo'
run 'free -m'
run 'ldd --version | head -1'
run 'ls -la /usr/lib/libc.so* /lib/libc.so* /usr/lib/ld-linux-aarch64.so* /lib/ld-linux-aarch64.so* 2>/dev/null'

sec "storage"
run 'mount'
run 'cat /proc/mounts'
run 'lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null || lsblk'
run 'cat /proc/partitions'
run 'ls -la /dev/mmcblk* /dev/block/by-name 2>/dev/null'
run 'for d in /sys/block/mmcblk*; do echo "$d: type=$(cat $d/device/type 2>/dev/null) name=$(cat $d/device/name 2>/dev/null) size_sectors=$(cat $d/size)"; done'
run 'df -h'
run 'ls -la /mnt /mnt/* 2>&1 | head -40'
run 'stat -c "%n %F %a %U" / /mnt /storage /storage/games-external /storage/roms 2>&1'
run 'awk '"'"'$2=="/" || $2=="/mnt" || $2 ~ /^\/storage/ {print}'"'"' /proc/mounts'
run '[ -w /mnt ] && echo "/mnt: write permission bit set (rootfs may still be ro)" || echo "/mnt: not writable"'
run 'ls -la /storage /storage/.config /storage/.config/system.d 2>&1'
run 'find /storage/.config/system.d -type f -exec sh -c '"'"'echo "--- $1"; cat "$1"'"'"' _ {} \; 2>&1'
run 'ls -la /storage/games-external | head -40'
run 'ls -la /usr/config/system-dirs.conf; wc -l /usr/config/system-dirs.conf'

sec "systemd"
run 'systemctl --version | head -1'
run 'systemctl cat essway.service'
run 'systemctl cat input.service'
run 'systemctl cat sway.service'
run 'systemctl cat rocknix-automount.service'
run 'systemctl status essway.service --no-pager -l | head -30'
run 'systemctl list-units --all --no-pager'
run 'systemctl list-unit-files --no-pager'
run 'cat /usr/bin/start_es.sh'
run 'cat /etc/systemd/logind.conf; ls /etc/systemd/logind.conf.d /storage/.config/logind.conf.d 2>&1'
run 'systemd-inhibit --list --no-pager'

sec "sway / display"
run 'env | grep -E "WAYLAND|XDG|SWAY|SDL|DISPLAY|HW_|DEVICE|QUIRK|MALI|EGL" | sort'
run 'ls -la $XDG_RUNTIME_DIR 2>&1'
run 'ls /storage/.config/sway /usr/config/sway /etc/sway 2>&1'
run 'for f in /storage/.config/sway/config /usr/config/sway/config /etc/sway/config; do [ -f $f ] && { echo "--- $f"; cat $f; }; done'
run 'sway --version'
run 'swaymsg -t get_outputs'
run 'swaymsg -t get_inputs'
run 'swaymsg -t get_tree | head -80'
run 'ls /sys/class/drm; cat /sys/class/drm/*/modes 2>/dev/null'

sec "input"
run 'cat /proc/bus/input/devices'
run 'ls -la /dev/input /dev/input/by-path /dev/input/by-id 2>&1'
if have evtest; then
	for e in /dev/input/event*; do
		printf '\n$ evtest %s (capabilities only, 1 s)\n' "$e"
		to 1 evtest "$e" 2>&1 | sed '/^Testing/q'
	done
else
	echo "evtest: not installed"
fi
run 'ls /usr/share/libretro/autoconfig /usr/config/retroarch/autoconfig 2>/dev/null | head; find / -xdev -path "*autoconfig*" -iname "*gkd*" 2>/dev/null | head'
run 'cat /proc/sys/kernel/sysrq; ls /sys/class/leds; for l in /sys/class/leds/*; do echo "$l max=$(cat $l/max_brightness) cur=$(cat $l/brightness) trig=$(cat $l/trigger | tr " " "\n" | grep "\[")"; done'
run 'ls /sys/class/input; ls /sys/bus/platform/drivers | grep -iE "gpio|key|joy|adc|rumble|pwm|vib"'
run 'find /sys/class -maxdepth 2 -iname "*vib*" -o -maxdepth 2 -iname "*rumble*" 2>/dev/null'

sec "backlight / power"
run 'for b in /sys/class/backlight/*; do echo "$b: max=$(cat $b/max_brightness) cur=$(cat $b/brightness) actual=$(cat $b/actual_brightness) bl_power=$(cat $b/bl_power 2>/dev/null)"; done'
run 'for p in /sys/class/power_supply/*; do echo "--- $p"; cat $p/uevent; done'
run 'cat /sys/power/state /sys/power/mem_sleep 2>&1'

sec "cpu / gpu frequency"
run 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "--- $p cpus=$(cat $p/related_cpus) gov=$(cat $p/scaling_governor) min=$(cat $p/scaling_min_freq) max=$(cat $p/scaling_max_freq) cur=$(cat $p/scaling_cur_freq)"; echo "freqs: $(cat $p/scaling_available_frequencies)"; echo "govs: $(cat $p/scaling_available_governors)"; done'
run 'for d in /sys/class/devfreq/*; do echo "--- $d name=$(cat $d/name 2>/dev/null) gov=$(cat $d/governor) min=$(cat $d/min_freq) max=$(cat $d/max_freq) cur=$(cat $d/cur_freq)"; echo "freqs: $(cat $d/available_frequencies)"; echo "govs: $(cat $d/available_governors)"; done'
run 'ls /sys/class/thermal; for t in /sys/class/thermal/thermal_zone*; do echo "$t $(cat $t/type) $(cat $t/temp)"; done'
run 'ls /usr/bin | grep -iE "cpu|gpu|perf|governor|fan|tdp"'

sec "audio"
run 'aplay -l'
run 'aplay -L | head -40'
run 'cat /proc/asound/cards'
run 'amixer scontrols'
run 'amixer contents | head -150'
run 'pactl info'
run 'pactl list short sinks; pactl list short sources'
run 'wpctl status 2>&1 | head -60'
run 'ps -o pid,args 2>/dev/null | grep -iE "pipewire|pulse|wireplumber" | grep -v grep || ps | grep -iE "pipewire|pulse|wireplumber" | grep -v grep'

sec "runtime / libraries"
run 'python3 --version'
run 'python3 -c "import sys; print(sys.path)"'
run 'python3 -c "import sdl2; print(sdl2.__file__, sdl2.dll.version)" 2>&1'
run 'python3 -c "import PIL; print(\"PIL\", PIL.__version__)" 2>&1'
run 'python3 -c "import pygame; print(\"pygame\", pygame.version.ver)" 2>&1'
run 'ls -la /usr/lib/libSDL2* /usr/lib/libSDL2_* /usr/lib/libEGL* /usr/lib/libGLESv2* /usr/lib/libmali* /usr/lib/libwayland* 2>/dev/null'
run 'sdl2-config --version 2>/dev/null; strings /usr/lib/libSDL2-2.0.so.0 2>/dev/null | grep -m1 -E "^2\.[0-9]+\.[0-9]+"'
run 'ls /usr/bin | grep -iE "retroarch|ppsspp|flycast|drastic|mupen|dolphin|melon|duckstation|pcsx|yabasan|portmaster|evtest|rsync|busybox|7z|unzip|curl|wget|socat|jq|fbset|python"'
run 'ls /usr/lib/libretro 2>/dev/null | head -100; ls /tmp/cores 2>/dev/null | head'
run 'which retroarch && retroarch --version 2>&1 | head -3'
run 'busybox 2>&1 | head -1'

sec "network"
run 'ip -br addr'
run 'connmanctl state'
run 'connmanctl technologies'
run 'connmanctl services'
run 'ls /storage/.cache/connman 2>&1 | head'
run 'systemctl is-active connman iwd sshd smbd nmbd syncthing avahi-daemon 2>&1'
run 'cat /storage/.config/system/configs/system.cfg 2>/dev/null | grep -viE "pass|psk|key|token|user" | head -100'

sec "processes"
run 'ps -o pid,ppid,args 2>/dev/null || ps'

sec "recent journal (essway, sway)"
run 'journalctl -b -u essway -u sway --no-pager | tail -60'
echo
echo "===== end of recon ====="
