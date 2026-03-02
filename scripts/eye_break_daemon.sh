#!/bin/bash
# Count Tongula's Eye Break Daemon
# Alerts every 20 minutes of active screen time.
# Pauses the timer when the screen is locked or the system sleeps.

INTERVAL=1200       # 20 minutes
CHECK_INTERVAL=30   # poll every 30 seconds

# Resolve the directory this script lives in
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

is_screen_locked() {
    python3 -c "
import subprocess, plistlib, sys
out = subprocess.check_output(['ioreg', '-n', 'Root', '-d1', '-a'])
d = plistlib.loads(out)
sys.exit(0 if d.get('IOConsoleLocked', False) else 1)
" 2>/dev/null
}

elapsed=0
last_check=$(date +%s)
was_locked=false

while true; do
    sleep $CHECK_INTERVAL
    now=$(date +%s)
    wall_elapsed=$((now - last_check))
    last_check=$now

    # Wall clock jumped well past the poll window -> system was asleep
    if [ $wall_elapsed -gt $((CHECK_INTERVAL + 60)) ]; then
        elapsed=0
        was_locked=false
        continue
    fi

    if is_screen_locked; then
        was_locked=true
        continue
    fi

    # Just unlocked — reset so the full interval starts from now
    if $was_locked; then
        elapsed=0
        was_locked=false
        continue
    fi

    elapsed=$((elapsed + wall_elapsed))

    if [ $elapsed -ge $INTERVAL ]; then
        "$SCRIPT_DIR/eye_break.sh"
        elapsed=0
    fi
done
