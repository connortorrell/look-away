APP      := Look Away
BUNDLE   := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
INSTALL  := /Applications/$(APP).app

# `make dist` overrides these for a universal, Developer ID-signed release.
# Left alone they build for this Mac and sign ad hoc, which needs no
# certificate. VERSION and BUILD_NUMBER default to what Info.plist says.
ARCH_FLAGS    :=
BINARY        := .build/release/LookAway
SIGN_IDENTITY := -
VERSION       :=
BUILD_NUMBER  :=
NOTARIZE      := 1

# pkill only sends the signal. Opening the app again before the old copy has
# exited can fail with LaunchServices error -600, so wait (up to 5s) for it.
QUIT_APP := pkill -x LookAway; \
	for _ in $$(seq 50); do pgrep -x LookAway >/dev/null || break; sleep 0.1; done

.PHONY: build bundle run install dist test verses artwork clean

build:
	swift build -c release $(ARCH_FLAGS)

test:
	swift test

verses:
	swift scripts/generate-daily-verses.swift

artwork:
	scripts/generate-artwork.sh

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BINARY)" "$(CONTENTS)/MacOS/LookAway"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	$(if $(VERSION),plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(CONTENTS)/Info.plist")
	$(if $(BUILD_NUMBER),plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(CONTENTS)/Info.plist")
	# Notarization needs the hardened runtime and a secure timestamp, and only
	# a real identity can get a timestamp, so ad hoc builds skip both.
	codesign --force $(if $(filter -,$(SIGN_IDENTITY)),,--options runtime --timestamp) \
		--sign "$(SIGN_IDENTITY)" "$(BUNDLE)"

run: bundle
	$(QUIT_APP)
	open "$(BUNDLE)"

install: bundle
	$(QUIT_APP)
	rm -rf "$(INSTALL)"
	cp -R "$(BUNDLE)" "$(INSTALL)"
	open "$(INSTALL)"

# A release: dist/LookAway.dmg for people, dist/LookAway.zip for the in-app
# updater. NOTARIZE=0 skips Apple's notary service for a local dry run.
dist:
	VERSION="$(VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		NOTARIZE="$(NOTARIZE)" scripts/package-release.sh

clean:
	rm -rf .build build dist
