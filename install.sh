#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Count Tongula's Eye Break Reminder
#  Installer for macOS
# ─────────────────────────────────────────────

INSTALL_DIR="$HOME/.eye-break"
AGENT_LABEL="com.counttongula.eyebreak"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$AGENT_LABEL.plist"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Count Tongula's Eye Break"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

ok()   { echo "  ✅ $1"; }
info() { echo "  🦇 $1"; }
fail() { echo "  ❌ $1" >&2; exit 1; }

# ── Preflight ──
[[ "$(uname)" == "Darwin" ]] || fail "This only works on macOS."
command -v swift >/dev/null || fail "swift not found (install Xcode Command Line Tools)."

echo ""
echo "  🧛 Count Tongula's Eye Break Reminder"
echo "  ─────────────────────────────────────"
echo ""

# ── Compile Swift UI ──
info "Compiling Dracula UI (Swift Package Manager) ..."
swift build -c release --package-path "$REPO_DIR" 2>&1
ok "Binary compiled"

# ── Install binary + assets ──
info "Installing to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
# Symlink the compiled binary
rm -f "$INSTALL_DIR/eye_break_ui"
ln -s "$REPO_DIR/.build/release/eye_break_ui" "$INSTALL_DIR/eye_break_ui"
# Strip macOS quarantine/provenance attributes
xattr -cr "$INSTALL_DIR" 2>/dev/null || true
ok "Binary installed → $INSTALL_DIR"

# ── Symlink assets ──
info "Symlinking assets ..."
rm -rf "$INSTALL_DIR/assets"
ln -s "$REPO_DIR/assets" "$INSTALL_DIR/assets"
ok "Assets symlinked → $REPO_DIR/assets/"

# ── Build .app bundle (for Login Items name + icon) ──
info "Building app bundle ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Symlink binary into the .app bundle
ln -sf "$INSTALL_DIR/eye_break_ui" "$APP_BUNDLE/Contents/MacOS/eye_break_ui"

# Copy icon
cp "$REPO_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

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
    <string>$AGENT_LABEL</string>
    <key>CFBundleExecutable</key>
    <string>eye_break_ui</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
ok "App bundle created"

echo ""
echo "  🦇 Count Tongula will remind you to rest your eyes."
echo "     Menu bar icon: 🦇 with countdown timer."
echo "     Keyboard shortcuts: Cmd+Shift+B (break now), Cmd+Shift+P (pause)."
echo ""
echo "  To uninstall:  ./uninstall.sh"
echo ""
