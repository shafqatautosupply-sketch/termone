# Term6 - terminal for jailbroken iOS 6 (app + root session daemon)
#
# If your Theos is the older on-device flavour and complains about the TARGET line, use
#   TARGET = iphone:6.1:5.0
ARCHS = armv7
TARGET = iphone:clang:6.1:5.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Term6

Term6_FILES = main.m Term6Application.m AppDelegate.m TerminalViewController.m TerminalView.m \
              KeyBarView.m KeyButton.m CommandPanelView.m CommandsViewController.m CommandEditViewController.m \
              TerminalSession.m SettingsViewController.m EncodingViewController.m Settings.m TermTheme.m TermEncoding.m \
              $(wildcard vterm/src/*.c)
Term6_CFLAGS = -Ivterm/include -Ivterm/src -Icommon -std=gnu99 -Wno-deprecated-declarations
Term6_OBJCFLAGS = -fobjc-arc
Term6_FRAMEWORKS = UIKit Foundation CoreGraphics CoreText QuartzCore

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS = term6d term6root
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	@chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/prerm 2>/dev/null || true

after-install::
	install.exec "uicache"
