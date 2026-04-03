#!/bin/bash
# Auto-increment build number and build APK
# Usage: ./build_apk.sh [--release]

PUBSPEC="pubspec.yaml"
cd "$(dirname "$0")"

# Extract current version
CURRENT=$(grep '^version:' $PUBSPEC | head -1)
VERSION_NAME=$(echo "$CURRENT" | sed 's/version: //' | sed 's/+.*//')
BUILD_NUM=$(echo "$CURRENT" | grep -o '+[0-9]*' | tr -d '+')

if [ -z "$BUILD_NUM" ]; then
    BUILD_NUM=0
fi

# Increment build number
NEW_BUILD=$((BUILD_NUM + 1))
NEW_VERSION="version: ${VERSION_NAME}+${NEW_BUILD}"

# Update pubspec.yaml
sed -i '' "s/^version:.*/$NEW_VERSION/" $PUBSPEC
echo "Version: ${VERSION_NAME} (${NEW_BUILD})"

# Build
if [ "$1" = "--release" ]; then
    flutter build apk --release
else
    flutter build apk --debug
fi

echo ""
echo "APK built: ${VERSION_NAME}+${NEW_BUILD}"
echo "Location: build/app/outputs/flutter-apk/"
