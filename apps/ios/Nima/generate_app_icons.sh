#!/bin/bash

# Script to generate the modern single iOS app icon from a source image
# Usage: ./generate_app_icons.sh <source_image.png>

if [ -z "$1" ]; then
    echo "Usage: ./generate_app_icons.sh <source_image.png>"
    echo "Example: ./generate_app_icons.sh logo.png"
    exit 1
fi

SOURCE_IMAGE="$1"
ICON_DIR="Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Error: Source image '$SOURCE_IMAGE' not found"
    exit 1
fi

echo "Generating app icon from $SOURCE_IMAGE..."

sips -z 1024 1024 "$SOURCE_IMAGE" --out "$ICON_DIR/AppIcon-1024x1024.png"

echo "Done! App icon has been generated in $ICON_DIR"
