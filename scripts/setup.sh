#!/bin/bash
# Downloads the GhosttyKit xcframework required to build Deck.
# Requires: gh (GitHub CLI)
set -e

REPO="muxy-app/ghostty"
FRAMEWORK_DIR="GhosttyKit.xcframework"
HEADER_DIR="GhosttyKit"

if [ -d "$FRAMEWORK_DIR" ]; then
    echo "GhosttyKit.xcframework already exists. Remove it to re-download."
    exit 0
fi

echo "Downloading GhosttyKit.xcframework..."
LATEST_TAG=$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName')
echo "Latest release: $LATEST_TAG"

TMPDIR=$(mktemp -d)
gh release download "$LATEST_TAG" \
    --pattern "GhosttyKit.xcframework.tar.gz" \
    --repo "$REPO" \
    --dir "$TMPDIR"

echo "Extracting..."
tar xzf "$TMPDIR/GhosttyKit.xcframework.tar.gz"
rm -rf "$TMPDIR"

# Sync headers into the GhosttyKit wrapper directory
echo "Syncing headers..."
mkdir -p "$HEADER_DIR"
cp "$FRAMEWORK_DIR/macos-arm64_x86_64/Headers/ghostty.h" "$HEADER_DIR/"
cp -r "$FRAMEWORK_DIR/macos-arm64_x86_64/Headers/ghostty" "$HEADER_DIR/" 2>/dev/null || true

echo "Done. Run 'swift build' to build Deck."
