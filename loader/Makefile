ARCHS = armv7 arm64
TARGET = iphone:10.3:9.2

include $(THEOS)/makefiles/common.mk

TOOL_NAME = CSStashedAppExecutable
CSStashedAppExecutable_FILES = main.m
CSStashedAppExecutable_CFLAGS = -Wall
CSStashedAppExecutable_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
