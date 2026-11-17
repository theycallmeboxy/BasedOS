#!/bin/sh
# All four A72s saturated (sha256 loops) at each clock step, on battery: voltage, the firmware's
# own clock, battery power, throughput and the big-core temperature. Two rounds, the second in
# reverse order, so drift and heat land on both ends. Run on the device as root, in the menu:
#   clock-sweep.sh [seconds per step] [steps...]
# PyUI's CPU-mode command is moved aside meanwhile and spruce's Smart mode restored at the end.
SECS=${1:-20}
shift
STEPS=${*:-"1800000 2016000 2112000 2208000 2304000"}
B=/sys/class/power_supply/battery
P=/sys/devices/system/cpu/cpufreq/policy4
CMD=/mnt/SDCARD/App/PyUI/set-cpu-mode.sh
R=$(dirname "$(grep -l vdd_cpu_big_s0 /sys/class/regulator/regulator.*/name)")
[ "$(cat $B/status)" = Discharging ] || { echo "plugged in ($(cat $B/status))" >&2; exit 1; }
mount -t debugfs none /sys/kernel/debug 2>/dev/null

killall -q enforceSmartCPU.sh
[ -f "$CMD" ] && mv "$CMD" "$CMD.sweep-off"
cleanup() {
    kill $(jobs -p) 2>/dev/null
    rm -f /tmp/sweep-blob /tmp/sweep-cnt*
    [ -f "$CMD.sweep-off" ] && mv "$CMD.sweep-off" "$CMD"
    . /mnt/SDCARD/spruce/scripts/helperFunctions.sh >/dev/null 2>&1
    set_smart >/dev/null 2>&1
}
trap cleanup EXIT INT TERM
dd if=/dev/urandom of=/tmp/sweep-blob bs=1M count=16 2>/dev/null
for f in scaling_governor scaling_min_freq scaling_max_freq; do chmod a+w $P/$f; done
echo performance > $P/scaling_governor

pw() {
    i=$(cat $B/current_now) v=$(cat $B/voltage_now)
    [ "${i#-}" -gt 100000 ] && i=$((i / 1000))
    [ "$v" -gt 100000 ] && v=$((v / 1000))
    i=${i#-}
    echo $((i * v / 1000))
}

run() {
    F=$1
    echo "$F" > $P/scaling_max_freq; echo "$F" > $P/scaling_min_freq; echo "$F" > $P/scaling_max_freq
    rm -f /tmp/sweep-cnt*
    for c in 1 2 3 4; do (while :; do sha256sum /tmp/sweep-blob >/dev/null; echo >> /tmp/sweep-cnt$c; done) & done
    sleep 5
    c0=$(cat /tmp/sweep-cnt* | wc -l); t0=$(cut -d' ' -f1 /proc/uptime); s=0; n=0
    while [ $n -lt "$SECS" ]; do s=$((s + $(pw))); n=$((n + 1)); sleep 1; done
    c1=$(cat /tmp/sweep-cnt* | wc -l); t1=$(cut -d' ' -f1 /proc/uptime)
    temp=$(cat /sys/class/thermal/thermal_zone1/temp)
    kill $(jobs -p) 2>/dev/null; wait 2>/dev/null
    awk -v f="$F" -v uv="$(cat $R/microvolts)" -v fw="$(grep scmi_armclkb /sys/kernel/debug/clk/clk_summary | awk '{print $5}')" \
        -v mw=$((s / n)) -v c=$((c1 - c0)) -v a="$t0" -v b="$t1" -v t="$temp" \
        'BEGIN { r = c * 16 / (b - a); printf "%d,%.1f,%d,%d,%.1f,%.2f,%.1f\n", f / 1000, uv / 1000, fw / 1000000, mw, r, mw / r, t / 1000 }'
    sleep 8
}

echo "mhz,mv,firmware_mhz,mw,mib_s,mj_per_mib,big_c"
for F in $STEPS; do run "$F"; done
REV=""; for F in $STEPS; do REV="$F $REV"; done
for F in $REV; do run "$F"; done
echo "idle_mw,$(pw)"
