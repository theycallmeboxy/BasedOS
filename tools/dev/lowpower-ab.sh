#!/bin/sh
# A/B the low-power presets on the A53s against the same presets on the A72s, under whatever is
# running (the menu, a game). Run on the device, on battery, as root:
#   lowpower-ab.sh <smart|powersave|both> [seconds per run] [rounds] [dslog]
# Each round runs every configuration once, in alternating order, so battery drift and warm-up
# land on both sides. Per run: average battery power, the clock of the running cluster, and the
# DSperate fps when a DS_FPS log is given (verbose logging on). PyUI's CPU-mode command is moved
# aside meanwhile, so the screensaver can't switch modes mid-run, and put back at the end.
SET=${1:-both}
SECS=${2:-25}
ROUNDS=${3:-2}
DSLOG=$4
B=/sys/class/power_supply/battery
C=/sys/devices/system/cpu
CMD=/mnt/SDCARD/App/PyUI/set-cpu-mode.sh
[ "$(cat $B/status)" = Discharging ] || { echo "plugged in ($(cat $B/status))" >&2; exit 1; }

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh >/dev/null 2>&1
[ -f "$CMD" ] && mv "$CMD" "$CMD.ab-off"
trap '[ -f "$CMD.ab-off" ] && mv "$CMD.ab-off" "$CMD"; set_smart >/dev/null 2>&1' EXIT INT TERM
killall -q enforceSmartCPU.sh

# name cores governor min max dmc
apply() {
    cores_online "$2" >/dev/null 2>&1
    case "$2" in 0123) P=$C/cpufreq/policy0 ;; *) P=$C/cpufreq/policy4 ;; esac
    for f in scaling_governor scaling_min_freq scaling_max_freq; do chmod a+w "$P/$f" 2>/dev/null; done
    echo "$3" > "$P/scaling_governor"
    echo "$4" > "$P/scaling_min_freq"; echo "$5" > "$P/scaling_max_freq"; echo "$4" > "$P/scaling_min_freq"
    echo "$6" > /sys/class/devfreq/dmc/governor
    POL=$P
}

run() {
    apply "$@"
    sleep 5
    n=0 sp=0 sf=0
    fps0=$( [ -n "$DSLOG" ] && wc -l < "$DSLOG" )
    end=$(( $(cut -d. -f1 /proc/uptime) + SECS ))
    while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
        i=$(cat $B/current_now) v=$(cat $B/voltage_now)
        [ "${i#-}" -gt 100000 ] && i=$((i / 1000))
        [ "$v" -gt 100000 ] && v=$((v / 1000))
        i=${i#-}
        sp=$((sp + i * v / 1000)); sf=$((sf + $(cat $POL/scaling_cur_freq) / 1000)); n=$((n + 1))
        sleep 1
    done
    fps=""
    if [ -n "$DSLOG" ]; then
        fps=$(tail -n +$((fps0 + 1)) "$DSLOG" | grep "fps (" | awk '{s += $1; k++} END {if (k) printf "%.1f fps", s / k}')
    fi
    printf "%-22s %5d mW  avg %4d MHz  %s\n" "$1" $((sp / n)) $((sf / n)) "$fps"
}

smart_a53()  { run "Smart A53 ondemand"  0123 ondemand     408000  1800000 dmc_ondemand; }
smart_a72()  { run "Smart A72 ondemand"  4567 ondemand     408000  1800000 dmc_ondemand; }
smart_sps()  { run "Smart A72 like TSPS" 4567 conservative 1008000 2016000 dmc_ondemand; }
ps_a53()     { run "Powersave A53"       0123 conservative 408000  1416000 powersave; }
ps_a72()     { run "Powersave A72"       4567 conservative 408000  1416000 powersave; }

echo "backlight $(cat /sys/class/backlight/*/brightness), battery $(cat $B/capacity)%, ${SECS}s per run"
r=1
while [ $r -le "$ROUNDS" ]; do
    case "$SET" in
        smart|both) if [ $((r % 2)) = 1 ]; then smart_a53; smart_a72; smart_sps; else smart_sps; smart_a72; smart_a53; fi ;;
    esac
    case "$SET" in
        powersave|both) if [ $((r % 2)) = 1 ]; then ps_a53; ps_a72; else ps_a72; ps_a53; fi ;;
    esac
    r=$((r + 1))
done
