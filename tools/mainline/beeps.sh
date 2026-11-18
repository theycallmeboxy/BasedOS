#!/bin/sh
# Mainline experiment: stepped test beeps through the ES9018K2M, quiet first.
#   beeps.sh [<volume> ...]    "Digital Playback Volume" values (255 = 0 dB, 0.5 dB a step);
#                              default 150 180 210 (-52.5, -37.5, -22.5 dB)
# One 0.4 s 440 Hz beep at -12 dBFS per value, a second apart, straight to hw:0,0.
set -e
wav=/tmp/beep.wav
python3 - "$wav" <<'EOF'
import math, struct, sys, wave
rate, secs, amp = 48000, 0.4, 0.25
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    n = int(rate * secs)
    frames = bytearray()
    for i in range(n):
        env = min(1.0, i / 480, (n - i) / 480)  # 10 ms fades: no clicks
        v = int(32767 * amp * env * math.sin(2 * math.pi * 440 * i / rate))
        frames += struct.pack("<hh", v, v)
    w.writeframes(bytes(frames))
EOF
[ $# -gt 0 ] || set -- 150 180 210
n=1
for v in "$@"; do
	amixer -q -c 0 cset name='Digital Playback Volume' "$v,$v"
	echo "beep $n: volume $v"
	aplay -q -D hw:0,0 "$wav"
	n=$((n + 1))
	sleep 1
done
