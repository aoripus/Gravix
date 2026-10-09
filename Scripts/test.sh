#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/tests
xcrun clang++ -std=c++17 Tests/TransferSafetyTests.cpp -o .build/tests/transfer-safety
.build/tests/transfer-safety
xcrun swiftc -swift-version 5 Sources/Gravix/Models.swift Sources/Gravix/Keychain.swift Sources/Gravix/ConnectionStore.swift Tests/ModelTests.swift -framework AppKit -framework Security -o .build/tests/models
.build/tests/models
xcrun clang++ -std=c++17 -fobjc-arc -fmodules -mmacosx-version-min=14.0 -I Vendor/include/freerdp3 -I Vendor/include/winpr3 Sources/RDPBridge/GravixRDP.mm Tests/ConnectionProbe.mm -L Vendor/lib -lfreerdp-client3 -lfreerdp3 -lwinpr3 -framework Cocoa -framework QuartzCore -Wl,-rpath,"$ROOT/Vendor/lib" -o .build/tests/connection-probe
.build/tests/connection-probe
xcrun clang++ -std=c++17 -fobjc-arc -fmodules -mmacosx-version-min=14.0 -I Vendor/include/freerdp3 -I Vendor/include/winpr3 Tests/ClipboardTests.mm -L Vendor/lib -lfreerdp-client3 -lfreerdp3 -lwinpr3 -framework Cocoa -framework QuartzCore -Wl,-rpath,"$ROOT/Vendor/lib" -o .build/tests/clipboard
.build/tests/clipboard
xcrun clang++ -std=c++17 -fobjc-arc -mmacosx-version-min=14.0 -I Vendor/include/freerdp3 -I Vendor/include/winpr3 -I Vendor/include Tests/HardwareDecode.mm -L Vendor/lib -lfreerdp3 -lwinpr3 -lavcodec -lavutil -framework Foundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo -Wl,-rpath,"$ROOT/Vendor/lib" -o .build/tests/hardware
.build/tests/hardware
