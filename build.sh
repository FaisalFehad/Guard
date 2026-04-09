#!/bin/bash
set -e

APP_NAME="Guard"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "Building $APP_NAME..."

rm -rf "$BUILD_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

swiftc \
    -O \
    -o "$CONTENTS/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework CoreMediaIO \
    Sources/main.swift \
    Sources/ActivityLog.swift \
    Sources/CameraMonitor.swift \
    Sources/HistoryWindowController.swift \
    Sources/AppDelegate.swift

cp Info.plist "$CONTENTS/"
cp Resources/AppIcon.icns "$CONTENTS/Resources/"

codesign --sign - --force --deep "$APP_BUNDLE"

echo ""
echo "Build successful: $APP_BUNDLE"
echo "Run with:  open $APP_BUNDLE"
