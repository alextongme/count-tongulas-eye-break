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

        countdownMenuItem = NSMenuItem(title: "Next break in --:--", action: nil, keyEquivalent: "")
        countdownMenuItem.isEnabled = false
        menu.addItem(countdownMenuItem)

        menu.addItem(NSMenuItem.separator())

        statsMenuItem = NSMenuItem(title: Statistics.shared.todaySummary(), action: nil, keyEquivalent: "")
        statsMenuItem.isEnabled = false
        menu.addItem(statsMenuItem)

        streakMenuItem = NSMenuItem(title: "Streak: \(Statistics.shared.currentStreak) breaks", action: nil, keyEquivalent: "")
        streakMenuItem.isEnabled = false
        menu.addItem(streakMenuItem)

        approvalMenuItem = NSMenuItem(title: "Approval rating: \(Statistics.shared.approvalRating)%", action: nil, keyEquivalent: "")
        approvalMenuItem.isEnabled = false
        menu.addItem(approvalMenuItem)

        let historyItem = NSMenuItem(title: "View History...", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        pauseMenuItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.keyEquivalentModifierMask = [.command, .shift]
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        let skipItem = NSMenuItem(title: "Take a Break Now", action: #selector(skipToBreak), keyEquivalent: "b")
        skipItem.keyEquivalentModifierMask = [.command, .shift]
        skipItem.target = self
        menu.addItem(skipItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let websiteItem = NSMenuItem(title: "Visit alextong.me", action: #selector(openWebsite), keyEquivalent: "")
        websiteItem.target = self
        menu.addItem(websiteItem)

        let musicItem = NSMenuItem(title: "🎵 Listen to my music", action: #selector(openMusic), keyEquivalent: "")
        musicItem.target = self
        menu.addItem(musicItem)

        let donateItem = NSMenuItem(title: "❤️ Donate if you enjoy the app", action: #selector(openDonate), keyEquivalent: "")
        donateItem.target = self
        menu.addItem(donateItem)

        let bugItem = NSMenuItem(title: "🐛 Report a bug", action: #selector(reportBug), keyEquivalent: "")
        bugItem.target = self
        menu.addItem(bugItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Count Tongula", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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
                button.title = "⏸ Paused"
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
        if Preferences.shared.appExclusionEnabled {
            if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               Preferences.shared.excludedBundleIDs.contains(bundleID) {
                if let button = statusItem.button {
                    button.title = "🦇 Excluded"
                }
                countdownMenuItem.title = "Paused (excluded app)"
                return
            }
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
        if isPaused {
            if let button = statusItem.button {
                button.title = "⏸ Paused"
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
        // TODO: Replace with actual donate link
        NSWorkspace.shared.open(URL(string: "https://alextong.me")!)
    }

    @objc func reportBug() {
        // TODO: Replace with actual email
        let email = "placeholder@example.com"
        let subject = "Count Tongula Bug Report"
        let urlString = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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

    // MARK: - Helpers

    func formatTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}
