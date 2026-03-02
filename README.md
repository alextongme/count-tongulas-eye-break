# 🧛 Count Tongula's Eye Break Reminder

**A macOS daemon that reminds you to rest your eyes every 20 minutes of active screen time.**

Follows the [20-20-20 rule](https://www.healthline.com/health/eye-health/20-20-20-rule): every **20 minutes**, look at something **20 feet** away for **20 seconds**.

<p align="center">
<img src="https://img.shields.io/badge/platform-macOS-bd93f9?style=flat-square" alt="macOS">
<img src="https://img.shields.io/badge/shell-bash-ff79c6?style=flat-square" alt="Bash">
<img src="https://img.shields.io/badge/theme-dracula-6272a4?style=flat-square" alt="Dracula">
</p>

---

## Features

- **Smart timer** — only counts active screen time; pauses when your screen is locked or your Mac sleeps
- **Native macOS dialogs** — no extra dependencies, uses AppleScript
- **Snooze support** — not ready? Snooze for 5 minutes
- **Guided countdown** — 20-second countdown keeps you on track
- **Sound alerts** — gentle chime when it's break time, purr when you're done
- **Runs at login** — installs as a macOS LaunchAgent

## Install

```bash
git clone https://github.com/alextongme/eye-break-reminder.git
cd eye-break-reminder
./install.sh
```

That's it. Count Tongula will start watching over your eyes immediately and on every login.

Scripts are symlinked, so pulling updates takes effect immediately:

```bash
cd eye-break-reminder
git pull
```

## Uninstall

```bash
cd eye-break-reminder
./uninstall.sh
```

## How It Works

```
eye_break_daemon.sh          eye_break.sh
┌─────────────────────┐      ┌─────────────────────────┐
│ Polls every 30s     │      │ 🧛 "Rest your eyes!"    │
│ Tracks active time  │─────>│ [Snooze] [Start Break]  │
│ Pauses when locked  │      │                         │
│ Resets after sleep   │      │ 👁 20s countdown        │
└─────────────────────┘      │ 🦇 "Break complete!"    │
                             └─────────────────────────┘
```

**Daemon** (`eye_break_daemon.sh`):
- Polls every 30 seconds to check if the screen is locked
- Accumulates active screen time
- Resets the timer after sleep or screen unlock
- Triggers the break dialog every 20 minutes of active use

**Break dialog** (`eye_break.sh`):
- Plays a sound to get your attention
- Shows a native macOS dialog with snooze option
- Runs a 20-second guided countdown
- Plays a completion sound when done

## Requirements

- macOS (uses AppleScript + `launchctl`)
- Python 3 (pre-installed on modern macOS, used for screen lock detection)

## License

MIT
