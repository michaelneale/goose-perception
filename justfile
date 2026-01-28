# GoosePerception Development Commands

# Default: build and run
default: run

# Build the app bundle
build:
    cd GoosePerception && ./build-app.sh

# Build and run the app
run: build
    @echo ""
    @echo "🚀 Launching GoosePerception..."
    open GoosePerception/build/GoosePerception.app

# Run without rebuilding (uses existing build)
launch:
    open GoosePerception/build/GoosePerception.app

# Quick rebuild with swift build only (no app bundle)
quick:
    cd GoosePerception && swift build -c release

# Clean build artifacts
clean:
    rm -rf GoosePerception/.build
    rm -rf GoosePerception/build
    @echo "✅ Build artifacts cleaned"

# Reset the perception database (fresh start)
reset-db:
    rm -rf ~/Library/Application\ Support/GoosePerception
    @echo "✅ Perception database reset"

# Reset screen capture permissions (requires restart after)
reset-permissions:
    tccutil reset ScreenCapture com.block.goose.perception
    @echo "✅ Screen capture permissions reset"
    @echo "   Restart the app to re-grant permissions"

# Full reset: database + permissions
reset-all: reset-db reset-permissions
    @echo ""
    @echo "✅ Full reset complete"

# Install to /Applications
install: build
    cp -R GoosePerception/build/GoosePerception.app /Applications/
    @echo "✅ Installed to /Applications/GoosePerception.app"

# View app logs
logs:
    log stream --predicate 'subsystem == "com.block.goose.perception"' --level debug

# Show app bundle info
info:
    @echo "=== App Bundle ==="
    @ls -lah GoosePerception/build/GoosePerception.app/Contents/MacOS/ 2>/dev/null || echo "App not built yet"
    @echo ""
    @echo "=== Code Signature ==="
    @codesign -dv --verbose=2 GoosePerception/build/GoosePerception.app 2>&1 | grep -E "(Identifier|Format|Signature)" || echo "App not signed"
    @echo ""
    @echo "=== Database ==="
    @ls -lah ~/Library/Application\ Support/GoosePerception/ 2>/dev/null || echo "No database yet"

# Kill any running GoosePerception processes
kill:
    @pkill -f GoosePerception || echo "No GoosePerception processes running"
