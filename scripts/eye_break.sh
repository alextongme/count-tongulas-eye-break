#!/bin/bash
# Count Tongula's Eye Break Reminder
# Shows a macOS dialog reminding you to rest your eyes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

osascript <<'APPLESCRIPT'
do shell script "afplay /System/Library/Sounds/Glass.aiff &"

set userChoice to button returned of (display dialog "🧛 Count Tongula commands you: Rest your eyes!" & return & return & "Look at something 20 feet away for 20 seconds." with title "Count Tongula's Eye Break" buttons {"Snooze 5 min", "Start Break"} default button "Start Break")

if userChoice is "Snooze 5 min" then
    delay 300
    do shell script "afplay /System/Library/Sounds/Glass.aiff &"
    display dialog "🧛 Your snooze has expired, mortal! Time to rest your eyes." with title "Count Tongula's Eye Break" buttons {"Start Break"} default button "Start Break"
end if

-- Countdown via auto-dismissing dialogs
repeat with i from 4 to 1 by -1
    set secs to i * 5
    display dialog "👁 Gaze into the distance, mortal!" & return & return & "🦇  " & secs & " seconds remaining  🦇" with title "Count Tongula's Eye Break" buttons {"Looking away..."} default button 1 giving up after 5
end repeat

do shell script "afplay /System/Library/Sounds/Purr.aiff &"
display dialog "🦇 Break complete! Count Tongula is pleased." & return & "You may return to your screen." with title "Count Tongula's Eye Break" buttons {"Thanks, Count!"} default button "Thanks, Count!" giving up after 5
APPLESCRIPT
