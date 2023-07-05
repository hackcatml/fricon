FINALPACKAGE := 1
TARGET := iphone:clang:latest:14.2
ARCHS := arm64 arm64e

THEOS_DEVICE_IP = localhost -p 2222

#ROOTLESS = 1

# swift package location
XCDD_TOP = $(HOME)/Library/Developer/Xcode/DerivedData/
XCDD_MID = $(shell basename $(XCDD_TOP)/$(PWD)*)
XCDD_BOT = /SourcePackages/checkouts

MOD_NAME = ArgParser
MOD_LOC = $(XCDD_TOP)$(XCDD_MID)$(XCDD_BOT)/$(MOD_NAME)/src/ArgParser

# Set rootless package scheme
THEOS_PACKAGE_SCHEME =
TOOL_INSTALL_PATH = /usr/local/bin
ifeq ($(ROOTLESS),1)
	THEOS_PACKAGE_SCHEME = rootless
	TOOL_INSTALL_PATH = /var/jb/usr/bin
endif

# Define included files, imported frameworks, etc.

TOOL_NAME = fricon
$(TOOL_NAME)_FILES = $(shell find Sources/friconswift -name '*.swift') $(wildcard $(shell find $(MOD_LOC) -name '*.swift'))
$(TOOL_NAME)_INSTALL_PATH = $(TOOL_INSTALL_PATH)
	
before-package::
	ldid -S $(THEOS_STAGING_DIR)$(TOOL_INSTALL_PATH)/$(TOOL_NAME);

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tool.mk
