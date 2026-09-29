APP      := Look Away
BUNDLE   := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
BINARY   := .build/release/LookAway
INSTALL  := /Applications/$(APP).app

.PHONY: build bundle run install test verses clean

build:
	swift build -c release

test:
	swift test

verses:
	swift scripts/generate-daily-verses.swift

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BINARY)" "$(CONTENTS)/MacOS/LookAway"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	# Install Updates in the menu pulls and rebuilds this checkout, and
	# compares GitHub against the commit the app was built from.
	if commit=$$(git rev-parse HEAD 2>/dev/null); then \
		plutil -insert LookAwaySourceDirectory -string "$(CURDIR)" "$(CONTENTS)/Info.plist"; \
		plutil -insert LookAwayCommit -string "$$commit" "$(CONTENTS)/Info.plist"; \
	fi
	codesign --force --sign - "$(BUNDLE)"

run: bundle
	pkill -x LookAway || true
	open "$(BUNDLE)"

install: bundle
	# -a: when Install Updates runs this, the app to quit is our own ancestor,
	# which pkill otherwise skips.
	pkill -ax LookAway || true
	rm -rf "$(INSTALL)"
	cp -R "$(BUNDLE)" "$(INSTALL)"
	open "$(INSTALL)"

clean:
	rm -rf .build build
