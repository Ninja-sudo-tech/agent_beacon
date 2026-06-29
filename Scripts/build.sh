#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
BUILD="$ROOT/.build"
APP_BUNDLE="$ROOT/AgentBeacon.app"

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk

cd "$ROOT"
mkdir -p "$BUILD/modules"

echo "==> Agent Beacon Build"
echo "    Swift: $(swift --version 2>&1 | head -1)"
echo "    SDK:   $SDK"
echo ""

# 1. Core library (shared model + store)
echo "--> Compiling Core library..."
swiftc -sdk "$SDK" \
  -module-name Core \
  -emit-module -emit-module-path "$BUILD/modules/Core.swiftmodule" \
  -emit-library -o "$BUILD/libCore.dylib" \
  -parse-as-library \
  Sources/Core/AgentStatus.swift Sources/Core/StatusStore.swift
echo "    OK"

# 2. CLI
echo "--> Compiling agent-beacon CLI..."
swiftc -sdk "$SDK" \
  -I "$BUILD/modules" \
  Sources/Core/AgentStatus.swift Sources/Core/StatusStore.swift \
  Sources/CLI/main.swift \
  -o "$BUILD/agent-beacon"
echo "    OK"

# 3. App
echo "--> Compiling AgentBeaconApp..."
swiftc -sdk "$SDK" \
  -framework AppKit \
  -I "$BUILD/modules" \
  Sources/Core/AgentStatus.swift Sources/Core/StatusStore.swift \
  Sources/App/main.swift \
  Sources/App/AppDelegate.swift \
  Sources/App/FileWatcher.swift \
  Sources/App/Preferences.swift \
  -o "$BUILD/AgentBeaconApp"
echo "    OK"

# 4. Tests
echo "--> Compiling and running tests..."
swiftc -sdk "$SDK" \
  Sources/Core/AgentStatus.swift Sources/Core/StatusStore.swift \
  Tests/main.swift \
  -o "$BUILD/CoreTests"
"$BUILD/CoreTests"
echo ""

# 5. Package app bundle
echo "--> Packaging AgentBeacon.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD/AgentBeaconApp" "$APP_BUNDLE/Contents/MacOS/"
cp Resources/App-Info.plist "$APP_BUNDLE/Contents/Info.plist"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Copy CLI to project root for easy install
cp "$BUILD/agent-beacon" "$ROOT/agent-beacon"

echo ""
echo "==> Build complete"
echo "    App bundle: $APP_BUNDLE"
echo "    CLI binary: $ROOT/agent-beacon"
echo ""
echo "Next: run Scripts/install.sh"
