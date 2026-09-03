APP      := Look Away
BUNDLE   := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
BINARY   := .build/release/LookAway
INSTALL  := /Applications/$(APP).app

.PHONY: build bundle run install test clean

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BINARY)" "$(CONTENTS)/MacOS/LookAway"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	codesign --force --sign - "$(BUNDLE)"

run: bundle
	pkill -x LookAway || true
	open "$(BUNDLE)"

install: bundle
	pkill -x LookAway || true
	rm -rf "$(INSTALL)"
	cp -R "$(BUNDLE)" "$(INSTALL)"
	open "$(INSTALL)"

clean:
	rm -rf .build build
