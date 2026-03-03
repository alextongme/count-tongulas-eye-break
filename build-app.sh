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
command -v swiftc >/dev/null || fail "swiftc not found (install Xcode Command Line Tools)."

echo ""
echo "  🧛 Building Count Tongula's Eye Break v${VERSION}"
echo "  ─────────────────────────────────────"
echo ""

# ── Clean ──
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Compile ──
info "Compiling ..."
swiftc -O -o "$BUILD_DIR/eye_break_ui" \
    "$REPO_DIR/scripts/Sources/"*.swift \
    -framework Cocoa -framework IOKit 2>&1
ok "Binary compiled"

# ── Build .app bundle ──
info "Building app bundle ..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/assets"

# Copy binary directly (no symlinks — fully standalone)
cp "$BUILD_DIR/eye_break_ui" "$APP_BUNDLE/Contents/MacOS/eye_break_ui"

# Copy assets
cp "$REPO_DIR/assets/dracula.png" "$APP_BUNDLE/Contents/Resources/assets/"
cp "$REPO_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
[ -f "$REPO_DIR/assets/alex.png" ] && cp "$REPO_DIR/assets/alex.png" "$APP_BUNDLE/Contents/Resources/assets/"

# Launcher script that sets up LaunchAgent on first run, then executes the binary
cat > "$APP_BUNDLE/Contents/MacOS/run" <<'LAUNCHER'
#!/bin/bash
BUNDLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$BUNDLE_DIR/MacOS/eye_break_ui"
AGENT_LABEL="com.counttongula.eyebreak"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$AGENT_LABEL.plist"

# Install LaunchAgent on first run (or if plist is missing)
if [ ! -f "$AGENT_PLIST" ]; then
    mkdir -p "$AGENT_DIR"
    cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/eye_break.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/eye_break.log</string>
</dict>
</plist>
EOF
    launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || true
fi

exec "$BINARY"
LAUNCHER
chmod +x "$APP_BUNDLE/Contents/MacOS/run"

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
    <string>run</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
PLIST
ok "App bundle created"

# ── Strip quarantine ──
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# ── Create zip for distribution ──
info "Creating zip ..."
cd "$BUILD_DIR"
ZIP_NAME="CountTongulasEyeBreak-${VERSION}.zip"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
ok "Zip created → dist/$ZIP_NAME"

# ── SHA256 for Cask ──
SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
echo ""
echo "  📦 Distribution files in dist/"
echo "     $ZIP_NAME"
echo "     SHA256: $SHA"
echo ""
echo "  To release:"
echo "     1. Create a GitHub release tagged v${VERSION}"
echo "     2. Upload dist/$ZIP_NAME to the release"
echo "     3. Update the Homebrew Cask with the new URL and SHA"
echo ""
