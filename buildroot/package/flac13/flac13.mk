################################################################################
#
# flac13: FLAC 1.3's library (libFLAC.so.8) only, beside Buildroot's FLAC 1.4
#
################################################################################

FLAC13_VERSION = 1.3.4
FLAC13_SITE = https://ftp.osuosl.org/pub/xiph/releases/flac
FLAC13_SOURCE = flac-$(FLAC13_VERSION).tar.xz
FLAC13_LICENSE = Xiph BSD-like (libFLAC)
FLAC13_LICENSE_FILES = COPYING.Xiph
FLAC13_DEPENDENCIES = libogg
# No headers in staging: those are FLAC 1.4's, which the rest of the build compiles against.
FLAC13_INSTALL_STAGING = NO
FLAC13_CONF_OPTS = \
	--disable-cpplibs \
	--disable-xmms-plugin \
	--disable-doxygen-docs \
	--disable-thorough-tests \
	--disable-stack-smash-protection \
	--disable-oggtest \
	--with-ogg=$(STAGING_DIR)/usr

define FLAC13_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/libFLAC
endef

define FLAC13_INSTALL_TARGET_CMDS
	cp -a $(@D)/src/libFLAC/.libs/libFLAC.so.8* $(TARGET_DIR)/usr/lib/
endef

$(eval $(autotools-package))
