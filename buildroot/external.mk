# BasedOS packages of its own go in package/<name>/ (none yet).
include $(sort $(wildcard $(BR2_EXTERNAL_BASEDOS_PATH)/package/*/*.mk))

# ncurses with its terminfo library apart (libtinfo.so.6), as ROCKNIX and most distributions
# build it: spruce's card binaries (bin64/rnano, flip/lib/libmp3lame) link libtinfo.so.6, and
# Buildroot's ncurses has no option for it. Appended here, after ncurses.mk; the configure step
# reads it when it runs.
NCURSES_CONF_OPTS += --with-termlib=tinfo

# The 32-bit root (basedos_gkd350hultra_armhf_defconfig): its libraries go to /usr/lib32 of the
# system layer, beside the 64-bit ones in /usr/lib, so its loader must look there. glibc's own
# way to add a directory to the loader's built-in search path is user-defined-trusted-dirs in
# configparms; it comes after /lib and /usr/lib, whose 64-bit libraries the loader skips as the
# wrong class and goes on. Written after configure, before the build reads it.
ifeq ($(BR2_arm),y)
define BASEDOS_GLIBC_LIB32
	echo "user-defined-trusted-dirs = /usr/lib32" > $(@D)/build/configparms
endef
GLIBC_POST_CONFIGURE_HOOKS += BASEDOS_GLIBC_LIB32
endif
