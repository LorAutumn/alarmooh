#!/usr/bin/env bash
# Baut das Release-Executable und verpackt es als Alarmooh.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# Im versteckten .build/ ablegen: Spotlight indexiert Dot-Ordner nicht,
# sonst erscheint die App doppelt im Apps-Viewer/Launchpad.
APP=".build/Alarmooh.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/alarmooh "$APP/Contents/MacOS/alarmooh"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc-Signatur genügt für lokale Nutzung inkl. Kalenderzugriff.
codesign --force --sign - "$APP"

echo "Fertig: $APP"
echo "Installieren mit: make install  (kopiert nach /Applications)"
