#!/bin/sh
# Measure battery draw for a few CPU configurations, screen on, nothing else running.
# Run on the device on battery (unplugged), with the frontend stopped (maintenance mode):
#   power-probe.sh [seconds per config]
# Prints average current (mA) and power (mW) per configuration.
SECS=${1:-20}
B=/sys/class/power_supply/battery
C=/sys/devices/system/cpu
[ "$(cat $B/status)" = Discharging ] || { echo "plugged in ($(cat $B/status)): readings would include charging" >&2; exit 1; }

sample() {
	n=0 sum_i=0 sum_p=0
	end=$(( $(cut -d. -f1 /proc/uptime) + SECS ))
	while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
		i=$(cat $B/current_now) v=$(cat $B/voltage_now)
		# current_now in uA or mA, voltage_now in uV or mV, depending on the driver: normalise.
		[ "${i#-}" -gt 100000 ] && i=$((i / 1000))
		[ "$v" -gt 100000 ] && v=$((v / 1000))
		i=${i#-}
		sum_i=$((sum_i + i)); sum_p=$((sum_p + i * v / 1000)); n=$((n + 1))
		sleep 1
	done
	echo "$1: $((sum_i / n)) mA, $((sum_p / n)) mW (n=$n)"
}

online() { for c in 4 5 6 7; do echo "$1" > $C/cpu$c/online; done; }
gov() { for p in $C/cpufreq/policy*; do echo "$1" > $p/scaling_governor 2>/dev/null; done; }

orig_gov=$(cat $C/cpufreq/policy0/scaling_governor)
online 1; gov schedutil; sleep 3; sample "all 8 cores, schedutil"
online 1; gov powersave; sleep 3; sample "all 8 cores, powersave (lowest OPP)"
online 0; gov schedutil; sleep 3; sample "A53 only (cpus 4-7 offline), schedutil"
online 0; gov powersave; sleep 3; sample "A53 only, powersave"
online 1; gov "$orig_gov"
echo "restored: all cores online, governor $orig_gov"
