FINALPACKAGE := 1
TARGET := iphone:clang:latest:12.2
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

# swift package location

XCDD_TOP = $(HOME)/Library/Developer/Xcode/DerivedData/
XCDD_MID = $(shell basename $(XCDD_TOP)/$(PWD)*)
XCDD_BOT = /SourcePackages/checkouts

MOD_NAME = ArgParser
MOD_LOC = $(XCDD_TOP)$(XCDD_MID)$(XCDD_BOT)/$(MOD_NAME)/src/ArgParser

# Define included files, imported frameworks, etc.

TOOL_NAME = fricon
$(TOOL_NAME)_FILES = $(shell find Sources/friconswift -name '*.swift') $(wildcard $(shell find $(MOD_LOC) -name '*.swift'))
$(TOOL_NAME)_INSTALL_PATH = /usr/local/bin

before-package::
	ldid -S $(THEOS_STAGING_DIR)/usr/local/bin/$(TOOL_NAME);

include $(THEOS_MAKE_PATH)/tool.mk
