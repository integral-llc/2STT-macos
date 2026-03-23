#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_DIR=".build/debug/DualSTTApp.app"
BINARY=".build/debug/DualSTTApp"
CONTENTS="$APP_DIR/Contents"
IDENTITY="Apple Development: Eugen Rata (3H5VXQQR83)"

# Kill any running instance
pkill -f "DualSTTApp.app" 2>/dev/null || true
sleep 0.3

# Build
echo "Building..."
swift build 2>&1
echo "Build OK"

# Create .app bundle if needed
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/DualSTTApp"

cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DualSTTApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.eugenerat.DualSTT</string>
    <key>CFBundleName</key>
    <string>DualSTT</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>DualSTT needs microphone access to transcribe your speech.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>DualSTT needs to capture system audio to transcribe what others are saying.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>DualSTT uses on-device speech recognition to convert audio to text.</string>
</dict>
</plist>
EOF

# Sign with developer identity + entitlements
codesign --force --sign "$IDENTITY" \
    --entitlements DualSTT.entitlements \
    "$APP_DIR" 2>/dev/null

echo "Launching..."
open "$APP_DIR"
