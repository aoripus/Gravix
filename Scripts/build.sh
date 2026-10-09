#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ ! -f Vendor/lib/libfreerdp3.dylib ]; then Scripts/build-dependencies.sh; fi
/usr/bin/python3 Scripts/generate-project.py
xcodebuild -project Gravix.xcodeproj -scheme Gravix -configuration Release -derivedDataPath build/DerivedData build
/usr/bin/ditto build/DerivedData/Build/Products/Release/Gravix.app build/Gravix.app
printf '\nBuilt: %s/build/Gravix.app\n' "$ROOT"
