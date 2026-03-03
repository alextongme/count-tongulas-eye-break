# Count Tongula's Eye Break

**A macOS menu bar app that reminds you to rest your eyes using the 20-20-20 rule.**

Every **20 minutes**, look at something **20 feet** away for **20 seconds**.

<p align="center">
<img src="https://img.shields.io/badge/platform-macOS-bd93f9?style=flat-square" alt="macOS">
<img src="https://img.shields.io/badge/swift-AppKit-ff79c6?style=flat-square" alt="Swift">
<img src="https://img.shields.io/badge/theme-dracula-6272a4?style=flat-square" alt="Dracula">
</p>

<p align="center">
<img src="assets/screenshots/full-screen-fog.png" width="720" alt="Full screen with fog overlay">
</p>

---

## Install

### Homebrew (recommended)

```bash
brew tap alextongme/cask
brew install --cask count-tongulas-eye-break
```

Homebrew will ask for your password during install — this is normal. It's needed to move the app to `/Applications` and clear the macOS Gatekeeper quarantine flag (the app is not code-signed with an Apple Developer certificate). If you see an "Apple could not verify" warning, run:

```bash
sudo xattr -cr "/Applications/Count Tongula's Eye Break.app"
open "/Applications/Count Tongula's Eye Break.app"
```

### From source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/alextongme/count-tongulas-eye-break.git
cd count-tongulas-eye-break
./install.sh
```

### Update

```bash
# Homebrew
brew update && brew upgrade count-tongulas-eye-break

# From source
git pull && ./install.sh
```

### Uninstall

```bash
# Homebrew
brew uninstall count-tongulas-eye-break

# From source
./uninstall.sh
```

---

## Features

- **Menu bar app** -- 🦇 icon with live countdown to your next break
- **Dracula theme** -- native AppKit UI styled with the [Dracula](https://draculatheme.com) color palette
- **Vampire quotes** -- random Bram Stoker-inspired quotes during breaks
- **Smart timer** -- pauses when your screen is locked, Mac sleeps, or Focus/DND is active
- **Idle detection** -- resets the timer when you're already away from the keyboard
- **Long breaks** -- every N eye breaks, triggers a longer stretch break
- **Multi-monitor** -- dims all connected screens during breaks
- **Cloud overlay** -- animated fog drifts across your screen during breaks
- **Configurable** -- adjust intervals, durations, sounds, and behavior from Settings
- **Sound customization** -- 14 macOS system sounds with live preview
- **Strict mode** -- disable skip and snooze to stay disciplined
- **Global shortcuts** -- trigger a break or pause from anywhere
- **Statistics** -- streak tracking with vampire-themed milestone titles
- **Pre-break notifications** -- get a heads-up before breaks start
- **Launch at login** -- runs automatically via macOS LaunchAgent

---

## Screenshots

<p align="center">
<img src="assets/screenshots/full-screen-fog.png" width="720" alt="Full screen with fog overlay">
</p>
<p align="center"><em>Fog overlay dims your screen during a break</em></p>

<p align="center">
<img src="assets/screenshots/all-01-onboarding.png" width="400" alt="Onboarding">
</p>
<p align="center"><em>First-run onboarding</em></p>

<p align="center">
<img src="assets/screenshots/all-03-eye-prompt.png" width="360" alt="Eye break prompt">
<img src="assets/screenshots/all-05-eye-complete.png" width="360" alt="Eye break complete">
</p>
<p align="center"><em>Eye break prompt and completion</em></p>

<p align="center">
<img src="assets/screenshots/all-06-long-prompt.png" width="360" alt="Long break prompt">
<img src="assets/screenshots/all-07-long-countdown.png" width="360" alt="Long break countdown">
</p>
<p align="center"><em>Long stretch break</em></p>

<p align="center">
<img src="assets/screenshots/all-02-settings.png" width="520" alt="Settings">
</p>
<p align="center"><em>Settings</em></p>

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + Shift + B` | Take a break now |
| `Cmd + Shift + P` | Pause / resume timer |
| `Esc` | Skip break (during countdown) |
| `Enter` | Dismiss (on completion screen) |

## Configuration

Open **Settings** from the menu bar dropdown.

| Section | Setting | Default |
|---------|---------|---------|
| **Timing** | Break interval | 20 min |
| | Break duration | 20 sec |
| | Snooze duration | 5 min |
| **Sounds** | Prompt sound | Sosumi |
| | Complete sound | Blow |
| **Behavior** | Pause during DND | On |
| | Detect inactivity | On |
| | Dim screens on break | On |
| | Cloud effect on break | On |
| | Launch at login | On |
| | Strict mode (no skip/snooze) | Off |
| | Pause for meetings/presentations | On |
| | Notify before break | On |
| **Long Breaks** | Enabled | On |
| | Frequency | Every 3 eye breaks |
| | Duration | 5 min |

All settings persist via `UserDefaults` and take effect immediately.

## Statistics

Count Tongula tracks your devotion. Stats are stored in `~/Library/Application Support/CountTongula/statistics.json` and retained for 30 days.

- Breaks completed, skipped, and snoozed per day
- Approval rating (completed / total)
- Streak tracking with milestone titles:

| Streak | Title |
|--------|-------|
| 5 | Familiar |
| 10 | Servant of the Night |
| 25 | Thrall |
| 50 | Considered for Immortality |
| 100 | Order of Count Tongula |

---

## Development

### Architecture

Single binary compiled from `scripts/Sources/*.swift` using SwiftPM. Depends on [Lottie](https://github.com/airbnb/lottie-ios) for animations.

```
scripts/Sources/*.swift  -->  eye_break_ui (single binary, SwiftPM)
                              |
                              +-- NSStatusItem (menu bar + countdown)
                              +-- BreakWindowController (eye + long breaks)
                              +-- SettingsWindowController (two-column prefs)
                              +-- OnboardingController (first-run setup)
                              +-- IdleDetector (CGEventSource, IOKit, DND)
                              +-- Statistics (JSON persistence, streaks)
                              +-- SoundManager (14 macOS system sounds)
                              +-- Preferences (UserDefaults)
```

### Releasing

Tag a version and push — GitHub Actions builds the `.app`, creates a GitHub Release, and updates the Homebrew Cask formula automatically.

```bash
git tag v0.3.0
git push --tags
```

**One-time setup:** add a `CASK_PAT` [repository secret](https://github.com/alextongme/count-tongulas-eye-break/settings/secrets/actions) with write access to `alextongme/homebrew-cask`. Create one at [GitHub fine-grained tokens](https://github.com/settings/tokens?type=beta).

### Requirements

- macOS 12+ (Monterey or later)
- Xcode Command Line Tools (for building from source only)

## License

MIT
