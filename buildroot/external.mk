# BasedOS packages of its own go in package/<name>/ (none yet).
include $(sort $(wildcard $(BR2_EXTERNAL_BASEDOS_PATH)/package/*/*.mk))

# ncurses with its terminfo library apart (libtinfo.so.6), as ROCKNIX and most distributions
# build it: spruce's card binaries (bin64/rnano, flip/lib/libmp3lame) link libtinfo.so.6, and
# Buildroot's ncurses has no option for it. Appended here, after ncurses.mk; the configure step
# reads it when it runs.
NCURSES_CONF_OPTS += --with-termlib=tinfo
