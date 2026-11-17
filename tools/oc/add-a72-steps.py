#!/usr/bin/env python3
"""Add A72 clock steps to a decompiled 350H Ultra device tree (dtc -O dts):
    add-a72-steps.py in.dts out.dts

The chip is an RK3576S that Rockchip's cpufreq driver puts on the standard RK3576 table
("bin=0 (3)"), whose A72 steps go 2016 -> 2208. Two steps are added to the A72 table
(cluster1-opp-table), each copied from the 2208 step with the same opp-supported-hw:

  2112 MHz  the A72 top of Rockchip's own RK3576S table (opp-s-2112000000), with that row's
            voltages for every leakage level (this unit, level 6: 862.5 mV).
  2304 MHz  each level's 2208 voltage plus 37.5 mV, capped at the regulator's 950 mV (level 6:
            925 mV, the voltage GammaOS ships for 2304 on the RG Vita Pro's RK3576).

The A72 bus table (bus-a72-opp-table, the shared CCI) gets a row for each, at its 2208 row's
voltages. Nothing else changes. Measured on the unit: the firmware (BL31 v1.20) keeps reporting
2208 for the 2304 step, but at 925 mV the A72s run 4.4% faster than at 2208, as 2304 would.
"""
import re
import sys

CAP = 950000
VOLT = re.compile(r"(opp-microvolt(?:-L\d+)?) = <([0-9a-fx ]+)>;")


def node(text, table, name):
    t = text.index("\t%s {\n" % table)
    end = text.index("\n\t};\n", t)
    n = text.index("\t\t%s {\n" % name, t, end)
    return n, text.index("\t\t};\n", n) + len("\t\t};\n")


def volts(block):
    return {m.group(1): [int(x, 16) for x in m.group(2).split()] for m in VOLT.finditer(block)}


def step(src, hz, volt_of):
    a, b = node(src, "cluster1-opp-table", "opp-2208000000")
    new = src[a:b].replace("opp-2208000000 {", "opp-%d {" % hz)
    new = new.replace("opp-hz = <0x00 0x839b6800>;", "opp-hz = <0x00 0x%x>;" % hz)
    new, n = VOLT.subn(lambda m: "%s = <%s>;" % (m.group(1), " ".join("0x%x" % v for v in volt_of(m.group(1)))), new)
    assert n == 11, n
    # Keep the table in clock order: 2112 before 2208, 2304 after it.
    at = a if hz < 2208000000 else b
    src = src[:at] + new + "\n" + src[at:] if at == a else src[:at] + "\n" + new + src[at:]

    a, b = node(src, "bus-a72-opp-table", "opp-2208000000")
    row = src[a:b].replace("opp-2208000000 {", "opp-%d {" % hz).replace(
        "opp-hz = <0x00 0x839b6800>;", "opp-hz = <0x00 0x%x>;" % hz)
    return src[:a] + row + "\n" + src[a:] if hz < 2208000000 else src[:b] + "\n" + row + src[b:]


src = open(sys.argv[1]).read()
v2016 = volts(src[slice(*node(src, "cluster1-opp-table", "opp-2016000000"))])
v2208 = volts(src[slice(*node(src, "cluster1-opp-table", "opp-2208000000"))])
vs2112 = volts(src[slice(*node(src, "cluster1-opp-table", "opp-s-2112000000"))])


def s_table(key):
    return tuple(vs2112[key])


def plus(key):
    t = min(v2208[key][0] + 37500, CAP)
    return (t, t, CAP)


src = step(src, 2112000000, s_table)
src = step(src, 2304000000, plus)
open(sys.argv[2], "w").write(src)
for k in ("opp-microvolt-L6",):
    print("level 6: 2016 %d, 2112 %d, 2208 %d, 2304 %d uV" % (v2016[k][0], s_table(k)[0], v2208[k][0], plus(k)[0]))
