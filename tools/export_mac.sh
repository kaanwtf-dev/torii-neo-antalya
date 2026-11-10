#!/bin/bash
# Builds the Mac app Torii double-clicks (CRT-02):
#   godot/build/TORİİ NEO ANTALYA.app   (universal: Intel + Apple Silicon, ad-hoc signed)
#   godot/build/TORII-NEO-ANTALYA-<ver>-mac.zip   (the one to send her)
# Needs Godot 4.7.2 on the PATH as `godot` and its export templates in
# ~/Library/Application Support/Godot/export_templates/4.7.2.stable (installed 2026-11-09).
# Run from anywhere:  bash tools/export_mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="godot/build/TORİİ NEO ANTALYA.app"
rm -rf "$APP"; mkdir -p godot/build

# 1. refresh the import cache (new scripts / class names), then export with the "macOS" preset (godot/export_presets.cfg)
perl -e 'alarm 600; exec @ARGV' godot --headless --path godot --import >/dev/null 2>&1 || true
perl -e 'alarm 600; exec @ARGV' godot --headless --path godot --export-release "macOS" "build/TORİİ NEO ANTALYA.app"

# 2. Godot names the inner binary and .pck after the game ("TORİİ- NEO ANTALYA"). The Turkish İ in those inner file
#    names breaks macOS's signature check ("a sealed resource is missing or invalid", which Finder shows as "the app is
#    damaged"), so they become plain "Torii" / "Torii.pck" (the binary finds its .pck by its own name). The app's name,
#    window title and save folder don't change.
EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")
if [ "$EXE" != "Torii" ]; then
  mv "$APP/Contents/MacOS/$EXE" "$APP/Contents/MacOS/Torii"
  mv "$APP/Contents/Resources/$EXE.pck" "$APP/Contents/Resources/Torii.pck"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Torii" "$APP/Contents/Info.plist"
fi

# 3. re-sign ad-hoc (no Apple developer account) and check it
codesign --force --deep --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"

# 4. zip it for AirDrop / a USB stick (ditto keeps the signature intact)
VER=$(python3 -c 'import json; print(json.load(open("godot/assets/story/godot.json"))["ver"].split(" ")[1])')
ZIP="godot/build/TORII-NEO-ANTALYA-$VER-mac.zip"
rm -f "$ZIP"; ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "built: $APP"
echo "zip:   $ZIP ($(du -h "$ZIP" | cut -f1))"
