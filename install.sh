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
command -v python3 >/dev/null || fail "python3 not found."
command -v swiftc  >/dev/null || fail "swiftc not found (install Xcode Command Line Tools)."

echo ""
echo "  🧛 Count Tongula's Eye Break Reminder"
echo "  ─────────────────────────────────────"
echo ""

# ── Compile Swift UI ──
info "Compiling Dracula UI ..."
swiftc -O -o "$REPO_DIR/scripts/eye_break_ui" "$REPO_DIR/scripts/eye_break_ui.swift" \
    -framework Cocoa 2>&1
ok "Binary compiled"

# ── Install scripts ──
info "Installing to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
# Copy shell scripts (copies avoid macOS TCC/provenance issues with symlinks)
for script in "$REPO_DIR/scripts/"*.sh; do
    target="$INSTALL_DIR/$(basename "$script")"
    rm -f "$target"
    cp "$script" "$target"
done
# Symlink the compiled binary
rm -f "$INSTALL_DIR/eye_break_ui"
ln -s "$REPO_DIR/scripts/eye_break_ui" "$INSTALL_DIR/eye_break_ui"
# Strip macOS quarantine/provenance attributes
xattr -cr "$INSTALL_DIR" 2>/dev/null || true
ok "Scripts installed → $INSTALL_DIR"

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

# Launcher script inside the .app
cat > "$APP_BUNDLE/Contents/MacOS/run" <<'LAUNCHER'
#!/bin/bash
SCRIPT_DIR="$HOME/.eye-break"
exec "$SCRIPT_DIR/eye_break_daemon.sh"
LAUNCHER
chmod +x "$APP_BUNDLE/Contents/MacOS/run"

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
    <string>run</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
ok "App bundle created"

# ── Create LaunchAgent ──
info "Setting up LaunchAgent ..."
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
        <string>$APP_BUNDLE/Contents/MacOS/run</string>
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
ok "LaunchAgent created"

# ── Load the daemon ──
info "Loading daemon ..."
launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
ok "Daemon loaded"

echo ""
echo "  🦇 Count Tongula will remind you to rest your eyes"
echo "     every 20 minutes of screen time."
echo ""
echo "  To uninstall:  ./uninstall.sh"
echo ""
