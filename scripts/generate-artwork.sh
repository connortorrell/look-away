#!/bin/sh
# Renders the SVGs in Resources/Artwork into the files the build uses:
#
#   Resources/AppIcon.icns                  the app and disk image icon
#   Resources/dmg-background.png (+ @2x)    the DMG window background
#
# The outputs are committed, so building needs none of this. Run `make artwork`
# after editing an SVG. Needs rsvg-convert: brew install librsvg
set -eu
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg" >&2; exit 1; }

ART=Resources/Artwork
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$ART/AppIcon.svg" -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) "$ART/AppIcon.svg" -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

rsvg-convert -w 600 -h 400 "$ART/dmg-background.svg" -o Resources/dmg-background.png
rsvg-convert -w 1200 -h 800 "$ART/dmg-background.svg" -o Resources/dmg-background@2x.png

ls -l Resources/AppIcon.icns Resources/dmg-background*.png
