#!/bin/bash
# setup.sh — Downloads ffmpeg-kit XCFramework for iOS (Full GPL build)
#
# Usage:
#   chmod +x scripts/setup.sh
#   ./scripts/setup.sh

set -euo pipefail

FFMPEG_KIT_VERSION="6.0"
FRAMEWORK_DIR="Frameworks"
FRAMEWORK_NAME="ffmpegkit.xcframework"
DOWNLOAD_URL="https://github.com/arthenica/ffmpeg-kit/releases/download/v${FFMPEG_KIT_VERSION}/ffmpeg-kit-full-gpl-${FFMPEG_KIT_VERSION}-ios-xcframework.zip"
ZIP_FILE="ffmpeg-kit.zip"

if [ -d "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" ]; then
    echo "ffmpeg-kit XCFramework already exists. Skipping download."
    exit 0
fi

echo "Downloading ffmpeg-kit v${FFMPEG_KIT_VERSION} (Full GPL)..."
mkdir -p "${FRAMEWORK_DIR}"
curl -L -o "${ZIP_FILE}" "${DOWNLOAD_URL}"

echo "Extracting..."
unzip -o "${ZIP_FILE}" -d "${FRAMEWORK_DIR}"
rm -f "${ZIP_FILE}"

if [ ! -d "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" ]; then
    echo ""
    echo "NOTE: The extracted framework might have a different directory name."
    echo "Please check ${FRAMEWORK_DIR}/ and rename the .xcframework directory to '${FRAMEWORK_NAME}'"
    echo ""
    echo "Alternatively, download manually from:"
    echo "  https://github.com/arthenica/ffmpeg-kit/releases"
    echo ""
    echo "Select: ffmpeg-kit-full-gpl → iOS → XCFramework"
    echo "Place the .xcframework in the ${FRAMEWORK_DIR}/ directory as '${FRAMEWORK_NAME}'"
fi

echo "Done! You can now generate the Xcode project with: xcodegen generate"
