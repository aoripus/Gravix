#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ ! -f Vendor/lib/libfreerdp3.dylib ]; then Scripts/build-dependencies.sh; fi
/usr/bin/python3 Scripts/generate-project.py
xcodebuild -project Gravix.xcodeproj -scheme Gravix -configuration Release -derivedDataPath build/DerivedData build
# Copy into a fresh bundle: merging over the previous app leaves removed resources
# behind and invalidates the code signature.
/usr/bin/python3 - <<'PY'
from pathlib import Path
import subprocess, tempfile
root = Path.cwd()
target = root / 'build/Gravix.app'
with tempfile.TemporaryDirectory(prefix='.bundle-', dir=root / 'build') as stage:
    staged = Path(stage) / 'Gravix.app'
    previous = Path(stage) / 'previous.app'
    subprocess.run(['/usr/bin/ditto', str(root / 'build/DerivedData/Build/Products/Release/Gravix.app'), str(staged)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
    if target.exists():
        target.rename(previous)
    try:
        staged.rename(target)
    except OSError:
        if previous.exists():
            previous.rename(target)
        raise
PY
printf '\nBuilt: %s/build/Gravix.app\n' "$ROOT"
