#!/bin/bash
# Builds "Hack Club CDN.app" and ad-hoc signs it.
#
#   ./build.sh              build for this Mac's architecture into build/
#   ./build.sh --universal  build a universal (arm64 + x86_64) binary
#   ./build.sh --install    build, then install into /Applications and register the Finder service
#   ./build.sh --icon       re-render Resources/AppIcon.icns from Tools/MakeIcon.swift
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Hack Club CDN.app"
DEPLOYMENT_TARGET="13.0"

UNIVERSAL=0
INSTALL=0
RENDER_ICON=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install)   INSTALL=1 ;;
    --icon)      RENDER_ICON=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# The .icns is committed so CI never has to render one; --icon regenerates it.
if [[ $RENDER_ICON == 1 || ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "==> icon"
  rm -rf "$BUILD/AppIcon.iconset"
  mkdir -p "$BUILD"
  swift "$ROOT/Tools/MakeIcon.swift" "$BUILD/AppIcon.iconset" >/dev/null
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ $UNIVERSAL == 1 ]]; then
  ARCHES=(arm64 x86_64)
else
  ARCHES=("$(uname -m)")
fi

echo "==> compile (${ARCHES[*]})"
SLICES=()
for arch in "${ARCHES[@]}"; do
  slice="$BUILD/HackClubCDN-$arch"
  swiftc \
    -parse-as-library \
    -swift-version 5 \
    -O \
    -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
    "$ROOT"/Sources/*.swift \
    -o "$slice"
  SLICES+=("$slice")
done

if [[ ${#SLICES[@]} -gt 1 ]]; then
  lipo -create -output "$APP/Contents/MacOS/HackClubCDN" "${SLICES[@]}"
else
  cp "${SLICES[0]}" "$APP/Contents/MacOS/HackClubCDN"
fi
rm -f "${SLICES[@]}"

echo "==> sign (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

if [[ $INSTALL == 1 ]]; then
  echo "==> install"
  DEST="/Applications/Hack Club CDN.app"
  # Quit any running copy so the replacement registers cleanly.
  osascript -e 'tell application "Hack Club CDN" to quit' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
  echo "installed: $DEST"
  echo "note: enable the service under System Settings > Keyboard > Keyboard Shortcuts > Services"
else
  echo "built: $APP"
fi
