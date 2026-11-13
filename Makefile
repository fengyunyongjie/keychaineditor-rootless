.DEFAULT_GOAL := keychaineditor
PACKAGE_SCHEME ?= $(if $(THEOS_PACKAGE_SCHEME),$(THEOS_PACKAGE_SCHEME),rootful)

ifneq ($(PACKAGE_SCHEME),rootful)
ifneq ($(PACKAGE_SCHEME),rootless)
$(error Unsupported PACKAGE_SCHEME '$(PACKAGE_SCHEME)'; use rootful or rootless)
endif
endif

ifeq ($(PACKAGE_SCHEME),rootless)
iOS_MIN_VERSION ?= 15.0
PLATFORM        = iphoneos
SDK_PATH        = $(shell xcrun --show-sdk-path -sdk $(PLATFORM))
SWIFT           = $(shell xcrun -f swiftc)
CLANG           = $(shell xcrun -f clang)
LDID           ?= ldid
DPKG_DEB       ?= dpkg-deb
PYTHON         ?= python3
TARGET          = arm64-apple-ios$(iOS_MIN_VERSION)
BUILD_CONFIG   := $(shell printf '%s\n' "$(TARGET)" "$(SDK_PATH)" "$(CLANG)" "$(SWIFT)" "$(ENTITLEMENTS)" | shasum -a 256 | cut -c1-12)
BUILD_DIR       = build/rootless/$(BUILD_CONFIG)
STAGING_DIR     = $(BUILD_DIR)/package
BINARY          = $(BUILD_DIR)/keychaineditor
PACKAGE_BINARY  = $(STAGING_DIR)/var/jb/usr/bin/keychaineditor
PACKAGE         = keychaineditor-rootless.deb
ENTITLEMENTS    ?= src/entitlements.xml
SOURCE          = $(wildcard src/*.swift)
C_SOURCE        = $(wildcard src/*.c)
HEADERS         = $(wildcard src/*.h)

## ROOTLESS BUILD AND PACKAGING ##
.DELETE_ON_ERROR:
.PHONY: keychaineditor compile link sign package verify clean FORCE
FORCE:

keychaineditor: package
compile link: $(BINARY)
sign: $(PACKAGE_BINARY)
package: $(PACKAGE)

$(BUILD_DIR):
	mkdir -p "$@"

$(BUILD_DIR)/decodeSecAccessControl.o: src/decodeSecAccessControl.c $(C_SOURCE) $(HEADERS) Makefile | $(BUILD_DIR)
	$(CLANG) -target $(TARGET) -isysroot "$(SDK_PATH)" -c "$<" -o "$@"

$(BUILD_DIR)/refreshKeychainGroups.o: src/refreshKeychainGroups.c $(HEADERS) Makefile | $(BUILD_DIR)
	$(CLANG) -target $(TARGET) -isysroot "$(SDK_PATH)" -c "$<" -o "$@"

$(BINARY): $(SOURCE) $(C_SOURCE) $(HEADERS) $(BUILD_DIR)/decodeSecAccessControl.o $(BUILD_DIR)/refreshKeychainGroups.o Makefile
	$(SWIFT) -target $(TARGET) -sdk "$(SDK_PATH)" -O \
		-import-objc-header src/bridgingheader.h $(SOURCE) \
		$(BUILD_DIR)/decodeSecAccessControl.o $(BUILD_DIR)/refreshKeychainGroups.o -o "$@"

$(PACKAGE_BINARY): $(BINARY) $(ENTITLEMENTS) Makefile
	mkdir -p "$(dir $@)"
	cp "$(BINARY)" "$@"
	chmod 755 "$@"
	$(LDID) -S$(ENTITLEMENTS) "$@"

$(STAGING_DIR)/DEBIAN/control: keychaineditor/DEBIAN/control Makefile
	mkdir -p "$(dir $@)"
	$(PYTHON) -I -c 'from pathlib import Path; import sys; text = Path(sys.argv[1]).read_text(); Path(sys.argv[2]).write_text(text.replace("Architecture: iphoneos-arm\n", "Architecture: iphoneos-arm64\n"))' "$<" "$@"
	chmod 644 "$@"

$(PACKAGE): $(PACKAGE_BINARY) $(STAGING_DIR)/DEBIAN/control FORCE
	$(DPKG_DEB) --root-owner-group -Zgzip -b "$(STAGING_DIR)" "$@"

verify: $(PACKAGE)
	$(PYTHON) -I scripts/verify-rootless.py "$(PACKAGE)"

.PHONY: test test-device
TEST_SOURCE = src/keychain.swift src/utils.swift tests/compatibility/main.swift
HOST_TEST_DIR = build/compatibility
HOST_SDK_PATH = $(shell xcrun --sdk macosx --show-sdk-path)

$(HOST_TEST_DIR):
	mkdir -p "$@"

$(HOST_TEST_DIR)/decodeSecAccessControl.o: src/decodeSecAccessControl.c $(C_SOURCE) $(HEADERS) Makefile | $(HOST_TEST_DIR)
	$(CLANG) -isysroot "$(HOST_SDK_PATH)" -c "$<" -o "$@"

$(HOST_TEST_DIR)/decodeSecAccessControl-disabled.o: src/decodeSecAccessControl.c $(HEADERS) Makefile | $(HOST_TEST_DIR)
	$(CLANG) -isysroot "$(HOST_SDK_PATH)" -DKEYCHAINEDITOR_DISABLE_PRIVATE_API -c "$<" -o "$@"

$(HOST_TEST_DIR)/compatibility: $(TEST_SOURCE) $(HEADERS) $(HOST_TEST_DIR)/decodeSecAccessControl.o Makefile
	$(SWIFT) -sdk "$(HOST_SDK_PATH)" -O -import-objc-header src/bridgingheader.h $(TEST_SOURCE) $(HOST_TEST_DIR)/decodeSecAccessControl.o -o "$@"

$(HOST_TEST_DIR)/compatibility-disabled: $(TEST_SOURCE) $(HEADERS) $(HOST_TEST_DIR)/decodeSecAccessControl-disabled.o Makefile
	$(SWIFT) -sdk "$(HOST_SDK_PATH)" -O -import-objc-header src/bridgingheader.h $(TEST_SOURCE) $(HOST_TEST_DIR)/decodeSecAccessControl-disabled.o -o "$@"

test: $(HOST_TEST_DIR)/compatibility $(HOST_TEST_DIR)/compatibility-disabled
	$(PYTHON) -I scripts/test-compatibility.py "$(HOST_TEST_DIR)/compatibility"
	$(PYTHON) -I scripts/test-compatibility.py "$(HOST_TEST_DIR)/compatibility-disabled"

$(BUILD_DIR)/decodeSecAccessControl-disabled.o: src/decodeSecAccessControl.c $(HEADERS) Makefile | $(BUILD_DIR)
	$(CLANG) -target $(TARGET) -isysroot "$(SDK_PATH)" -DKEYCHAINEDITOR_DISABLE_PRIVATE_API -c "$<" -o "$@"

$(BUILD_DIR)/compatibility: $(TEST_SOURCE) $(HEADERS) $(BUILD_DIR)/decodeSecAccessControl.o Makefile
	$(SWIFT) -target $(TARGET) -sdk "$(SDK_PATH)" -O -import-objc-header src/bridgingheader.h $(TEST_SOURCE) $(BUILD_DIR)/decodeSecAccessControl.o -o "$@"
	$(LDID) -S "$@"

$(BUILD_DIR)/compatibility-disabled: $(TEST_SOURCE) $(HEADERS) $(BUILD_DIR)/decodeSecAccessControl-disabled.o Makefile
	$(SWIFT) -target $(TARGET) -sdk "$(SDK_PATH)" -O -import-objc-header src/bridgingheader.h $(TEST_SOURCE) $(BUILD_DIR)/decodeSecAccessControl-disabled.o -o "$@"
	$(LDID) -S "$@"

test-device: $(BUILD_DIR)/compatibility $(BUILD_DIR)/compatibility-disabled

clean:
	rm -rf "build/rootless"
	rm -f "$(PACKAGE)"

else
iOS_MIN_VERSION =  9.0
ARCH_FLAGS      =  -arch arm64
TARGET          =  -target arm64-apple-ios9
PLATFORM        =  iphoneos

SDK_PATH        = $(shell xcrun --show-sdk-path -sdk $(PLATFORM))
TOOLCHAIN        = Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/$(PLATFORM)
TOOLCHAIN_PATH  = $(shell xcode-select --print-path)/$(TOOLCHAIN)

## SWIFT COMPILER SETUP ##
SWIFT        =  $(shell xcrun -f swift) -frontend -c -color-diagnostics
SWIFT_FLAGS  = -g -Onone $(TARGET) \
               -import-objc-header src/bridgingheader.h \
              -sdk $(SDK_PATH)

## CLANG COMPILER SETUP FOR C ##
CLANG        =  $(shell xcrun -f clang) -c
CLANG_FLAGS  =  $(ARCH_FLAGS) \
              -isysroot  $(SDK_PATH) \
              -mios-version-min=$(iOS_MIN_VERSION)

## LINKER SETTINGS ##
LD        = $(shell xcrun -f ld)
LD_FLAGS  =  -syslibroot $(SDK_PATH) \
            -lSystem $(ARCH_FLAGS)  \
            -ios_version_min $(iOS_MIN_VERSION) \
            -no_objc_category_merging  \
            -L $(TOOLCHAIN_PATH)

SOURCE = $(notdir $(wildcard src/*.swift))
C_SOURCE = $(notdir $(wildcard src/*.c))

keychaineditor: compile link sign copylibs package removegarbage

compile: $(C_SOURCE) $(SOURCE) main.swift

decodeSecAccessControl.c:
	$(CLANG) $(CLANG_FLAGS) src/$@

refreshKeychainGroups.c:
	$(CLANG) $(CLANG_FLAGS) src/$@

%.swift:
	$(SWIFT) $(SWIFT_FLAGS) -primary-file src/$@ \
	$(addprefix src/,$(filter-out $@,$(SOURCE))) \
	-module-name keychaineditor -o $*.o -emit-module \
	-emit-module-path $*~partial.swiftmodule

main.swift:
	$(SWIFT) $(SWIFT_FLAGS) -primary-file src/$@ \
	$(addprefix src/,$(filter-out $@,$(SOURCE))) \
	-module-name keychaineditor -o main.o -emit-module \
	-emit-module-path main~partial.swiftmodule

link:
	$(LD) $(LD_FLAGS) *.o -o keychaineditor/usr/local/bin/keychaineditor

sign:
	ldid -Ssrc/entitlements.xml keychaineditor/usr/local/bin/keychaineditor

FILES = $(addprefix $(TOOLCHAIN_PATH)/,libswiftCore.dylib libswiftCoreFoundation.dylib libswiftCoreGraphics.dylib libswiftDarwin.dylib libswiftDispatch.dylib libswiftFoundation.dylib libswiftObjectiveC.dylib libswiftSwiftOnoneSupport.dylib libswiftos.dylib)
copylibs:
	cp $(FILES) keychaineditor/usr/local/lib/

package:
	dpkg-deb -Zgzip -b keychaineditor

removegarbage:
	rm *.o *.swiftmodule

clean:
	rm -f keychaineditor/usr/local/bin/keychaineditor
	rm -f keychaineditor/usr/lib/*
	rm -f keychaineditor.deb
endif
