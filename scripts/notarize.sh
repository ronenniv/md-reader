#!/usr/bin/env bash
# Notarizes and staples dist/MDReader.app, producing a distributable
# MDReader.zip that passes Gatekeeper on any Mac.
#
# One-time prerequisites (see README "Signing & notarization"):
#   1. Developer ID Application certificate installed in the keychain
#      (make app then signs with it automatically).
#   2. xcrun notarytool store-credentials mdreader-notary \
#        --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# Override the keychain profile name with NOTARY_PROFILE=<name>.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/MDReader.app
PROFILE="${NOTARY_PROFILE:-mdreader-notary}"

[ -d "$APP" ] || { echo "error: $APP missing — run 'make app' first" >&2; exit 1; }

if ! codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
  echo "error: $APP is not signed with a Developer ID identity." >&2
  echo "Install your 'Developer ID Application' certificate, then re-run 'make notarize'." >&2
  exit 1
fi

echo "==> submitting to Apple notary service (usually 1–5 minutes)…"
ditto -c -k --keepParent "$APP" MDReader.zip
xcrun notarytool submit MDReader.zip --keychain-profile "$PROFILE" --wait

echo "==> stapling ticket"
xcrun stapler staple "$APP"

# Re-zip so the distributed archive contains the stapled app.
ditto -c -k --keepParent "$APP" MDReader.zip
shasum -a 256 MDReader.zip | tee MDReader.zip.sha256

echo ""
echo "MDReader.zip is notarized and stapled. To replace a release asset:"
echo "  gh release upload vX.Y.Z MDReader.zip MDReader.zip.sha256 --clobber"
echo "…then update sha256 in the Homebrew cask (homebrew-tap/Casks/mdreader.rb)."
