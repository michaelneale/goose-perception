#!/bin/bash
# Build GoosePerception as a proper macOS .app bundle
# Now uses in-process MLX with proper Task.detached pattern

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="GoosePerception"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Signing identity - prefer self-signed cert for stable local development permissions
# Falls back to ad-hoc if not found
SIGNING_IDENTITY="GoosePerception Development"

# MLX metallib location - check multiple locations
MLX_METALLIB=""
for loc in \
    "$HOME/.lmstudio/extensions/backends/vendor/_amphibian/app-mlx-generate-mac-arm64@69/lib/python3.11/site-packages/mlx/lib/mlx.metallib" \
    "/tmp/mlx-venv/lib/python3.13/site-packages/mlx/lib/mlx.metallib" \
    "/tmp/mlx-venv/lib/python3.12/site-packages/mlx/lib/mlx.metallib" \
    "/tmp/mlx-venv/lib/python3.11/site-packages/mlx/lib/mlx.metallib" \
    "$HOME/Library/Python/3.13/lib/python/site-packages/mlx/lib/mlx.metallib" \
    "$HOME/Library/Python/3.12/lib/python/site-packages/mlx/lib/mlx.metallib" \
    "$HOME/Library/Python/3.11/lib/python/site-packages/mlx/lib/mlx.metallib" \
    "$(python3 -c 'import mlx; import os; print(os.path.join(os.path.dirname(mlx.__file__), "lib", "mlx.metallib"))' 2>/dev/null)"
do
    if [ -f "$loc" ]; then
        MLX_METALLIB="$loc"
        break
    fi
done

echo "🔨 Building $APP_NAME..."
echo ""

# Step 1: Build with swift build
echo "📦 Building app (swift build release)..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | grep -E "(Build complete|error:|warning:.*GoosePerception)" || true

BUILT_BINARY="$SCRIPT_DIR/.build/release/GoosePerception"
if [ ! -f "$BUILT_BINARY" ]; then
    echo "⚠️  Release build not found, trying debug..."
    swift build 2>&1 | grep -E "(Build complete|error:|warning:)" || true
    BUILT_BINARY="$SCRIPT_DIR/.build/debug/GoosePerception"
fi

if [ ! -f "$BUILT_BINARY" ]; then
    echo "❌ Build failed - binary not found"
    exit 1
fi
echo "✅ App built: $(du -h "$BUILT_BINARY" | cut -f1)"

# Step 2: Create app bundle
echo ""
echo "📦 Creating app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy main binary
cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/"
echo "  ✓ Main binary"

# Copy MLX metallib (CRITICAL - without this, MLX fails to load)
if [ -f "$MLX_METALLIB" ]; then
    cp "$MLX_METALLIB" "$APP_BUNDLE/Contents/MacOS/"
    echo "  ✓ MLX Metal shader library ($(du -h "$APP_BUNDLE/Contents/MacOS/mlx.metallib" | cut -f1))"
else
    echo "⚠️  Warning: mlx.metallib not found at $MLX_METALLIB"
    echo "   The app will fail to run without it."
    echo "   Install LM Studio or build MLX from source to get this file."
fi

# Copy Info.plist
if [ -f "$SCRIPT_DIR/GoosePerception/Info.plist" ]; then
    cp "$SCRIPT_DIR/GoosePerception/Info.plist" "$APP_BUNDLE/Contents/"
    echo "  ✓ Info.plist"
else
    # Create minimal Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>GoosePerception</string>
    <key>CFBundleIdentifier</key>
    <string>com.block.goose.perception</string>
    <key>CFBundleName</key>
    <string>Goose Perception</string>
    <key>CFBundleDisplayName</key>
    <string>Goose Perception</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Goose Perception uses the microphone for voice capture and transcription.</string>
    <key>NSCameraUsageDescription</key>
    <string>Goose Perception uses the camera for face detection to know when you're at your computer.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Goose Perception uses speech recognition to transcribe your voice.</string>
</dict>
</plist>
EOF
    echo "  ✓ Info.plist (generated)"
fi

# Copy GRDB bundle if present
GRDB_BUNDLE=$(find "$SCRIPT_DIR/.build" -name "GRDB_GRDB.bundle" -type d 2>/dev/null | head -1)
if [ -n "$GRDB_BUNDLE" ] && [ -d "$GRDB_BUNDLE" ]; then
    cp -R "$GRDB_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "  ✓ GRDB bundle"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 3: Code sign the app bundle
echo ""
echo "🔏 Code signing..."

# Check if our signing identity exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
    echo "  Using identity: $SIGNING_IDENTITY"
    codesign --force --deep --sign "$SIGNING_IDENTITY" \
        --entitlements "$SCRIPT_DIR/GoosePerception/GoosePerception.entitlements" \
        --options runtime \
        "$APP_BUNDLE" 2>&1
    SIGN_STATUS=$?
else
    echo "⚠️  Signing identity '$SIGNING_IDENTITY' not found."
    echo "   Run: ./scripts/create-signing-cert.sh to create one"
    echo "   Falling back to ad-hoc signing (permissions will reset on each build)..."
    codesign --force --deep --sign - \
        --entitlements "$SCRIPT_DIR/GoosePerception/GoosePerception.entitlements" \
        --options runtime \
        "$APP_BUNDLE" 2>&1 || true
    SIGN_STATUS=1
fi

# Verify signature
echo "  Verifying signature..."
codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | grep -E "(Identifier|Format|Signature|Authority)" || true

if [ "$SIGN_STATUS" -eq 0 ]; then
    echo "  ✅ Signed with stable identity - permissions will persist across rebuilds"
else
    echo "  ⚠️  Ad-hoc signed - you'll need to re-grant permissions after each rebuild"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ App bundle created: $APP_BUNDLE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Contents:"
ls -lah "$APP_BUNDLE/Contents/MacOS/"
echo ""
echo "Total size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "To run:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -R $APP_BUNDLE /Applications/"
