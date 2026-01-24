#!/bin/bash

APP_NAME="VoiceInk"
APP_PATH="/Users/kunalgharate/Library/Developer/Xcode/DerivedData/VoiceInk-ckkqtysznkbctugwkzqszrokocoj/Build/Products/Release/VoiceInk.app"
DMG_NAME="VoiceInk-Offline-Premium"
VOLUME_NAME="VoiceInk Offline Premium"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Creating DMG in temporary directory: $TEMP_DIR"

# Copy app to temp directory
cp -R "$APP_PATH" "$TEMP_DIR/"

# Create DMG
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_NAME.dmg"

# Clean up
rm -rf "$TEMP_DIR"

echo "DMG created: $DMG_NAME.dmg"
echo "Size: $(du -h "$DMG_NAME.dmg" | cut -f1)"
