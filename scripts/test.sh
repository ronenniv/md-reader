#!/usr/bin/env bash
# Runs the test suite. With full Xcode, `swift test` finds Swift Testing on
# its own. With Command Line Tools only, the Testing framework and its macro
# plugin exist in the CLT but SwiftPM does not wire them up automatically, so
# pass the search/rpath flags explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVDIR=$(xcode-select -p)

if [ -d "$DEVDIR/Platforms" ]; then
  # Full Xcode.
  exec swift test "$@"
fi

exec swift test \
  -Xswiftc -F -Xswiftc "$DEVDIR/Library/Developer/Frameworks" \
  -Xswiftc -plugin-path -Xswiftc "$DEVDIR/usr/lib/swift/host/plugins/testing" \
  -Xlinker -F -Xlinker "$DEVDIR/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEVDIR/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEVDIR/Library/Developer/usr/lib" \
  "$@"
