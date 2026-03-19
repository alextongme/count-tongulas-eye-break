import Cocoa
import Sparkle
// UserNotifications removed — triggers mic permission prompt on macOS 26
// and crashes without a proper bundle proxy. The app shows its own break
// window and plays sounds via NSSound, so push notifications aren't needed.

class AppDelegate: NSObject, NSApplicationDelegate, BreakWindowDelegate, NSMenuDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Properties

    var statusItem: NSStatusItem!

    var breakTimer: Timer?
    var secondsUntilBreak: Int = 0
    var isPaused = false
    var eyeBreaksSinceLastLong = 0
    var snoozedThisBreak = false
    var snoozeTimer: Timer?

    var breakController: BreakWindowController?
    var settingsController: SettingsWindowController?
    var onboardingController: OnboardingController?
    var statsChartController: StatsChartWindowController?
    var remindersController: RemindersWindowController?
    var reminderWindowController: ReminderWindowController?
    var updaterController: SPUStandardUpdaterController!
    var reminderCheckTimer: Timer?

    private var lastTickWasSpecial = false

    var countdownMenuItem: NSMenuItem!
    var statsMenuItem: NSMenuItem!
    var streakMenuItem: NSMenuItem!
    var pauseMenuItem: NSMenuItem!
    var approvalMenuItem: NSMenuItem!

    // Menu items that open windows (disabled when another window is already open)
    var historyMenuItem: NSMenuItem!
    var remindersMenuItem: NSMenuItem!
    var settingsMenuItem: NSMenuItem!
    var skipMenuItem: NSMenuItem!
    var bugMenuItem: NSMenuItem!
    var featureMenuItem: NSMenuItem!

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerCustomFonts()
        removeLegacyLaunchAgent()
        setupStatusItem()
        buildMenu()
        startIdleDetector()


        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: Preferences.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingDidComplete),
            name: OnboardingController.didCompleteNotification,
            object: nil
        )


        // Only auto-check for updates when running from a real .app bundle
        // (not a dev symlink install where Sparkle can't verify signatures).
        let isAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isAppBundle,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        if !Preferences.shared.hasCompletedOnboarding {
            showOnboarding()
        } else {
            startTimer()
        }

        startReminderChecker()
    }

    // MARK: - Reminder Checker

    func startReminderChecker() {
        reminderCheckTimer?.invalidate()
        reminderCheckTimer = Timer.scheduledTimer(
            timeInterval: 30.0,
            target: self,
            selector: #selector(checkReminders),
            userInfo: nil,
            repeats: true
        )
    }

    @objc func checkReminders() {
        ReminderStore.shared.cleanFiredCache()
        let due = ReminderStore.shared.dueReminders()
        guard let reminder = due.first else { return }
        // Don't show if another window is blocking
        guard !hasOpenWindow else { return }

        ReminderStore.shared.markFired(reminder)

        let controller = ReminderWindowController(reminder: reminder)
        controller.onDismiss = { [weak self] in
            self?.reminderWindowController = nil
            // Fire next due reminder if any
            let remaining = due.dropFirst()
            for r in remaining {
                ReminderStore.shared.markFired(r)
            }
        }
        reminderWindowController = controller
    }

    // MARK: - Status Item

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🦇"
            button.toolTip = "Count Tongula's Eye Break"
        }
    }

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()

        countdownMenuItem = menuItem("Next break in --:--", emoji: "⏳")
        countdownMenuItem.isEnabled = false
        menu.addItem(countdownMenuItem)

        menu.addItem(NSMenuItem.separator())

        statsMenuItem = menuItem(Statistics.shared.todaySummary(), emoji: "👁")
        statsMenuItem.isEnabled = false
        menu.addItem(statsMenuItem)

        streakMenuItem = menuItem("Streak: \(Statistics.shared.currentStreak) breaks", emoji: "🔥")
        streakMenuItem.isEnabled = false
        menu.addItem(streakMenuItem)

        approvalMenuItem = menuItem("Approval rating: \(Statistics.shared.approvalRating)%", emoji: "📊")
        approvalMenuItem.isEnabled = false
        menu.addItem(approvalMenuItem)

        historyMenuItem = menuItem("View History...", emoji: "📈", action: #selector(showHistory))
        menu.addItem(historyMenuItem)

        menu.addItem(NSMenuItem.separator())

        pauseMenuItem = menuItem("Pause", emoji: "⏸️", action: #selector(togglePause))
        menu.addItem(pauseMenuItem)

        skipMenuItem = menuItem("Take a Break Now", emoji: "👁", action: #selector(skipToBreak))
        menu.addItem(skipMenuItem)

        menu.addItem(NSMenuItem.separator())

        remindersMenuItem = menuItem("Reminders...", emoji: "🔔", action: #selector(showReminders))
        menu.addItem(remindersMenuItem)

        settingsMenuItem = menuItem("Settings...", emoji: "⚙️", action: #selector(showSettings))
        menu.addItem(settingsMenuItem)

        menu.addItem(menuItem("Check for Updates...", emoji: "🔄", action: #selector(checkForUpdates)))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem("Visit alextong.me", emoji: "🌐", action: #selector(openWebsite)))
        menu.addItem(menuItem("Listen to my music", emoji: "🎵", action: #selector(openMusic)))
        menu.addItem(menuItem("Buy me a coffee", emoji: "☕", action: #selector(openDonate)))
        bugMenuItem = menuItem("Report a bug", emoji: "🐛", action: #selector(reportBug))
        menu.addItem(bugMenuItem)
        featureMenuItem = menuItem("Request a feature", emoji: "💡", action: #selector(requestFeature))
        menu.addItem(featureMenuItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem("Quit Count Tongula", emoji: "👋", action: #selector(quitApp)))

        menu.delegate = self
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, emoji: String? = nil, action: Selector? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if action != nil { item.target = self }
        if let emoji = emoji {
            item.image = emojiImage(emoji)
        }
        return item
    }

    private func emojiImage(_ emoji: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let str = NSAttributedString(string: emoji, attributes: attrs)
        let textSize = str.size()
        let imgSize = NSSize(width: 18, height: 18)
        let img = NSImage(size: imgSize)
        img.lockFocus()
        let x = (imgSize.width - textSize.width) / 2
        let y = (imgSize.height - textSize.height) / 2
        str.draw(at: NSPoint(x: x, y: y))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    func updateMenuStats() {
        statsMenuItem.title = Statistics.shared.todaySummary()
        streakMenuItem.title = "Streak: \(Statistics.shared.currentStreak) breaks"
        approvalMenuItem.title = "Approval rating: \(Statistics.shared.approvalRating)%"
    }

    // MARK: - NSMenuDelegate

    /// Returns true if any managed window (break, settings, history, feedback) is currently visible.
    private var hasOpenWindow: Bool {
        if breakController != nil { return true }
        if reminderWindowController != nil { return true }
        if let w = settingsController?.window, w.isVisible { return true }
        if let w = statsChartController?.window, w.isVisible { return true }
        if let w = remindersController?.window, w.isVisible { return true }
        if let w = feedbackController?.window, w.isVisible { return true }
        if let w = onboardingController?.window, w.isVisible { return true }
        // Sparkle manages its own update windows
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Force a fresh countdown so throttled values don't appear stale.
        // Skip during snooze — the snooze timer manages its own display.
        if !isPaused && !IdleDetector.shared.shouldDeferBreak && snoozeTimer == nil {
            updateStatusDisplay()
        }
        let blocked = hasOpenWindow
        historyMenuItem?.isEnabled = !blocked
        remindersMenuItem?.isEnabled = !blocked
        settingsMenuItem?.isEnabled = !blocked
        skipMenuItem?.isEnabled = !blocked
        bugMenuItem?.isEnabled = !blocked
        featureMenuItem?.isEnabled = !blocked
    }

    // MARK: - Idle Detector

    func startIdleDetector() {
        IdleDetector.shared.startMonitoring()
    }

    // MARK: - Timer Management

    func startTimer() {
        breakTimer?.invalidate()

        secondsUntilBreak = Preferences.shared.breakInterval
        breakTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        updateStatusDisplay()
    }

    @objc func tick() {
        // Guard redundant status bar title sets in special-state paths to avoid
        // unnecessary WindowServer redraws (the main cause of compositor stutter
        // during macOS space-switching animations).

        if isPaused {
            if let button = statusItem.button, button.title != "🦇 Paused" {
                button.title = "🦇 Paused"
            }
            if countdownMenuItem.title != "Paused — timer stopped" {
                countdownMenuItem.title = "Paused — timer stopped"
                countdownMenuItem.image = emojiImage("⏸️")
            }
            lastTickWasSpecial = true
            return
        }

        if IdleDetector.shared.shouldDeferBreak {
            if let button = statusItem.button, button.title != "🦇 Deferred" {
                button.title = "🦇 Deferred"
            }
            if countdownMenuItem.title != "Deferred — DND or screen locked" {
                countdownMenuItem.title = "Deferred — DND or screen locked"
                countdownMenuItem.image = emojiImage("🔒")
            }
            lastTickWasSpecial = true
            return
        }

        if IdleDetector.shared.isUserIdle {
            // User is already resting; reset the timer as a natural break
            secondsUntilBreak = Preferences.shared.breakInterval
    
            updateStatusDisplay()
            lastTickWasSpecial = true
            return
        }

        // App exclusion: pause timer while excluded app is frontmost
        if Preferences.shared.appExclusionEnabled && isExcludedAppFrontmost() {
            if let button = statusItem.button, button.title != "🦇 Excluded" {
                button.title = "🦇 Excluded"
            }
            if countdownMenuItem.title != "Excluded — app in focus" {
                countdownMenuItem.title = "Excluded — app in focus"
                countdownMenuItem.image = emojiImage("🚫")
            }
            lastTickWasSpecial = true
            return
        }

        secondsUntilBreak -= 1
        lastTickWasSpecial = false
        updateStatusDisplay()

        // Pre-break notification: NSUserNotification removed — it triggers the
        // mic permission prompt on macOS 26 (same underlying system as UNUserNotificationCenter).
        // The app already shows its own break window as the notification.

        if secondsUntilBreak <= 0 {
            triggerBreak()
        }
    }

    func updateStatusDisplay() {
        let timeStr = formatTime(secondsUntilBreak)
        let icon = (secondsUntilBreak <= 30 && secondsUntilBreak > 0)
            ? (secondsUntilBreak % 2 == 0 ? "🦇" : "👁")
            : "🦇"

        if let button = statusItem.button {
            let fullStr = NSMutableAttributedString()
            let emojiAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12)
            ]
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .baselineOffset: 0.5
            ]
            fullStr.append(NSAttributedString(string: "\(icon) ", attributes: emojiAttrs))
            fullStr.append(NSAttributedString(string: timeStr, attributes: textAttrs))
            button.attributedTitle = fullStr
        }
        let newMenu = "Next break in \(timeStr)"
        if countdownMenuItem.title != newMenu {
            countdownMenuItem.title = newMenu
        }
        countdownMenuItem.image = emojiImage("⏳")
    }

    func triggerBreak() {
        breakTimer?.invalidate()
        breakTimer = nil


        let prefs = Preferences.shared
        let breakType: BreakType
        if prefs.longBreakEnabled && eyeBreaksSinceLastLong >= prefs.longBreakEveryN {
            breakType = .long
            eyeBreaksSinceLastLong = 0
        } else {
            breakType = .eye
        }

        let controller = BreakWindowController(type: breakType, allowSnooze: !snoozedThisBreak)
        controller.delegate = self
        breakController = controller

        SoundManager.shared.playPromptSound()
    }

    // MARK: - BreakWindowDelegate

    func breakDidFinish(type: BreakType, result: BreakResult) {
        switch result {
        case .completed:
            Statistics.shared.recordBreakCompleted()
            if type == .eye {
                eyeBreaksSinceLastLong += 1
            }
            snoozedThisBreak = false
            if let msg = Statistics.shared.streakMessage() {
                streakMenuItem.title = msg
            }

        case .skipped:
            Statistics.shared.recordBreakSkipped()
            snoozedThisBreak = false

        case .snoozed:
            Statistics.shared.recordBreakSnoozed()
            snoozedThisBreak = true

            snoozeTimer?.invalidate()
            let snoozeSecs = Preferences.shared.snoozeDuration
            var snoozeRemaining = snoozeSecs

            if let button = statusItem.button {
                button.title = "🦇 \(formatTime(snoozeRemaining))"
            }
            countdownMenuItem.title = "Snoozed — \(formatTime(snoozeRemaining))"
            countdownMenuItem.image = emojiImage("💤")

            snoozeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                snoozeRemaining -= 1
                let timeStr = self.formatTime(snoozeRemaining)
                if let button = self.statusItem.button {
                    button.title = "🦇 \(timeStr)"
                }
                self.countdownMenuItem.title = "Snoozed — \(timeStr)"
                if snoozeRemaining <= 0 {
                    timer.invalidate()
                    self.snoozeTimer = nil
                    self.triggerBreak()
                }
            }
        }

        breakController = nil

        if result != .snoozed {
            secondsUntilBreak = Preferences.shared.breakInterval
            startTimer()
        }

        updateMenuStats()
    }

    // MARK: - Menu Actions

    @objc func togglePause() {
        isPaused = !isPaused
        pauseMenuItem.title = isPaused ? "Resume" : "Pause"
        pauseMenuItem.image = emojiImage(isPaused ? "▶️" : "⏸️")
        if isPaused {
            if let button = statusItem.button {
                button.title = "⏸️ Paused"
            }
            countdownMenuItem.title = "Paused"
        } else {
            updateStatusDisplay()
        }
    }

    @objc func skipToBreak() {
        secondsUntilBreak = 0
        triggerBreak()
    }

    @objc func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        onboardingController = OnboardingController()
        onboardingController?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showHistory() {
        if statsChartController == nil {
            statsChartController = StatsChartWindowController()
        }
        statsChartController?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showReminders() {
        if remindersController == nil {
            remindersController = RemindersWindowController()
        }
        remindersController?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://alextong.me")!)
    }

    @objc func openMusic() {
        NSWorkspace.shared.open(URL(string: "https://suimamusic.com")!)
    }

    @objc func openDonate() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/XLd2bzbViZ")!)
    }

    var feedbackController: FeedbackWindowController?

    @objc func reportBug() {
        feedbackController = FeedbackWindowController(mode: .bug)
    }

    @objc func requestFeature() {
        feedbackController = FeedbackWindowController(mode: .feature)
    }

    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc func quitApp() {
        IdleDetector.shared.stopMonitoring()
        NSApp.terminate(nil)
    }

    // MARK: - Notification Handlers

    @objc func preferencesDidChange() {
        let newInterval = Preferences.shared.breakInterval
        if secondsUntilBreak > newInterval {
            secondsUntilBreak = newInterval
            updateStatusDisplay()
        }
    }

    @objc func onboardingDidComplete() {
        onboardingController = nil
        if breakTimer == nil {
            startTimer()
        }
    }

    // MARK: - Legacy LaunchAgent Cleanup

    /// Older versions installed a LaunchAgent plist to handle launch-at-login.
    /// Now that install.sh launches via the .app bundle, macOS Login Items handles
    /// this natively. Remove the old plist so users don't see a duplicate entry.
    private func removeLegacyLaunchAgent() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plistPath = home.appendingPathComponent("Library/LaunchAgents/com.counttongula.eyebreak.plist")
        guard FileManager.default.fileExists(atPath: plistPath.path) else { return }

        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(uid)", plistPath.path]
        try? task.run()
        task.waitUntilExit()

        try? FileManager.default.removeItem(at: plistPath)
    }

    // MARK: - Helpers

    func formatTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    // MARK: - App Exclusion (cached)

    private var cachedExcludedBundleID: String?
    private var lastExclusionCheck: TimeInterval = 0

    /// Checks frontmost app against exclusion list, caching the result for 2 seconds
    /// to avoid IPC to NSWorkspace on every 1-second tick.
    func isExcludedAppFrontmost() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastExclusionCheck > 2 {
            lastExclusionCheck = now
            cachedExcludedBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        guard let bundleID = cachedExcludedBundleID else { return false }
        return Preferences.shared.excludedBundleIDs.contains(bundleID)
    }

}
