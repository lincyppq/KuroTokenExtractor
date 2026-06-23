ARCHS = arm64
TARGET = iphone:clang:latest:11.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KuroTokenExtractor

KuroTokenExtractor_FILES = Tweak.x
KuroTokenExtractor_CFLAGS = -fobjc-arc
KuroTokenExtractor_FRAMEWORKS = UIKit Foundation Security
KuroTokenExtractor_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
