#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Build a standalone .app bundle for distribution
#  (Homebrew Cask, GitHub Releases, etc.)
# ─────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Count Tongula's Eye Break"
BUNDLE_ID="com.counttongula.eyebreak"
VERSION="${1:-0.1.0}"
BUILD_DIR="$REPO_DIR/dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

ok()   { echo "  ✅ $1"; }
info() { echo "  🦇 $1"; }
fail() { echo "  ❌ $1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "This only works on macOS."
command -v swift >/dev/null || fail "swift not found (install Xcode Command Line Tools)."

echo ""
echo "  🧛 Building Count Tongula's Eye Break v${VERSION}"
echo "  ─────────────────────────────────────"
echo ""

# ── Clean ──
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Compile universal binary (arm64 + x86_64) ──
info "Compiling arm64 ..."
swift build -c release --arch arm64 --package-path "$REPO_DIR" 2>&1
ok "arm64 compiled"

info "Compiling x86_64 ..."
swift build -c release --arch x86_64 --package-path "$REPO_DIR" 2>&1
ok "x86_64 compiled"

info "Creating universal binary ..."
lipo -create \
    "$REPO_DIR/.build/arm64-apple-macosx/release/eye_break_ui" \
    "$REPO_DIR/.build/x86_64-apple-macosx/release/eye_break_ui" \
    -output "$BUILD_DIR/eye_break_ui"
ok "Universal binary created"

# ── Build .app bundle ──
info "Building app bundle ..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/assets"

# Copy binary directly (no symlinks — fully standalone)
cp "$BUILD_DIR/eye_break_ui" "$APP_BUNDLE/Contents/MacOS/eye_break_ui"

# Embed Sparkle framework
SPARKLE_FW="$REPO_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
# Set rpath so the binary finds the embedded framework
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/eye_break_ui"

# Copy assets
cp "$REPO_DIR/assets/alex_final.png" "$APP_BUNDLE/Contents/Resources/assets/"
cp "$REPO_DIR/assets/dracula.png" "$APP_BUNDLE/Contents/Resources/assets/"
[ -f "$REPO_DIR/assets/clouds.png" ] && cp "$REPO_DIR/assets/clouds.png" "$APP_BUNDLE/Contents/Resources/assets/"
cp "$REPO_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy Lottie animations
if [ -d "$REPO_DIR/assets/animations" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/assets/animations"
    cp "$REPO_DIR/assets/animations/"*.json "$APP_BUNDLE/Contents/Resources/assets/animations/"
fi

# Copy fonts
mkdir -p "$APP_BUNDLE/Contents/Resources/assets/fonts"
cp "$REPO_DIR/assets/fonts/"*.ttf "$APP_BUNDLE/Contents/Resources/assets/fonts/"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>eye_break_ui</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/alextongme/count-tongulas-eye-break/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>mMeJeZNu41QLWirdyTD43i5H8PayL6JxP+McRHmkwgY=</string>
</dict>
</plist>
PLIST
ok "App bundle created"

# ── Code sign with Developer ID ──
SIGN_IDENTITY="Developer ID Application: Alexander Tong (VFHH4742PD)"
info "Code signing with Developer ID ..."
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
ok "Signed with Developer ID"

# ── Create zip for distribution ──
info "Creating zip ..."
cd "$BUILD_DIR"
ZIP_NAME="CountTongulasEyeBreak-${VERSION}.zip"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
ok "Zip created → dist/$ZIP_NAME"

# ── Create DMG for distribution ──
info "Creating DMG ..."
DMG_NAME="CountTongulasEyeBreak-${VERSION}.dmg"
DMG_TEMP="$BUILD_DIR/dmg_staging"
mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"
hdiutil create -volname "Count Tongula's Eye Break" \
    -srcfolder "$DMG_TEMP" -ov -format UDZO \
    "$BUILD_DIR/$DMG_NAME"
cp "$BUILD_DIR/$DMG_NAME" "$BUILD_DIR/CountTongulasEyeBreak.dmg"
rm -rf "$DMG_TEMP"
ok "DMG created → dist/$DMG_NAME"
ok "DMG copied → dist/CountTongulasEyeBreak.dmg (stable download URL)"

# ── Sparkle EdDSA signature ──
SIGN_TOOL="$REPO_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
info "Signing archive for Sparkle ..."
SPARKLE_SIG=$("$SIGN_TOOL" "$BUILD_DIR/$DMG_NAME" 2>&1)
ok "Sparkle signature generated"

# Parse signature components
ED_SIGNATURE=$(echo "$SPARKLE_SIG" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
FILE_LENGTH=$(echo "$SPARKLE_SIG" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -R)
DOWNLOAD_URL="https://github.com/alextongme/count-tongulas-eye-break/releases/download/v${VERSION}/${DMG_NAME}"

# ── Update appcast.xml ──
info "Updating appcast.xml ..."
APPCAST="$REPO_DIR/appcast.xml"
cat > "$APPCAST" <<APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Count Tongula's Eye Break</title>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${FILE_LENGTH}"
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
APPCAST_EOF
ok "appcast.xml updated"

# ── SHA256 for Cask ──
SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
DMG_SHA=$(shasum -a 256 "$DMG_NAME" | awk '{print $1}')
echo ""
echo "  📦 Distribution files in dist/"
echo "     $ZIP_NAME"
echo "     SHA256: $SHA"
echo "     $DMG_NAME"
echo "     SHA256: $DMG_SHA"
echo ""
echo "  To release:"
echo "     1. Create a GitHub release tagged v${VERSION}"
echo "     2. Upload dist/$ZIP_NAME and dist/$DMG_NAME to the release"
echo "     3. Commit and push appcast.xml (Sparkle auto-update feed)"
echo "     4. Update the Homebrew Cask with the new URL and SHA"
echo ""
