#!/bin/bash
# Sets up Deck: downloads GhosttyKit and installs default templates.
# Requires: gh (GitHub CLI)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- GhosttyKit xcframework ---

REPO="muxy-app/ghostty"
FRAMEWORK_DIR="$PROJECT_DIR/GhosttyKit.xcframework"
HEADER_DIR="$PROJECT_DIR/GhosttyKit"

if [ ! -d "$FRAMEWORK_DIR" ]; then
    echo "Downloading GhosttyKit.xcframework..."
    LATEST_TAG=$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName')
    echo "Latest release: $LATEST_TAG"

    TMPDIR=$(mktemp -d)
    gh release download "$LATEST_TAG" \
        --pattern "GhosttyKit.xcframework.tar.gz" \
        --repo "$REPO" \
        --dir "$TMPDIR"

    echo "Extracting..."
    tar xzf "$TMPDIR/GhosttyKit.xcframework.tar.gz" -C "$PROJECT_DIR"
    rm -rf "$TMPDIR"

    echo "Syncing headers..."
    mkdir -p "$HEADER_DIR"
    cp "$FRAMEWORK_DIR/macos-arm64_x86_64/Headers/ghostty.h" "$HEADER_DIR/"
    cp -r "$FRAMEWORK_DIR/macos-arm64_x86_64/Headers/ghostty" "$HEADER_DIR/" 2>/dev/null || true
else
    echo "GhosttyKit.xcframework already exists."
fi

# --- Install default templates ---

APPS_DIR="$HOME/.deck/apps"
TEMPLATES_DIR="$PROJECT_DIR/templates"

if [ -d "$TEMPLATES_DIR" ]; then
    mkdir -p "$APPS_DIR"
    for template in "$TEMPLATES_DIR"/*.deck; do
        name=$(basename "$template")
        dest="$APPS_DIR/$name"
        if [ ! -d "$dest" ]; then
            echo "Installing template: $name"
            cp -r "$template" "$dest"
            # Make scripts executable
            find "$dest" -name "*.sh" -exec chmod +x {} \;
        else
            echo "Template already exists: $name"
        fi
    done
fi

echo ""
echo "Done. Next steps:"
echo "  swift build"
echo "  ./scripts/bundle.sh"
echo "  open .build/Deck.app"
