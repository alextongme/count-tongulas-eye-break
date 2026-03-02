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

ok()   { echo "  ✅ $1"; }
info() { echo "  🦇 $1"; }
fail() { echo "  ❌ $1" >&2; exit 1; }

# ── Preflight ──
[[ "$(uname)" == "Darwin" ]] || fail "This only works on macOS."
command -v osascript >/dev/null || fail "osascript not found."
command -v python3 >/dev/null || fail "python3 not found."

echo ""
echo "  🧛 Count Tongula's Eye Break Reminder"
echo "  ─────────────────────────────────────"
echo ""

# ── Symlink scripts (git pull = instant update) ──
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
info "Symlinking to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
for script in "$REPO_DIR/scripts/"*.sh; do
    target="$INSTALL_DIR/$(basename "$script")"
    rm -f "$target"
    ln -s "$script" "$target"
done
ok "Scripts symlinked → $REPO_DIR/scripts/"

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
        <string>$INSTALL_DIR/eye_break_daemon.sh</string>
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
