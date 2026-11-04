#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building SwiftPM targets..."
swift build

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ -d "$DEV_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" ]]; then
  echo "==> Running swift test via Xcode XCTest..."
  swift test
else
  echo "==> CommandLineTools active (no XCTest.framework); compiling standalone test runner..."
  mkdir -p .build
  RUNNER_BIN=".build/school-tracker-test-runner"
  swiftc \
    -D STANDALONE_TEST_RUNNER \
    -target arm64-apple-macosx14.0 \
    Sources/SchoolTrackerCore/*.swift \
    Tests/SchoolTrackerCoreTests/*.swift \
    -o "$RUNNER_BIN"
  echo "==> Executing SchoolTrackerCoreTests..."
  "$RUNNER_BIN"
fi
