# Goose Perception Development Tasks
# Usage: just <recipe>

# Default recipe - show available commands
default:
    @just --list

# Build the app using existing build-app.sh (creates proper .app bundle with signing)
build:
    cd GoosePerception && ./build-app.sh

# Build with xcodebuild (faster, for dev iteration - no app bundle)
build-dev:
    cd GoosePerception && xcodebuild -scheme GoosePerception -destination 'platform=macOS' build 2>&1 | tail -20

# Run the app using existing run.sh
run *ARGS:
    cd GoosePerception && ./run.sh {{ARGS}}

# Run fast tests (unit + integration with mocks)
test:
    cd GoosePerception && ./run.sh --test

# Run all tests including LLM (slow, loads model)
test-full:
    cd GoosePerception && ./run.sh --test --full

# Run only TinyAgent integration tests
test-tinyagent:
    cd GoosePerception && ./run.sh --test-tinyagent

# Run integration tests with real LLM
test-llm:
    cd GoosePerception && ./run.sh --test-tinyagent-llm

# Run E2E tests (database, pipeline)
test-e2e:
    cd GoosePerception && ./run.sh --test --e2e

# Run the existing self-test harness
test-harness:
    cd GoosePerception && ./run.sh --test-harness

# Self-test (existing)
self-test:
    cd GoosePerception && ./run.sh --self-test

# Clean build artifacts
clean:
    rm -rf GoosePerception/.build
    rm -rf GoosePerception/build
    rm -rf ~/Library/Developer/Xcode/DerivedData/GoosePerception-*

# Open in Xcode
xcode:
    open GoosePerception/GoosePerception.xcodeproj

# Grant permissions (existing script)
permissions:
    cd GoosePerception && ./grant-permissions.sh

# Check git status
status:
    @git status --short
    @echo ""
    @git diff --stat

# Show test coverage summary
coverage:
    @echo "Test Suites:"
    @echo "  - Unit: Parser tests (5 tests)"
    @echo "  - Integration: Mock execution tests (7 tests)"
    @echo "  - E2E: Database, pipeline tests"
    @echo "  - LLM: Real model inference tests"
    @echo ""
    @echo "Run 'just test' for fast tests, 'just test-full' for all"
