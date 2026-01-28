#!/bin/bash
# Build script for GoosePerception
# Creates a proper macOS app bundle from swift build output

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="GoosePerception"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building GoosePerception..."
cd "$PROJECT_DIR"

# Build with swift
swift build -c debug

# Find the built executable
EXECUTABLE="$PROJECT_DIR/.build/arm64-apple-macosx/debug/GoosePerception"
if [ ! -f "$EXECUTABLE" ]; then
    # Try alternate path
    EXECUTABLE="$PROJECT_DIR/.build/debug/GoosePerception"
fi

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Could not find built executable"
    exit 1
fi

echo "📦 Creating app bundle..."

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create a launcher script that sets working directory for MLX metallib
cat > "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-launcher" << 'LAUNCHER'
#!/bin/bash
# Launcher script to ensure MLX can find default.metallib
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
exec "$SCRIPT_DIR/GoosePerception-bin" "$@"
LAUNCHER
chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-launcher"
mv "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-bin"
mv "$APP_BUNDLE/Contents/MacOS/${APP_NAME}-launcher" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/GoosePerception/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy any bundle resources (like GRDB bundle)
if [ -d "$PROJECT_DIR/.build/arm64-apple-macosx/debug/GRDB_GRDB.bundle" ]; then
    cp -R "$PROJECT_DIR/.build/arm64-apple-macosx/debug/GRDB_GRDB.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy MLX metallib to MacOS directory (same dir as executable)
# MLX looks for default.metallib relative to the executable
if [ -f "$PROJECT_DIR/.build/arm64-apple-macosx/debug/mlx.metallib" ]; then
    cp "$PROJECT_DIR/.build/arm64-apple-macosx/debug/mlx.metallib" "$APP_BUNDLE/Contents/MacOS/default.metallib"
    echo "📦 Included default.metallib (MLX metal kernels)"
fi

# Sign the app (ad-hoc for development)
echo "🔏 Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || echo "⚠️ Code signing skipped (may need manual signing)"

echo "✅ Build complete: $APP_BUNDLE"
echo ""
echo "To run:"
echo "  open $APP_BUNDLE"
echo "  # or"
echo "  $APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo "To run tests:"
echo "  $APP_BUNDLE/Contents/MacOS/$APP_NAME --test-harness --test-all"
