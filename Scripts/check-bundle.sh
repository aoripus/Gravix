#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/Gravix.app"
FRAMEWORKS="$APP/Contents/Frameworks"
codesign --verify --deep --strict "$APP"
/usr/bin/python3 - "$APP" <<'PY'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]); frameworks=app/'Contents/Frameworks'
for binary in [app/'Contents/MacOS/Gravix',*frameworks.glob('*.dylib')]:
 for row in subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines()[1:]:
  dep=row.strip().split(' (')[0]
  if dep.startswith(('/usr/lib/','/System/')): continue
  assert dep.startswith('@rpath/'),(binary,dep)
  assert (frameworks/pathlib.Path(dep).name).is_file(),(binary,dep)
print('App signature and bundled dependency closure passed')
PY
xcrun clang -I Vendor/include Tests/BundleCrypto.c "$FRAMEWORKS/libcrypto.3.dylib" -Wl,-rpath,"$FRAMEWORKS" -o .build/tests/bundle-crypto
.build/tests/bundle-crypto "$FRAMEWORKS"
