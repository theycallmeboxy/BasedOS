#!/usr/bin/env python3
"""Mainline experiment: add BasedOS's ES9018K2M codec driver (tools/mainline/drivers/es9018k2m.c)
to the kernel tree as SND_SOC_ES9018K2M. Mainline has no driver for this DAC.

  es9018k2m-codec.py <linux tree>
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KCONFIG_ANCHOR = "config SND_SOC_ES8328_I2C\n"
KCONFIG = '''config SND_SOC_ES9018K2M
	tristate "ESS ES9018K2M DAC"
	depends on I2C
	select REGMAP_I2C
	help
	  The ESS ES9018K2M stereo DAC, on I2C, with GPIO-switched speaker and
	  headphone outputs (GameKiddy GKD 350H Ultra).

'''
MAKEFILE_ANCHOR = "snd-soc-es8328-i2c-y := es8328-i2c.o\n"
MAKEFILE_OBJ_ANCHOR = "obj-$(CONFIG_SND_SOC_ES8328_I2C)+= snd-soc-es8328-i2c.o\n"


def main():
    tree = sys.argv[1]
    codecs = os.path.join(tree, "sound/soc/codecs")
    shutil.copy(os.path.join(HERE, "..", "drivers", "es9018k2m.c"), codecs)
    kc = os.path.join(codecs, "Kconfig")
    mk = os.path.join(codecs, "Makefile")
    k = open(kc).read()
    m = open(mk).read()
    if "SND_SOC_ES9018K2M" in k:
        return
    if k.count(KCONFIG_ANCHOR) != 1 or m.count(MAKEFILE_ANCHOR) != 1 or m.count(MAKEFILE_OBJ_ANCHOR) != 1:
        sys.exit("sound/soc/codecs Kconfig/Makefile aren't the expected ones; not patching")
    open(kc, "w", newline="\n").write(k.replace(KCONFIG_ANCHOR, KCONFIG + KCONFIG_ANCHOR))
    m = m.replace(MAKEFILE_ANCHOR, MAKEFILE_ANCHOR + "snd-soc-es9018k2m-y := es9018k2m.o\n")
    m = m.replace(MAKEFILE_OBJ_ANCHOR,
                  MAKEFILE_OBJ_ANCHOR + "obj-$(CONFIG_SND_SOC_ES9018K2M)\t+= snd-soc-es9018k2m.o\n")
    open(mk, "w", newline="\n").write(m)
    print("added the ES9018K2M codec driver (SND_SOC_ES9018K2M)")


if __name__ == "__main__":
    main()
