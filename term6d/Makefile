ARCHS = armv7
TARGET = iphone:clang:6.1:5.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = term6d
term6d_FILES = main.c
term6d_CFLAGS = -I../common -std=gnu99
term6d_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
