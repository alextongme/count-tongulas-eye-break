import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, BreakWindowDelegate {

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
    var preBreakNotified = false

    var countdownMenuItem: NSMenuItem!
    var statsMenuItem: NSMenuItem!
    var streakMenuItem: NSMenuItem!
    var pauseMenuItem: NSMenuItem!
    var approvalMenuItem: NSMenuItem!

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        installLaunchAgentIfNeeded()
        setupStatusItem()
        buildMenu()
        startIdleDetector()
        registerKeyboardShortcuts()

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

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if !Preferences.shared.hasCompletedOnboarding {
            showOnboarding()
        } else {
            startTimer()
        }
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

        statsMenuItem = menuItem(Statistics.shared.todaySummary())
        statsMenuItem.isEnabled = false
        menu.addItem(statsMenuItem)

        streakMenuItem = menuItem("Streak: \(Statistics.shared.currentStreak) breaks", emoji: "🔥")
        streakMenuItem.isEnabled = false
        menu.addItem(streakMenuItem)

        approvalMenuItem = menuItem("Approval rating: \(Statistics.shared.approvalRating)%", emoji: "📊")
        approvalMenuItem.isEnabled = false
        menu.addItem(approvalMenuItem)

        let historyItem = menuItem("View History...", emoji: "📈", action: #selector(showHistory))
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        pauseMenuItem = menuItem("Pause", emoji: "⏸️", action: #selector(togglePause), key: "p")
        pauseMenuItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(pauseMenuItem)

        let skipItem = menuItem("Take a Break Now", emoji: "👁", action: #selector(skipToBreak), key: "b")
        skipItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(skipItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem("Settings...", emoji: "⚙️", action: #selector(showSettings)))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem("Visit alextong.me", emoji: "🌐", action: #selector(openWebsite)))
        menu.addItem(menuItem("Listen to my music", emoji: "🎵", action: #selector(openMusic)))
        menu.addItem(menuItem("Buy me a coffee", emoji: "☕", action: #selector(openDonate)))
        menu.addItem(menuItem("Report a bug", emoji: "🐛", action: #selector(reportBug)))
        menu.addItem(menuItem("Request a feature", emoji: "💡", action: #selector(requestFeature)))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem("Quit Count Tongula", emoji: "👋", action: #selector(quitApp)))

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

    // MARK: - Idle Detector

    func startIdleDetector() {
        IdleDetector.shared.startMonitoring()
    }

    // MARK: - Timer Management

    func startTimer() {
        breakTimer?.invalidate()
        preBreakNotified = false
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
        if isPaused {
            if let button = statusItem.button {
                button.title = "⏸️ Paused"
            }
            countdownMenuItem.title = "Paused"
            return
        }

        if IdleDetector.shared.shouldDeferBreak {
            if let button = statusItem.button {
                button.title = "🦇 Deferred"
            }
            countdownMenuItem.title = "Deferred (DND or locked)"
            return
        }

        if IdleDetector.shared.isUserIdle {
            // User is already resting; reset the timer as a natural break
            secondsUntilBreak = Preferences.shared.breakInterval
            preBreakNotified = false
            updateStatusDisplay()
            return
        }

        // App exclusion: pause timer while excluded app is frontmost
        if Preferences.shared.appExclusionEnabled && isExcludedAppFrontmost() {
            if let button = statusItem.button {
                button.title = "🦇 Excluded"
            }
            countdownMenuItem.title = "Paused (excluded app)"
            return
        }

        secondsUntilBreak -= 1
        updateStatusDisplay()

        // Pre-break notification
        if secondsUntilBreak == 15 && !preBreakNotified && Preferences.shared.preBreakNotifyEnabled {
            preBreakNotified = true
            let content = UNMutableNotificationContent()
            content.title = "Eye break in 15 seconds"
            content.body = "Count Tongula is preparing your eye break..."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "preBreak", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }

        if secondsUntilBreak <= 0 {
            triggerBreak()
        }
    }

    func updateStatusDisplay() {
        let timeStr = formatTime(secondsUntilBreak)
        if let button = statusItem.button {
            if secondsUntilBreak <= 30 && secondsUntilBreak > 0 {
                let icon = secondsUntilBreak % 2 == 0 ? "🦇" : "👁"
                button.title = "\(icon) \(timeStr)"
            } else {
                button.title = "🦇 \(timeStr)"
            }
        }
        countdownMenuItem.title = "Next break in \(timeStr)"
    }

    func triggerBreak() {
        breakTimer?.invalidate()
        breakTimer = nil
        preBreakNotified = false
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["preBreak"])

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

    @objc func quitApp() {
        IdleDetector.shared.stopMonitoring()
        NSApp.terminate(nil)
    }

    // MARK: - Keyboard Shortcuts

    func registerKeyboardShortcuts() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command, .shift] else { return }

            switch event.keyCode {
            case 11: // Cmd+Shift+B
                DispatchQueue.main.async { self.skipToBreak() }
            case 35: // Cmd+Shift+P
                DispatchQueue.main.async { self.togglePause() }
            default:
                break
            }
        }
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

    // MARK: - LaunchAgent

    private func installLaunchAgentIfNeeded() {
        guard Preferences.shared.launchAtLogin else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let agentDir = home.appendingPathComponent("Library/LaunchAgents")
        let plistPath = agentDir.appendingPathComponent("com.counttongula.eyebreak.plist")

        guard !FileManager.default.fileExists(atPath: plistPath.path) else { return }

        let binary = ProcessInfo.processInfo.arguments[0]
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.counttongula.eyebreak</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binary)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/tmp/eye_break.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/eye_break.log</string>
        </dict>
        </plist>
        """

        try? FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try? plist.write(to: plistPath, atomically: true, encoding: .utf8)

        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(uid)", plistPath.path]
        try? task.run()
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
