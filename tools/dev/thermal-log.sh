#!/bin/sh
# Log a sustained load once a second: the A72 clock, the thermal throttling state, temperatures,
# battery draw and the CPU time of a process. Run on the device, as root:
#   thermal-log.sh <seconds> <out.csv> [process name]
# Then prints per-minute averages. The CPU columns: proc_cpu is the process's CPU time in percent
# of one core (100 = one core busy). Cooling states are the kernel's throttle steps (0 = none).
SECS=${1:-600}
OUT=${2:-/tmp/thermal.csv}
NAME=${3:-ra64.universal}
B=/sys/class/power_supply/battery
T=/sys/class/thermal
P4=/sys/devices/system/cpu/cpufreq/policy4
HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)

ticks() { [ -n "$1" ] && awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null || echo 0; }

echo "t,a72_mhz,a72_max_mhz,cool_cpu4,cool_gpu,cool_dmc,soc_c,big_c,little_c,gpu_c,mw,proc_cpu" > "$OUT"
pid=$(pidof "$NAME" | cut -d' ' -f1)
prev=$(ticks "$pid")
t=0
while [ $t -lt "$SECS" ]; do
    sleep 1
    t=$((t + 1))
    i=$(cat $B/current_now) v=$(cat $B/voltage_now)
    [ "${i#-}" -gt 100000 ] && i=$((i / 1000))
    [ "$v" -gt 100000 ] && v=$((v / 1000))
    i=${i#-}
    now=$(ticks "$pid")
    cpu=$(( (now - prev) * 100 / HZ ))
    prev=$now
    echo "$t,$(( $(cat $P4/scaling_cur_freq) / 1000 )),$(( $(cat $P4/scaling_max_freq) / 1000 )),$(cat $T/cooling_device1/cur_state),$(cat $T/cooling_device2/cur_state),$(cat $T/cooling_device3/cur_state),$(( $(cat $T/thermal_zone0/temp) / 1000 )),$(( $(cat $T/thermal_zone1/temp) / 1000 )),$(( $(cat $T/thermal_zone2/temp) / 1000 )),$(( $(cat $T/thermal_zone5/temp) / 1000 )),$((i * v / 1000)),$cpu" >> "$OUT"
done

echo "min  a72_mhz  cool_cpu4(max)  big_c  little_c(max)  gpu_c  mW   ${NAME}_cpu%"
awk -F, 'NR > 1 {
    m = int(($1 - 1) / 60); n[m]++; f[m] += $2; if ($4 > cm[m]) cm[m] = $4; b[m] += $8; l[m] += $9
    if ($9 > lm[m]) lm[m] = $9; g[m] += $10; w[m] += $11; c[m] += $12
} END {
    for (k = 0; k in n; k++)
        printf "%3d  %7d  %14d  %5.1f  %4.1f (%3d)  %5.1f  %4d  %5d\n", k + 1, f[k] / n[k], cm[k], b[k] / n[k], l[k] / n[k], lm[k], g[k] / n[k], w[k] / n[k], c[k] / n[k]
}' "$OUT"
