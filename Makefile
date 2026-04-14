ARCHS = armv7 arm64
TARGET = iphone:10.3:9.2
STASH_VERSION = 2.1.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = StashApps Unloader
StashApps_FILES = src/main.mm src/stashutils.mm src/appstasher.mm src/binlibstasher.mm src/fstabutil.mm
StashApps_CFLAGS = -Wall -DSTASH_VERSION=\"$(STASH_VERSION)\"
Unloader_FILES = src/unloader.mm src/stashutils.mm
Unloader_CFLAGS = -Wall -DSTASH_VERSION=\"$(STASH_VERSION)\"

include $(THEOS_MAKE_PATH)/tool.mk

SUBPROJECTS += loader
include $(THEOS_MAKE_PATH)/aggregate.mk

LIPO ?= $(shell command -v lipo 2>/dev/null || echo $(THEOS)/toolchain/linux/iphone/bin/lipo)

after-stage::
	@# StashApps is the package post-install binary, not a regular tool
	mkdir -p $(THEOS_STAGING_DIR)/DEBIAN
	mv $(THEOS_STAGING_DIR)/usr/bin/StashApps $(THEOS_STAGING_DIR)/DEBIAN/postinst
	mv $(THEOS_STAGING_DIR)/usr/bin/Unloader $(THEOS_STAGING_DIR)/DEBIAN/postrm
	rmdir $(THEOS_STAGING_DIR)/usr/bin
	chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postrm
	chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postinst
	@# Split fat CSStashedAppExecutable into per-arch thin binaries
	$(LIPO) $(THEOS_STAGING_DIR)/usr/local/bin/CSStashedAppExecutable -thin arm64 \
		-output $(THEOS_STAGING_DIR)/usr/local/bin/CSStashedAppExecutable64
	$(LIPO) $(THEOS_STAGING_DIR)/usr/local/bin/CSStashedAppExecutable -thin armv7 \
		-output $(THEOS_STAGING_DIR)/usr/local/bin/CSStashedAppExecutable.tmp
	mv $(THEOS_STAGING_DIR)/usr/local/bin/CSStashedAppExecutable.tmp \
		$(THEOS_STAGING_DIR)/usr/local/bin/CSStashedAppExecutable
	@# Copy DEBIAN scripts from layout and stamp version into preinst
	cp layout/DEBIAN/triggers $(THEOS_STAGING_DIR)/DEBIAN/triggers
	sed 's/@STASH_VERSION@/$(STASH_VERSION)/g' layout/DEBIAN/preinst > $(THEOS_STAGING_DIR)/DEBIAN/preinst
	chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/preinst
