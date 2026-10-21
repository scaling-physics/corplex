#!/bin/bash
# Builds the macOS release app and packages it as a drag-to-Applications DMG:
#   tool/macos/make_dmg.sh            -> build/dmg/Corplex-<version>.dmg
#   tool/macos/make_dmg.sh --no-build -> package the existing release build
#                                        (it keeps whatever the build had)
#
# Without a Developer ID certificate the app is ad-hoc signed: it runs on the
# Mac that built it, but a copy downloaded elsewhere is blocked by Gatekeeper
# until it is right-clicked → Open (or `xattr -dr com.apple.quarantine`).
# With one, set CODESIGN_IDENTITY="Developer ID Application: …" and the app
# and DMG are signed with it (notarise with `xcrun notarytool` afterwards).
set -euo pipefail
cd "$(dirname "$0")/../.."

# Sync needs the Supabase project's URL and publishable key compiled in; a
# build without them runs offline with a greyed-out "Sync now". They live in
# tool/supabase.env (gitignored, see supabase.env.example).
if [[ "${1:-}" != "--no-build" ]]; then
  env_file="tool/supabase.env"
  [[ -f "$env_file" ]] || {
    echo "Missing $env_file: copy tool/supabase.env.example and fill it in." >&2
    exit 1
  }
  set -a; source "$env_file"; set +a
  [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]] || {
    echo "$env_file must set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY." >&2
    exit 1
  }
  flutter build macos --release \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
fi

app="build/macos/Build/Products/Release/Corplex.app"
[[ -d "$app" ]] || { echo "No release build at $app" >&2; exit 1; }
version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
out="build/dmg"
dmg="$out/Corplex-$version.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$CODESIGN_IDENTITY" "$app"
fi

cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
mkdir -p "$out"
rm -f "$dmg"
hdiutil create -volname "Corplex" -srcfolder "$stage" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$dmg" >/dev/null

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$dmg"
fi

echo "$dmg ($(du -h "$dmg" | cut -f1))"
