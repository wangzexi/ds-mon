#!/bin/bash
set -e

APP_NAME="DeepSeek Monitor"
BINARY_NAME="ds-mon"
APP_DIR="dist/${APP_NAME}.app"

echo "Building ${APP_NAME}..."

swift build -c release --arch arm64 --arch x86_64

BUILD_DIR=".build/apple/Products/Release"
if [ ! -d "$BUILD_DIR" ]; then
    BUILD_DIR=".build/release"
fi

rm -rf dist
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${BINARY_NAME}" "${APP_DIR}/Contents/MacOS/"
cp "Sources/ds-mon/Info.plist" "${APP_DIR}/Contents/Info.plist"

RESOURCE_BUNDLE=$(find "${BUILD_DIR}" -name "*.bundle" -type d | head -n 1)
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "${APP_DIR}/Contents/Resources/"
fi
cp "Sources/ds-mon/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "${APP_DIR}"

cd dist
zip -r "${BINARY_NAME}.zip" "${APP_NAME}.app"
cd ..

echo "Done: dist/${BINARY_NAME}.zip"
