#!/usr/bin/env python3
"""One busy thread pinned to an A53 (cpu0) and then to an A72 (cpu4): battery power, clock and
work rate for each, and energy per unit of work. Run on the device, on battery, frontend stopped:
    python3 cluster-probe.py [seconds]
"""
import multiprocessing as mp
import os
import sys
import time

B = "/sys/class/power_supply/battery"
SECS = int(sys.argv[1]) if len(sys.argv) > 1 else 12


def read(p):
    with open(p) as f:
        return int(f.read().strip())


def power_mw():
    i, v = abs(read(f"{B}/current_now")), read(f"{B}/voltage_now")
    if i > 100000:
        i //= 1000
    if v > 100000:
        v //= 1000
    return i * v / 1000


def burn(cpu, counter, stop):
    os.sched_setaffinity(0, {cpu})
    n = 0
    while not stop.is_set():
        for _ in range(20000):
            n += 1
        counter.value = n


def measure(label, cpu=None):
    stop, counter, proc = mp.Event(), mp.Value("q", 0), None
    if cpu is not None:
        proc = mp.Process(target=burn, args=(cpu, counter, stop))
        proc.start()
        time.sleep(3)  # let the governor ramp
    start_n, start_t, samples, freqs = counter.value, time.time(), [], []
    for _ in range(SECS):
        time.sleep(1)
        samples.append(power_mw())
        if cpu is not None:
            freqs.append(read(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq") // 1000)
    rate = (counter.value - start_n) / (time.time() - start_t)
    if proc:
        stop.set()
        proc.join()
    mw = sum(samples) / len(samples)
    return label, mw, rate, (sum(freqs) // len(freqs)) if freqs else 0


def main():
    idle = measure("idle")
    print(f"idle: {idle[1]:.0f} mW")
    for cpu, name in ((0, "A53 (cpu0)"), (4, "A72 (cpu4)")):
        _, mw, rate, mhz = measure(name, cpu)
        extra = mw - idle[1]
        per = extra / (rate / 1e6) if rate else 0
        print(f"{name}: {mw:.0f} mW (+{extra:.0f} mW over idle) at ~{mhz} MHz, "
              f"{rate / 1e6:.2f} M loops/s, {per:.1f} mJ per M loops")


if __name__ == "__main__":
    main()
