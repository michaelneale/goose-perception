#!/bin/bash
# Run GoosePerception with proper Metal shader support
# 
# This script:
# 1. Builds the app with xcodebuild (compiles metallib properly)
# 2. Sets DYLD_FRAMEWORK_PATH to find the mlx-swift_Cmlx.bundle
# 3. Runs the app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Build with xcodebuild
echo "Building with xcodebuild..."
xcodebuild -scheme GoosePerception -destination "platform=macOS" build 2>&1 | grep -E "(BUILD|error:|warning:)" | head -20

# Find the build directory
DERIVED_DATA=$(find ~/Library/Developer/Xcode/DerivedData -name "GoosePerception-*" -type d 2>/dev/null | head -1)
BUILD_DIR="${DERIVED_DATA}/Build/Products/Debug"

if [ ! -f "${BUILD_DIR}/GoosePerception" ]; then
    echo "❌ Build failed - executable not found at ${BUILD_DIR}/GoosePerception"
    exit 1
fi

echo ""
echo "✅ Build successful"
echo "📍 Running from: ${BUILD_DIR}"
echo ""

# Set framework path and run
export DYLD_FRAMEWORK_PATH="${BUILD_DIR}"

if [ "$1" == "--self-test" ]; then
    echo "🧪 Running self-test..."
    "${BUILD_DIR}/GoosePerception" --self-test
else
    echo "🚀 Starting GoosePerception..."
    "${BUILD_DIR}/GoosePerception" "$@"
fi
