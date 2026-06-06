#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/happy-workdog-tests.XXXXXX")"
LIST_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/happy-workdog-test-list.XXXXXX")"
trap 'rm -f "$TEST_OUTPUT" "$LIST_OUTPUT"' EXIT

swift test --disable-sandbox --enable-swift-testing --disable-xctest "$@" 2>&1 | tee "$TEST_OUTPUT"
swift test --disable-sandbox --enable-swift-testing --disable-xctest list 2>&1 | tee "$LIST_OUTPUT"

if ! grep -Eq '@Test|HappyWorkdogTests|happy_workdogTests|/[A-Za-z0-9_]+$' "$LIST_OUTPUT"; then
    cat >&2 <<'MESSAGE'

error: SwiftPM built the test bundle but did not list any tests.

This usually means the local Command Line Tools installation cannot execute the
Swift Testing runner. Install/select a full Xcode toolchain, or run tests in CI
with Swift Testing support, before treating test output as valid.
MESSAGE
    exit 1
fi
