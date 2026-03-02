#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Count Tongula's Eye Break Reminder
#  Uninstaller
# ─────────────────────────────────────────────

INSTALL_DIR="$HOME/.eye-break"
AGENT_LABEL="com.counttongula.eyebreak"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

echo ""
echo "  🧛 Uninstalling Count Tongula's Eye Break Reminder..."
echo ""

# ── Stop and remove LaunchAgent ──
launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || true
rm -f "$AGENT_PLIST"
echo "  ✅ LaunchAgent removed"

# ── Remove scripts ──
rm -rf "$INSTALL_DIR"
echo "  ✅ Scripts removed"

echo ""
echo "  🦇 Count Tongula bids you farewell... for now."
echo ""
