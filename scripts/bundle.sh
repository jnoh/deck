#!/bin/bash
# Wraps the built Deck executable into a proper .app bundle
set -e

APP_DIR=".build/Deck.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp .build/debug/Deck "$MACOS/Deck"
cp Sources/DeckApp/Info.plist "$CONTENTS/Info.plist"

# Bundle default templates
RESOURCES="$CONTENTS/Resources/templates"
mkdir -p "$RESOURCES"
cp -r templates/*.deck "$RESOURCES/"
find "$RESOURCES" -name "*.sh" -exec chmod +x {} \;

echo "Built: $APP_DIR"
echo "Run:   open $APP_DIR"
