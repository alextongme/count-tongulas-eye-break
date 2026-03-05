import Cocoa
import Lottie

// MARK: - Enums & Protocol

enum BreakType {
    case eye   // 20-second eye break
    case long  // 5-minute stretch break
}

enum BreakResult {
    case completed
    case skipped
    case snoozed
}

protocol BreakWindowDelegate: AnyObject {
    func breakDidFinish(type: BreakType, result: BreakResult)
}

// MARK: - Companion (non-primary screen mirror)

private struct CompanionViews {
    let mascot: NSImageView
    let heading: NSTextField
    let body: NSTextField
    let detail: NSTextField
    let countdownLbl: NSTextField
    let countdownSub: NSTextField
    let progressBar: ProgressBarView
    let lottieView: LottieAnimationView?
    let primaryBtn: HoverButton
    let secondaryBtn: HoverButton
    let dismissBtn: HoverLink
    let escHint: NSTextField
    let enterHint: NSTextField
    let primaryCenterX: NSLayoutConstraint
    let primaryPaired: NSLayoutConstraint
}

// MARK: - BreakWindowController

class BreakWindowController: NSObject, NSWindowDelegate {

    weak var delegate: BreakWindowDelegate?
    let breakType: BreakType
    let allowSnooze: Bool

    let window: NSWindow
    var overlayWindows: [NSWindow] = []

    let mascot: NSImageView
    let heading: NSTextField
    let body: NSTextField
    let detail: NSTextField
    let countdownLbl: NSTextField
    let countdownSub: NSTextField
    let progressBar: ProgressBarView
    var primaryBtn: HoverButton!
    var secondaryBtn: HoverButton!
    var dismissBtn: HoverLink!
    var lottieView: LottieAnimationView?
    var escHint: NSTextField!
    var enterHint: NSTextField!
    private var isOnCompleteScreen = false
    private var animationFiles: [String] = []
    private var unusedAnimations: [String] = []
    private var currentAnimationPath: String?
    private var escMonitor: Any?
    private var wakeObserver: NSObjectProtocol?
    private var companions: [(window: NSWindow, views: CompanionViews)] = []

    var primaryCenterX: NSLayoutConstraint!
    var primaryPaired: NSLayoutConstraint!
    var dismissAtBottom: NSLayoutConstraint!
    var dismissBelowProgress: NSLayoutConstraint!
    var mascotTopFixed: NSLayoutConstraint!
    var countdownCentering: [NSLayoutConstraint] = []
    var bodyTopConstraint: NSLayoutConstraint!
    var detailTopConstraint: NSLayoutConstraint!


    var secondsLeft: Int
    var timer: Timer?
    private var hasReportedResult = false

    private let totalDuration: Int

    // MARK: - Init

    init(type: BreakType, allowSnooze: Bool = true) {
        self.breakType = type
        self.allowSnooze = allowSnooze

        let duration = (type == .eye)
            ? Preferences.shared.breakDuration
            : Preferences.shared.longBreakDuration
        self.secondsLeft = duration
        self.totalDuration = duration

        // Main window
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = Drac.background
        win.isMovableByWindowBackground = false
        win.hasShadow = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window = win

        // Mascot
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        if let img = NSImage(contentsOfFile: assetPath("alex_final.png"))
                  ?? NSImage(contentsOfFile: assetPath("dracula.png")) {
            iv.image = img
        }
        self.mascot = iv

        // Labels
        self.heading      = makeLabel("", size: 22, weight: .bold, color: Drac.purple)
        self.body         = makeLabel("", size: 17, weight: .regular, color: Drac.foreground)
        self.detail       = makeLabel("", size: 15, weight: .medium, color: Drac.cyan)
        self.countdownLbl = {
        let lbl = NSTextField(labelWithString: "")
        lbl.font = dmMono(size: 80, weight: .medium)
        lbl.textColor = Drac.green
        lbl.alignment = .center
        lbl.lineBreakMode = .byWordWrapping
        lbl.maximumNumberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
        self.countdownSub = makeLabel("", size: 14, weight: .regular, color: Drac.comment)
        self.progressBar  = ProgressBarView()

        super.init()

        win.delegate = self

        // Buttons
        primaryBtn = HoverButton(
            "Start Break",
            bg: Drac.purple,
            hover: Drac.pink,
            fg: Drac.foreground,
            target: self,
            action: #selector(primaryTapped)
        )
        secondaryBtn = HoverButton(
            "Snooze 5 min",
            bg: Drac.currentLine,
            hover: Drac.comment,
            fg: Drac.foreground,
            target: self,
            action: #selector(snoozeTapped)
        )
        dismissBtn = HoverLink(
            "Not now—remind me later",
            color: Drac.comment,
            hover: Drac.pink,
            size: 13,
            target: self,
            action: #selector(dismissTapped)
        )

        // Esc hint label
        escHint = makeLabel("Press Esc to skip", size: 11, weight: .regular, color: Drac.comment)
        escHint.alphaValue = 0.6

        // Enter hint label (shown on complete screen)
        enterHint = makeLabel("Press Enter to dismiss", size: 11, weight: .regular, color: Drac.comment)
        enterHint.alphaValue = 0.6
        enterHint.isHidden = true
        escHint.isHidden = true

        // Esc key monitor
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc key
                if !Preferences.shared.strictMode {
                    self?.finishWithResult(.skipped)
                }
                return nil
            }
            if event.keyCode == 36 { // Enter key
                if self?.isOnCompleteScreen == true {
                    self?.finishWithResult(.completed)
                    return nil
                }
            }
            return event
        }

        // Discover all Lottie animation files
        let animDir = assetPath("animations")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: animDir) {
            animationFiles = contents.filter { $0.hasSuffix(".json") }
                .map { "\(animDir)/\($0)" }
        }

        // Create the animation view (animation loaded per-screen in loadRandomAnimation)
        let av = LottieAnimationView()
        av.loopMode = .loop
        av.translatesAutoresizingMaskIntoConstraints = false
        self.lottieView = av

        // On wake from sleep, auto-dismiss the break — the user was away and
        // effectively took a rest. This also resets the interval timer.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.finishWithResult(.completed)
        }

        layout()
        showPrompt()

        // Position on screen containing mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let screen = targetScreen {
            let sf = screen.visibleFrame
            let wf = win.frame
            let x = sf.minX + (sf.width - wf.width) / 2
            let y = sf.minY + (sf.height - wf.height) / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        startMascotAnimation()

        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            win.animator().alphaValue = 1.0
        }

        // Show companion windows on all other screens
        let primaryFrame = (targetScreen ?? NSScreen.main)?.frame
        for screen in NSScreen.screens where screen.frame != primaryFrame {
            let comp = buildCompanion(on: screen)
            companions.append(comp)
        }
    }

    // MARK: - Layout

    private func layout() {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor

        heading.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        countdownLbl.translatesAutoresizingMaskIntoConstraints = false
        countdownSub.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        primaryBtn.translatesAutoresizingMaskIntoConstraints = false
        secondaryBtn.translatesAutoresizingMaskIntoConstraints = false
        dismissBtn.translatesAutoresizingMaskIntoConstraints = false

        for v in [mascot, heading, body, detail, countdownLbl, countdownSub,
                  progressBar, primaryBtn!, secondaryBtn!, dismissBtn!, escHint!, enterHint!] as [NSView] {
            cv.addSubview(v)
        }
        if let lv = lottieView { cv.addSubview(lv) }

        // Multi-line labels — set preferredMaxLayoutWidth so text wraps
        // instead of expanding the window (460 - 64px padding = 396)
        for lbl in [heading, body, detail, countdownSub] {
            lbl.maximumNumberOfLines = 0
            lbl.lineBreakMode = .byWordWrapping
            lbl.preferredMaxLayoutWidth = 396
            lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        NSLayoutConstraint.activate([
            // Mascot
            mascot.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            mascot.widthAnchor.constraint(equalToConstant: 110),
            mascot.heightAnchor.constraint(equalToConstant: 110),

            // Heading
            heading.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 32),
            heading.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -32),

            // Body
            body.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            body.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            // Detail
            detail.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            detail.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            // Countdown label
            countdownLbl.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20),
            countdownLbl.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Countdown sub
            countdownSub.topAnchor.constraint(equalTo: countdownLbl.bottomAnchor, constant: -2),
            countdownSub.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Progress bar
            progressBar.topAnchor.constraint(equalTo: countdownSub.bottomAnchor, constant: 24),
            progressBar.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            progressBar.widthAnchor.constraint(equalToConstant: 300),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            // Primary button
            primaryBtn.bottomAnchor.constraint(equalTo: dismissBtn.topAnchor, constant: -14),
            primaryBtn.widthAnchor.constraint(equalToConstant: 160),
            primaryBtn.heightAnchor.constraint(equalToConstant: 42),

            // Secondary button
            secondaryBtn.bottomAnchor.constraint(equalTo: dismissBtn.topAnchor, constant: -14),
            secondaryBtn.leadingAnchor.constraint(equalTo: cv.centerXAnchor, constant: 8),
            secondaryBtn.widthAnchor.constraint(equalToConstant: 160),
            secondaryBtn.heightAnchor.constraint(equalToConstant: 42),

            // Dismiss link
            dismissBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Esc hint
            escHint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            escHint.topAnchor.constraint(equalTo: dismissBtn.bottomAnchor, constant: 8),

            // Enter hint (below primary button on complete screen)
            enterHint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            enterHint.topAnchor.constraint(equalTo: primaryBtn.bottomAnchor, constant: 12),
        ])

        bodyTopConstraint = body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14)
        detailTopConstraint = detail.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 14)
        bodyTopConstraint.isActive = true
        detailTopConstraint.isActive = true

        // Mascot top: fixed for prompt/complete, flexible for countdown centering
        mascotTopFixed = mascot.topAnchor.constraint(equalTo: cv.topAnchor, constant: 32)

        dismissAtBottom = dismissBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -28)
        dismissBelowProgress = dismissBtn.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 40)

        // Countdown vertical centering: equal spacers above mascot and below dismiss
        let topSpacer = NSLayoutGuide()
        let bottomSpacer = NSLayoutGuide()
        cv.addLayoutGuide(topSpacer)
        cv.addLayoutGuide(bottomSpacer)
        countdownCentering = [
            topSpacer.topAnchor.constraint(equalTo: cv.topAnchor),
            topSpacer.bottomAnchor.constraint(equalTo: mascot.topAnchor),
            bottomSpacer.topAnchor.constraint(equalTo: dismissBtn.bottomAnchor),
            bottomSpacer.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor),
        ]

        // Lottie animation (vertically centered between detail text and buttons)
        if let lv = lottieView {
            let spacer = NSLayoutGuide()
            cv.addLayoutGuide(spacer)
            NSLayoutConstraint.activate([
                spacer.topAnchor.constraint(equalTo: detail.bottomAnchor),
                spacer.bottomAnchor.constraint(equalTo: primaryBtn.topAnchor),
                lv.centerYAnchor.constraint(equalTo: spacer.centerYAnchor, constant: -10),
                lv.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
                lv.widthAnchor.constraint(equalToConstant: 180),
                lv.heightAnchor.constraint(equalToConstant: 180),
            ])
        }

        // Paired layout: two buttons side by side
        primaryPaired = primaryBtn.trailingAnchor.constraint(equalTo: cv.centerXAnchor, constant: -8)
        // Centered layout: single button
        primaryCenterX = primaryBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor)
    }

    private let fullHeight: CGFloat = 560

    private func resizeWindow(to height: CGFloat) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        var frame = window.frame
        frame.size.height = height
        frame.origin.x = sf.minX + (sf.width - frame.width) / 2
        frame.origin.y = sf.minY + (sf.height - frame.height) / 2
        window.setFrame(frame, display: true)
    }

    private func countdownFittingHeight() -> CGFloat {
        let headingH = heading.intrinsicContentSize.height
        let countdownH = countdownLbl.intrinsicContentSize.height
        let subH = countdownSub.intrinsicContentSize.height
        let dismissH = dismissBtn.intrinsicContentSize.height
        // mascot(110) + gap(20) + heading + gap(20) + countdown + gap(-2) + sub
        // + gap(24) + progress(6) + gap(40) + dismiss
        let content = 110 + 20 + headingH + 20 + countdownH + (-2) + subH + 24 + 6 + 40 + dismissH
        return content + 90  // 45px padding top + bottom
    }

    // MARK: - Animation

    private func loadRandomAnimation() {
        guard let lv = lottieView, !animationFiles.isEmpty else { return }
        if unusedAnimations.isEmpty {
            unusedAnimations = animationFiles.shuffled()
        }
        let path = unusedAnimations.removeLast()
        currentAnimationPath = path
        if let animation = LottieAnimation.filepath(path) {
            lv.animation = animation
            lv.play()
        }
    }

    // MARK: - Screen States

    func showPrompt() {
        isOnCompleteScreen = false

        heading.stringValue = (breakType == .long)
            ? "Time for a stretch break!"
            : "Time for an eye break!"
        heading.textColor = Drac.purple

        if breakType == .long {
            let longMin = Preferences.shared.longBreakDuration / 60
            body.stringValue = "Stand up, stretch, and move around."
            detail.stringValue = "This is a \(longMin)-minute break. Ready?"
        } else {
            body.stringValue = "Look at something 20 feet away for 20 seconds."
            detail.stringValue = ""
        }

        body.isHidden = false
        detail.isHidden = false
        countdownLbl.isHidden = true
        countdownSub.isHidden = true
        progressBar.isHidden = true
        enterHint.isHidden = true

        primaryBtn.setLabel("Start Break")
        primaryBtn.isHidden = false

        dismissBtn.isHidden = false
        dismissBelowProgress.isActive = false
        dismissAtBottom.isActive = true
        NSLayoutConstraint.deactivate(countdownCentering)
        mascotTopFixed.isActive = true

        resizeWindow(to: fullHeight)

        lottieView?.isHidden = false
        loadRandomAnimation()

        let isStrict = Preferences.shared.strictMode
        if allowSnooze && !isStrict {
            secondaryBtn.isHidden = false
            primaryCenterX.isActive = false
            primaryPaired.isActive = true
        } else {
            secondaryBtn.isHidden = true
            primaryPaired.isActive = false
            primaryCenterX.isActive = true
        }
        dismissBtn.isHidden = isStrict
        escHint.isHidden = true

        syncCompanionsToPrompt()
    }

    func showCountdown() {
        isOnCompleteScreen = false

        if Preferences.shared.fullscreenOverlay && overlayWindows.isEmpty {
            showOverlays()
        }

        let quoteList = (breakType == .long) ? Quotes.longBreak : Quotes.countdown
        heading.stringValue = Quotes.random(quoteList)
        heading.textColor = Drac.purple

        body.isHidden = true
        detail.isHidden = true
        countdownLbl.isHidden = false
        countdownSub.isHidden = false
        progressBar.isHidden = false
        enterHint.isHidden = true

        let isStrict = Preferences.shared.strictMode
        primaryBtn.isHidden = true
        secondaryBtn.isHidden = true
        dismissBtn.isHidden = isStrict
        escHint.isHidden = isStrict
        dismissAtBottom.isActive = false
        dismissBelowProgress.isActive = true
        mascotTopFixed.isActive = false
        NSLayoutConstraint.activate(countdownCentering)

        resizeWindow(to: countdownFittingHeight())

        lottieView?.isHidden = true
        lottieView?.stop()

        syncCompanionsToCountdown()
        updateCountdown()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.secondsLeft -= 1
            if self.secondsLeft <= 0 {
                self.secondsLeft = 0
                self.timer?.invalidate()
                self.timer = nil
                self.showComplete()
            } else {
                self.updateCountdown()
            }
        }
    }

    private func updateCountdown() {
        if secondsLeft >= 60 {
            let minutes = secondsLeft / 60
            let seconds = secondsLeft % 60
            countdownLbl.stringValue = String(format: "%d:%02d", minutes, seconds)
            countdownSub.stringValue = "remaining"
        } else {
            countdownLbl.stringValue = "\(secondsLeft)"
            countdownSub.stringValue = "seconds remaining"
        }

        let total = CGFloat(totalDuration > 0 ? totalDuration : 1)
        progressBar.progress = 1.0 - CGFloat(secondsLeft) / total

        updateCompanionCountdowns()
    }

    func showComplete() {
        isOnCompleteScreen = true
        timer?.invalidate()
        timer = nil

        let milestoneMsg = Statistics.shared.nextStreakMilestone()
        let isMilestone = milestoneMsg != nil

        if isMilestone {
            SoundManager.shared.playMilestoneSound()
            heading.stringValue = "🏆 Milestone Reached!"
            heading.textColor = Drac.orange
            body.stringValue = milestoneMsg!
            body.textColor = Drac.pink
            detail.stringValue = "Streak: \(Statistics.shared.nextStreak) breaks"
            detail.textColor = Drac.yellow
            bodyTopConstraint.constant = 24
            detailTopConstraint.constant = 20

            // Purple-tinted background + orange glow border
            let cv = window.contentView!
            cv.layer?.backgroundColor = NSColor(srgbRed: 0x30/255.0, green: 0x2B/255.0, blue: 0x44/255.0, alpha: 1).cgColor
            cv.layer?.borderWidth = 2
            cv.layer?.borderColor = Drac.orange.cgColor
            cv.layer?.shadowColor = Drac.orange.cgColor
            cv.layer?.shadowRadius = 12
            cv.layer?.shadowOpacity = 0.6
            cv.layer?.shadowOffset = .zero
        } else {
            SoundManager.shared.playCompleteSound()
            heading.stringValue = "Break complete!"
            heading.textColor = Drac.green
            body.stringValue = Quotes.random(Quotes.complete)
            body.textColor = Drac.foreground
            detail.stringValue = "You may return to your screen."
            detail.textColor = Drac.foreground
            bodyTopConstraint.constant = 14
            detailTopConstraint.constant = 14

            // Reset to normal background
            let cv = window.contentView!
            cv.layer?.backgroundColor = Drac.background.cgColor
            cv.layer?.borderWidth = 0
            cv.layer?.shadowOpacity = 0
        }

        body.isHidden = false
        detail.isHidden = false
        countdownLbl.isHidden = true
        countdownSub.isHidden = true
        progressBar.isHidden = true

        primaryBtn.setLabel("Thanks, Count!")
        primaryBtn.isHidden = false
        primaryPaired.isActive = false
        primaryCenterX.isActive = true
        secondaryBtn.isHidden = true
        dismissBtn.isHidden = true
        escHint.isHidden = true
        enterHint.isHidden = false
        dismissBelowProgress.isActive = false
        dismissAtBottom.isActive = true
        NSLayoutConstraint.deactivate(countdownCentering)
        mascotTopFixed.isActive = true

        resizeWindow(to: fullHeight)

        lottieView?.isHidden = false
        loadRandomAnimation()

        syncCompanionsToComplete(milestone: isMilestone, milestoneMsg: milestoneMsg)

        let delay = isMilestone ? max(Preferences.shared.autoQuitDelay, 12) : Preferences.shared.autoQuitDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
            self?.finishWithResult(.completed)
        }
    }

    /// Preview-only: force the milestone complete UI regardless of actual streak
    func showMilestonePreview() {
        isOnCompleteScreen = true
        timer?.invalidate()
        timer = nil

        SoundManager.shared.playMilestoneSound()
        heading.stringValue = "🏆 Milestone Reached!"
        heading.textColor = Drac.orange
        body.stringValue = Quotes.milestones[5] ?? "5 breaks without fail! The Count promotes you to Familiar."
        body.textColor = Drac.pink
        detail.stringValue = "Streak: 5 breaks"
        detail.textColor = Drac.yellow
        bodyTopConstraint.constant = 24
        detailTopConstraint.constant = 20

        let cv = window.contentView!
        cv.layer?.backgroundColor = NSColor(srgbRed: 0x30/255.0, green: 0x2B/255.0, blue: 0x44/255.0, alpha: 1).cgColor
        cv.layer?.borderWidth = 2
        cv.layer?.borderColor = Drac.orange.cgColor
        cv.layer?.shadowColor = Drac.orange.cgColor
        cv.layer?.shadowRadius = 12
        cv.layer?.shadowOpacity = 0.6
        cv.layer?.shadowOffset = .zero

        body.isHidden = false
        detail.isHidden = false
        countdownLbl.isHidden = true
        countdownSub.isHidden = true
        progressBar.isHidden = true

        primaryBtn.setLabel("Thanks, Count!")
        primaryBtn.isHidden = false
        primaryPaired.isActive = false
        primaryCenterX.isActive = true
        secondaryBtn.isHidden = true
        dismissBtn.isHidden = true
        escHint.isHidden = true
        enterHint.isHidden = false
        dismissBelowProgress.isActive = false
        dismissAtBottom.isActive = true
        NSLayoutConstraint.deactivate(countdownCentering)
        mascotTopFixed.isActive = true

        resizeWindow(to: fullHeight)

        lottieView?.isHidden = false
        loadRandomAnimation()
    }

    // MARK: - Button Actions

    @objc private func primaryTapped() {
        if primaryBtn.title == "Thanks, Count!" {
            finishWithResult(.completed)
        } else {
            showCountdown()
        }
    }

    @objc private func snoozeTapped() {
        finishWithResult(.snoozed)
    }

    @objc private func dismissTapped() {
        finishWithResult(.skipped)
    }

    // MARK: - Finish

    func finishWithResult(_ result: BreakResult) {
        guard !hasReportedResult else { return }
        hasReportedResult = true

        timer?.invalidate()
        timer = nil

        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }

        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.window.animator().alphaValue = 0
            for ow in self.overlayWindows {
                ow.animator().alphaValue = 0
            }
            for c in self.companions {
                c.window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            for ow in self.overlayWindows {
                ow.orderOut(nil)
            }
            self.overlayWindows.removeAll()
            for c in self.companions {
                c.window.orderOut(nil)
            }
            self.companions.removeAll()
            self.window.orderOut(nil)
            self.delegate?.breakDidFinish(type: self.breakType, result: result)
        })
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if !hasReportedResult {
            finishWithResult(.skipped)
        }
    }

    // MARK: - Multi-monitor Overlays

    private func showOverlays() {
        guard Preferences.shared.fullscreenOverlay else { return }

        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = Drac.background.withAlphaComponent(0.85)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.setFrame(screen.frame, display: false)
            panel.alphaValue = 0
            panel.orderFront(nil)
            overlayWindows.append(panel)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                panel.animator().alphaValue = 1.0
            }

            if Preferences.shared.cloudsEnabled {
                addOverlayClouds(to: panel, screenFrame: screen.frame)
            }
            addOverlayBats(to: panel, screenFrame: screen.frame)
        }
    }

    private func addOverlayClouds(to panel: NSPanel, screenFrame: NSRect) {
        guard let cv = panel.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.masksToBounds = true

        let cloudPath = assetPath("clouds.png")
        guard let cloudImage = NSImage(contentsOfFile: cloudPath),
              let cgImage = cloudImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let screenW = screenFrame.width
        let h = screenFrame.height
        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let layerW = max(ceil(imageAspect * h), screenW)

        // Single image — no tiling, no seams. Pan back and forth across the screen.
        let cloudLayer = CALayer()
        cloudLayer.frame = CGRect(x: 0, y: 0, width: layerW, height: h)
        cloudLayer.contents = cgImage
        cloudLayer.contentsGravity = .resizeAspectFill
        cloudLayer.opacity = 0
        cv.layer?.addSublayer(cloudLayer)

        let panDistance = layerW - screenW
        if panDistance > 0 {
            // Match the original scroll speed (~48pt/s)
            let speed: CGFloat = 64.0
            let duration = Double(panDistance / speed)
            let scroll = CABasicAnimation(keyPath: "position.x")
            scroll.fromValue = layerW / 2
            scroll.toValue = layerW / 2 - panDistance
            scroll.duration = max(duration, 5)
            scroll.autoreverses = true
            scroll.repeatCount = .infinity
            scroll.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cloudLayer.add(scroll, forKey: "scroll")
        }

        // Fade in
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 0.35
        fadeIn.duration = 2.5
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        cloudLayer.add(fadeIn, forKey: "fadeIn")
    }

    // MARK: - Overlay Bats

    private func addOverlayBats(to panel: NSPanel, screenFrame: NSRect) {
        guard let cv = panel.contentView else { return }

        let screenW = screenFrame.width
        let screenH = screenFrame.height
        let batColor = NSColor(srgbRed: 0.10, green: 0.08, blue: 0.16, alpha: 1).cgColor

        // --- Helpers ---

        func addBat(
            wingspan: CGFloat,
            opacity: Float,
            flapSpeed: Double,
            fadeDelay: Double,
            addFlight: (CAShapeLayer) -> Void
        ) {
            let bat = CAShapeLayer()
            bat.fillColor = batColor
            bat.strokeColor = nil
            bat.opacity = 0
            bat.path = batSilhouettePath(wingspan: wingspan, flapPhase: 0)
            cv.layer?.addSublayer(bat)

            // Wing flap
            let wingsUp = batSilhouettePath(wingspan: wingspan, flapPhase: 0)
            let wingsDown = batSilhouettePath(wingspan: wingspan, flapPhase: 0.5)
            let flap = CAKeyframeAnimation(keyPath: "path")
            flap.values = [wingsUp, wingsDown, wingsUp]
            flap.keyTimes = [0, 0.5, 1]
            flap.duration = flapSpeed
            flap.repeatCount = .infinity
            flap.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bat.add(flap, forKey: "flap")

            // Random base rotation so they aren't all perfectly level
            let baseAngle = CGFloat.random(in: -CGFloat.pi * 0.1...CGFloat.pi * 0.1)
            bat.setAffineTransform(CGAffineTransform(rotationAngle: baseAngle))

            // Rocking rotation — ~60% of bats wobble, rest stay fixed
            if Double.random(in: 0...1) < 0.6 {
                let wobble = CABasicAnimation(keyPath: "transform.rotation.z")
                wobble.fromValue = baseAngle - CGFloat.pi * CGFloat.random(in: 0.01...0.08)
                wobble.toValue = baseAngle + CGFloat.pi * CGFloat.random(in: 0.01...0.08)
                wobble.duration = Double.random(in: 1.5...4.0)
                wobble.autoreverses = true
                wobble.repeatCount = .infinity
                wobble.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bat.add(wobble, forKey: "wobble")
            }

            // Flight (or hover) — caller decides
            addFlight(bat)

            // Fade in
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = opacity
            fadeIn.duration = Double.random(in: 1.5...3.0)
            fadeIn.beginTime = CACurrentMediaTime() + fadeDelay
            fadeIn.fillMode = .both
            fadeIn.isRemovedOnCompletion = false
            bat.add(fadeIn, forKey: "fadeIn")
        }

        // --- Flying bats: cross the screen on varied bezier paths ---

        let flyingCount = Int.random(in: 25...35)
        for _ in 0..<flyingCount {
            let wingspan = CGFloat.random(in: 15...110)
            // Depth layers: smaller + fainter = behind fog, larger + brighter = in front
            let depthFactor = Float(wingspan - 15) / 95.0   // 0 (tiny) → 1 (large)
            let opacity = Float.random(in: 0.15...0.35) + depthFactor * 0.30

            let goingRight = Bool.random()
            let goingUp = Bool.random()
            let startX: CGFloat = goingRight ? -wingspan * 2 : screenW + wingspan * 2
            let endX: CGFloat = goingRight ? screenW + wingspan * 2 : -wingspan * 2

            // Full vertical range — use the entire screen including edges
            let startY = CGFloat.random(in: -wingspan...screenH + wingspan)
            let endY = CGFloat.random(in: -wingspan...screenH + wingspan)

            // Control points spread across the full screen area including edges
            let cp1 = CGPoint(
                x: goingRight ? CGFloat.random(in: -screenW * 0.1...screenW * 0.55)
                              : CGFloat.random(in: screenW * 0.45...screenW * 1.1),
                y: goingUp ? CGFloat.random(in: screenH * 0.3...screenH * 1.1)
                           : CGFloat.random(in: -screenH * 0.1...screenH * 0.7)
            )
            let cp2 = CGPoint(
                x: goingRight ? CGFloat.random(in: screenW * 0.45...screenW * 1.1)
                              : CGFloat.random(in: -screenW * 0.1...screenW * 0.55),
                y: CGFloat.random(in: -screenH * 0.1...screenH * 1.1)
            )

            let flightPath = CGMutablePath()
            flightPath.move(to: CGPoint(x: startX, y: startY))
            flightPath.addCurve(to: CGPoint(x: endX, y: endY), control1: cp1, control2: cp2)

            let stagger = Double.random(in: 0...5)
            let speed = Double.random(in: 5...20)

            addBat(
                wingspan: wingspan,
                opacity: opacity,
                flapSpeed: Double.random(in: 0.2...0.5),
                fadeDelay: stagger + 0.5
            ) { bat in
                let flight = CAKeyframeAnimation(keyPath: "position")
                flight.path = flightPath
                flight.duration = speed
                flight.repeatCount = .infinity
                flight.calculationMode = .paced
                flight.beginTime = CACurrentMediaTime() + stagger
                flight.fillMode = .both
                bat.add(flight, forKey: "flight")

                // Vertical bob — ~70% of flying bats
                if Double.random(in: 0...1) < 0.7 {
                    let bob = CABasicAnimation(keyPath: "transform.translation.y")
                    bob.fromValue = -wingspan * CGFloat.random(in: 0.08...0.2)
                    bob.toValue = wingspan * CGFloat.random(in: 0.08...0.2)
                    bob.duration = Double.random(in: 1.2...3.5)
                    bob.autoreverses = true
                    bob.repeatCount = .infinity
                    bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bat.add(bob, forKey: "bob")
                }

                // Depth scale — ~50% of flying bats
                if Double.random(in: 0...1) < 0.5 {
                    let depth = CABasicAnimation(keyPath: "transform.scale")
                    depth.fromValue = CGFloat.random(in: 0.82...0.98)
                    depth.toValue = CGFloat.random(in: 1.02...1.18)
                    depth.duration = Double.random(in: 4...10)
                    depth.autoreverses = true
                    depth.repeatCount = .infinity
                    depth.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bat.add(depth, forKey: "depth")
                }
            }
        }

        // --- Hovering bats: stationary, just flapping in place ---

        let hoverCount = Int.random(in: 10...18)
        for _ in 0..<hoverCount {
            let wingspan = CGFloat.random(in: 10...60)
            let depthFactor = Float(wingspan - 10) / 50.0
            let opacity = Float.random(in: 0.10...0.30) + depthFactor * 0.20

            // Place across the full screen, including near edges and corners
            let posX = CGFloat.random(in: screenW * 0.01...screenW * 0.99)
            let posY = CGFloat.random(in: screenH * 0.02...screenH * 0.98)

            addBat(
                wingspan: wingspan,
                opacity: opacity,
                flapSpeed: Double.random(in: 0.3...0.7),
                fadeDelay: Double.random(in: 0.5...4)
            ) { bat in
                bat.position = CGPoint(x: posX, y: posY)

                // Gentle drift — ~75% drift around, rest stay truly fixed
                if Double.random(in: 0...1) < 0.75 {
                    let range = CGFloat.random(in: 3...25)
                    let drift = CABasicAnimation(keyPath: "position")
                    drift.fromValue = NSValue(point: NSPoint(
                        x: posX - CGFloat.random(in: 2...range),
                        y: posY - CGFloat.random(in: 2...range)
                    ))
                    drift.toValue = NSValue(point: NSPoint(
                        x: posX + CGFloat.random(in: 2...range),
                        y: posY + CGFloat.random(in: 2...range)
                    ))
                    drift.duration = Double.random(in: 3...10)
                    drift.autoreverses = true
                    drift.repeatCount = .infinity
                    drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bat.add(drift, forKey: "drift")
                }

                // Depth scale on hovering bats too — ~40%
                if Double.random(in: 0...1) < 0.4 {
                    let depth = CABasicAnimation(keyPath: "transform.scale")
                    depth.fromValue = CGFloat.random(in: 0.88...0.97)
                    depth.toValue = CGFloat.random(in: 1.03...1.12)
                    depth.duration = Double.random(in: 5...12)
                    depth.autoreverses = true
                    depth.repeatCount = .infinity
                    depth.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bat.add(depth, forKey: "depth")
                }
            }
        }
    }

    /// Generates a bat silhouette CGPath with scalloped wings.
    /// `flapPhase` 0 = wings up, 0.5 = wings down. All phases produce paths
    /// with identical element counts so Core Animation can interpolate between them.
    private func batSilhouettePath(wingspan: CGFloat, flapPhase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let half = wingspan / 2
        let bw = wingspan * 0.06       // body half-width
        let bh = wingspan * 0.12       // body half-height
        let earH = wingspan * 0.055    // ear height above body top
        let amplitude = wingspan * 0.22
        let tipY = amplitude * cos(flapPhase * .pi * 2)
        let dip = wingspan * 0.035     // scallop concavity depth

        // Scallop finger X/Y positions (right wing; left is mirrored)
        let s1x = half * 0.72,  s1y = tipY * 0.65
        let s2x = half * 0.45,  s2y = tipY * 0.35
        let s3x = half * 0.22,  s3y = tipY * 0.12

        // Left wing tip
        path.move(to: CGPoint(x: -half, y: tipY))

        // Left wing leading edge → shoulder
        path.addQuadCurve(to: CGPoint(x: -bw, y: bh * 0.4),
                          control: CGPoint(x: -half * 0.45, y: tipY * 0.5 + bh * 0.5))

        // Ears
        path.addLine(to: CGPoint(x: -bw * 0.7, y: bh + earH))
        path.addLine(to: CGPoint(x: -bw * 0.15, y: bh * 0.6))
        path.addLine(to: CGPoint(x:  bw * 0.15, y: bh * 0.6))
        path.addLine(to: CGPoint(x:  bw * 0.7,  y: bh + earH))

        // Right shoulder
        path.addLine(to: CGPoint(x: bw, y: bh * 0.4))

        // Right wing leading edge → tip
        path.addQuadCurve(to: CGPoint(x: half, y: tipY),
                          control: CGPoint(x: half * 0.45, y: tipY * 0.5 + bh * 0.5))

        // Right wing trailing edge (scalloped)
        path.addQuadCurve(to: CGPoint(x: s1x, y: s1y - dip),
                          control: CGPoint(x: (half + s1x) / 2, y: (tipY + s1y) / 2 - dip * 1.5))
        path.addQuadCurve(to: CGPoint(x: s2x, y: s2y - dip),
                          control: CGPoint(x: (s1x + s2x) / 2, y: (s1y + s2y) / 2 - dip * 1.5))
        path.addQuadCurve(to: CGPoint(x: s3x, y: s3y - dip),
                          control: CGPoint(x: (s2x + s3x) / 2, y: (s2y + s3y) / 2 - dip * 1.5))
        path.addQuadCurve(to: CGPoint(x: bw * 0.5, y: -bh),
                          control: CGPoint(x: (s3x + bw) / 2, y: -bh * 0.5 - dip))

        // Body bottom
        path.addQuadCurve(to: CGPoint(x: -bw * 0.5, y: -bh),
                          control: CGPoint(x: 0, y: -bh * 1.2))

        // Left wing trailing edge (mirror)
        path.addQuadCurve(to: CGPoint(x: -s3x, y: s3y - dip),
                          control: CGPoint(x: -(s3x + bw) / 2, y: -bh * 0.5 - dip))
        path.addQuadCurve(to: CGPoint(x: -s2x, y: s2y - dip),
                          control: CGPoint(x: -(s2x + s3x) / 2, y: (s2y + s3y) / 2 - dip * 1.5))
        path.addQuadCurve(to: CGPoint(x: -s1x, y: s1y - dip),
                          control: CGPoint(x: -(s1x + s2x) / 2, y: (s1y + s2y) / 2 - dip * 1.5))
        path.addQuadCurve(to: CGPoint(x: -half, y: tipY),
                          control: CGPoint(x: -(half + s1x) / 2, y: (tipY + s1y) / 2 - dip * 1.5))

        path.closeSubpath()
        return path
    }

    // MARK: - Wake Recovery

    /// Rebuilds all CA-driven visuals that freeze when macOS sleeps.
    /// The render server is suspended on sleep and CACurrentMediaTime() jumps
    /// forward on wake, leaving beginTime-anchored animations expired/stuck.
    private func restoreAnimationsAfterWake() {
        // 1. Tear down and rebuild overlay windows (bats + clouds)
        for ow in overlayWindows { ow.orderOut(nil) }
        overlayWindows.removeAll()
        if Preferences.shared.fullscreenOverlay && !isOnCompleteScreen {
            showOverlays()
        }

        // 2. Restart Lottie
        lottieView?.stop()
        lottieView?.play()

        // 3. Restart mascot float
        mascot.layer?.removeAnimation(forKey: "float")
        startMascotAnimation()

        // 4. Restart companion mascot floats and Lottie animations
        for c in companions {
            c.views.mascot.layer?.removeAnimation(forKey: "float")
            startMascotAnimation(for: c.views.mascot)
            c.views.lottieView?.stop()
            c.views.lottieView?.play()
        }
    }

    // MARK: - Mascot Animation

    private func startMascotAnimation() {
        mascot.wantsLayer = true

        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 0
        animation.toValue = -9
        animation.duration = 2.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        mascot.layer?.add(animation, forKey: "float")
    }

    private func startMascotAnimation(for imageView: NSImageView) {
        imageView.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 0
        animation.toValue = -9
        animation.duration = 2.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageView.layer?.add(animation, forKey: "float")
    }

    // MARK: - Companion Windows

    private func buildCompanion(on screen: NSScreen) -> (window: NSWindow, views: CompanionViews) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: fullHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = Drac.background
        win.isMovableByWindowBackground = false
        win.hasShadow = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        guard let cv = win.contentView else {
            fatalError("companion window has no contentView")
        }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor

        // Mascot
        let cMascot = NSImageView()
        cMascot.translatesAutoresizingMaskIntoConstraints = false
        cMascot.imageScaling = .scaleProportionallyDown
        cMascot.image = mascot.image

        // Labels
        let cHeading      = makeLabel("", size: 22, weight: .bold, color: Drac.purple)
        let cBody         = makeLabel("", size: 17, weight: .regular, color: Drac.foreground)
        let cDetail        = makeLabel("", size: 15, weight: .medium, color: Drac.cyan)
        let cCountdownLbl: NSTextField = {
            let lbl = NSTextField(labelWithString: "")
            lbl.font = dmMono(size: 80, weight: .medium)
            lbl.textColor = Drac.green
            lbl.alignment = .center
            lbl.lineBreakMode = .byWordWrapping
            lbl.maximumNumberOfLines = 0
            lbl.translatesAutoresizingMaskIntoConstraints = false
            return lbl
        }()
        let cCountdownSub = makeLabel("", size: 14, weight: .regular, color: Drac.comment)
        let cProgressBar  = ProgressBarView()
        cProgressBar.translatesAutoresizingMaskIntoConstraints = false

        // Lottie
        var cLottie: LottieAnimationView?
        if !animationFiles.isEmpty {
            let lv = LottieAnimationView()
            lv.loopMode = .loop
            lv.translatesAutoresizingMaskIntoConstraints = false
            cLottie = lv
        }

        // Buttons — target the same actions on self
        let cPrimaryBtn = HoverButton(
            "Start Break",
            bg: Drac.purple, hover: Drac.pink, fg: Drac.foreground,
            target: self, action: #selector(primaryTapped)
        )
        let cSecondaryBtn = HoverButton(
            "Snooze 5 min",
            bg: Drac.currentLine, hover: Drac.comment, fg: Drac.foreground,
            target: self, action: #selector(snoozeTapped)
        )
        let cDismissBtn = HoverLink(
            "Not now—remind me later",
            color: Drac.comment, hover: Drac.pink, size: 13,
            target: self, action: #selector(dismissTapped)
        )
        let cEscHint = makeLabel("Press Esc to skip", size: 11, weight: .regular, color: Drac.comment)
        cEscHint.alphaValue = 0.6
        cEscHint.isHidden = true
        let cEnterHint = makeLabel("Press Enter to dismiss", size: 11, weight: .regular, color: Drac.comment)
        cEnterHint.alphaValue = 0.6
        cEnterHint.isHidden = true

        // Add subviews
        for v in [cMascot, cHeading, cBody, cDetail, cCountdownLbl, cCountdownSub,
                  cProgressBar, cPrimaryBtn, cSecondaryBtn, cDismissBtn, cEscHint, cEnterHint] as [NSView] {
            cv.addSubview(v)
        }
        if let lv = cLottie { cv.addSubview(lv) }

        // Multi-line wrapping
        for lbl in [cHeading, cBody, cDetail, cCountdownSub] {
            lbl.maximumNumberOfLines = 0
            lbl.lineBreakMode = .byWordWrapping
            lbl.preferredMaxLayoutWidth = 396
            lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        // Layout — mirrors the primary window
        let mascotTop = cMascot.topAnchor.constraint(equalTo: cv.topAnchor, constant: 32)
        mascotTop.isActive = true

        NSLayoutConstraint.activate([
            cMascot.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cMascot.widthAnchor.constraint(equalToConstant: 110),
            cMascot.heightAnchor.constraint(equalToConstant: 110),

            cHeading.topAnchor.constraint(equalTo: cMascot.bottomAnchor, constant: 20),
            cHeading.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 32),
            cHeading.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -32),

            cBody.topAnchor.constraint(equalTo: cHeading.bottomAnchor, constant: 14),
            cBody.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            cBody.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            cDetail.topAnchor.constraint(equalTo: cBody.bottomAnchor, constant: 14),
            cDetail.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            cDetail.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            cCountdownLbl.topAnchor.constraint(equalTo: cHeading.bottomAnchor, constant: 20),
            cCountdownLbl.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            cCountdownSub.topAnchor.constraint(equalTo: cCountdownLbl.bottomAnchor, constant: -2),
            cCountdownSub.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            cProgressBar.topAnchor.constraint(equalTo: cCountdownSub.bottomAnchor, constant: 24),
            cProgressBar.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cProgressBar.widthAnchor.constraint(equalToConstant: 300),
            cProgressBar.heightAnchor.constraint(equalToConstant: 6),

            cPrimaryBtn.bottomAnchor.constraint(equalTo: cDismissBtn.topAnchor, constant: -14),
            cPrimaryBtn.widthAnchor.constraint(equalToConstant: 160),
            cPrimaryBtn.heightAnchor.constraint(equalToConstant: 42),

            cSecondaryBtn.bottomAnchor.constraint(equalTo: cDismissBtn.topAnchor, constant: -14),
            cSecondaryBtn.leadingAnchor.constraint(equalTo: cv.centerXAnchor, constant: 8),
            cSecondaryBtn.widthAnchor.constraint(equalToConstant: 160),
            cSecondaryBtn.heightAnchor.constraint(equalToConstant: 42),

            cDismissBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cDismissBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -28),

            cEscHint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cEscHint.topAnchor.constraint(equalTo: cDismissBtn.bottomAnchor, constant: 8),

            cEnterHint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cEnterHint.topAnchor.constraint(equalTo: cPrimaryBtn.bottomAnchor, constant: 12),
        ])

        let cPrimaryCenterX = cPrimaryBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor)
        let cPrimaryPaired = cPrimaryBtn.trailingAnchor.constraint(equalTo: cv.centerXAnchor, constant: -8)

        if let lv = cLottie {
            let spacer = NSLayoutGuide()
            cv.addLayoutGuide(spacer)
            NSLayoutConstraint.activate([
                spacer.topAnchor.constraint(equalTo: cDetail.bottomAnchor),
                spacer.bottomAnchor.constraint(equalTo: cPrimaryBtn.topAnchor),
                lv.centerYAnchor.constraint(equalTo: spacer.centerYAnchor, constant: -10),
                lv.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
                lv.widthAnchor.constraint(equalToConstant: 180),
                lv.heightAnchor.constraint(equalToConstant: 180),
            ])
        }

        let views = CompanionViews(
            mascot: cMascot,
            heading: cHeading,
            body: cBody,
            detail: cDetail,
            countdownLbl: cCountdownLbl,
            countdownSub: cCountdownSub,
            progressBar: cProgressBar,
            lottieView: cLottie,
            primaryBtn: cPrimaryBtn,
            secondaryBtn: cSecondaryBtn,
            dismissBtn: cDismissBtn,
            escHint: cEscHint,
            enterHint: cEnterHint,
            primaryCenterX: cPrimaryCenterX,
            primaryPaired: cPrimaryPaired
        )

        // Mirror current primary state
        syncCompanion(views, toPromptFor: breakType)

        // Position on screen
        let sf = screen.visibleFrame
        let wf = win.frame
        let x = sf.minX + (sf.width - wf.width) / 2
        let y = sf.minY + (sf.height - wf.height) / 2
        win.setFrameOrigin(NSPoint(x: x, y: y))

        startMascotAnimation(for: cMascot)

        win.alphaValue = 0
        win.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            win.animator().alphaValue = 1.0
        }

        return (window: win, views: views)
    }

    // MARK: - Companion State Sync

    private func syncCompanion(_ v: CompanionViews, toPromptFor type: BreakType) {
        v.heading.stringValue = (type == .long)
            ? "Time for a stretch break!" : "Time for an eye break!"
        v.heading.textColor = Drac.purple

        if type == .long {
            let longMin = Preferences.shared.longBreakDuration / 60
            v.body.stringValue = "Stand up, stretch, and move around."
            v.detail.stringValue = "This is a \(longMin)-minute break. Ready?"
        } else {
            v.body.stringValue = "Look at something 20 feet away for 20 seconds."
            v.detail.stringValue = ""
        }

        v.body.isHidden = false
        v.detail.isHidden = false
        v.countdownLbl.isHidden = true
        v.countdownSub.isHidden = true
        v.progressBar.isHidden = true
        v.enterHint.isHidden = true
        v.lottieView?.isHidden = false
        loadCurrentAnimation(into: v.lottieView)

        v.primaryBtn.setLabel("Start Break")
        v.primaryBtn.isHidden = false
        v.dismissBtn.isHidden = false
        v.escHint.isHidden = true

        let isStrict = Preferences.shared.strictMode
        if allowSnooze && !isStrict {
            v.secondaryBtn.isHidden = false
            v.primaryCenterX.isActive = false
            v.primaryPaired.isActive = true
        } else {
            v.secondaryBtn.isHidden = true
            v.primaryPaired.isActive = false
            v.primaryCenterX.isActive = true
        }
        v.dismissBtn.isHidden = isStrict
    }

    private func syncCompanionsToPrompt() {
        for c in companions {
            syncCompanion(c.views, toPromptFor: breakType)
            resizeCompanion(c.window, to: fullHeight)
        }
    }

    private func resizeCompanion(_ win: NSWindow, to height: CGFloat) {
        guard let screen = win.screen ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        var frame = win.frame
        frame.size.height = height
        frame.origin.x = sf.minX + (sf.width - frame.width) / 2
        frame.origin.y = sf.minY + (sf.height - frame.height) / 2
        win.setFrame(frame, display: true)
    }

    private func syncCompanionsToCountdown() {
        let isStrict = Preferences.shared.strictMode
        let targetHeight = countdownFittingHeight()
        for c in companions {
            let v = c.views
            v.heading.stringValue = heading.stringValue
            v.heading.textColor = heading.textColor
            v.body.isHidden = true
            v.detail.isHidden = true
            v.countdownLbl.isHidden = false
            v.countdownSub.isHidden = false
            v.progressBar.isHidden = false
            v.enterHint.isHidden = true
            v.lottieView?.isHidden = true
            v.lottieView?.stop()

            v.primaryBtn.isHidden = true
            v.secondaryBtn.isHidden = true
            v.dismissBtn.isHidden = isStrict
            v.escHint.isHidden = isStrict

            resizeCompanion(c.window, to: targetHeight)
        }
        updateCompanionCountdowns()
    }

    private func updateCompanionCountdowns() {
        for c in companions {
            let v = c.views
            if secondsLeft >= 60 {
                let minutes = secondsLeft / 60
                let seconds = secondsLeft % 60
                v.countdownLbl.stringValue = String(format: "%d:%02d", minutes, seconds)
                v.countdownSub.stringValue = "remaining"
            } else {
                v.countdownLbl.stringValue = "\(secondsLeft)"
                v.countdownSub.stringValue = "seconds remaining"
            }
            let total = CGFloat(totalDuration > 0 ? totalDuration : 1)
            v.progressBar.progress = 1.0 - CGFloat(secondsLeft) / total
        }
    }

    private func syncCompanionsToComplete(milestone: Bool, milestoneMsg: String?) {
        for c in companions {
            let v = c.views
            v.heading.stringValue = heading.stringValue
            v.heading.textColor = heading.textColor
            v.body.stringValue = body.stringValue
            v.body.textColor = body.textColor
            v.detail.stringValue = detail.stringValue
            v.detail.textColor = detail.textColor

            let cv = c.window.contentView!
            let primaryCV = window.contentView!
            cv.layer?.backgroundColor = primaryCV.layer?.backgroundColor
            cv.layer?.borderWidth = primaryCV.layer?.borderWidth ?? 0
            cv.layer?.borderColor = primaryCV.layer?.borderColor
            cv.layer?.shadowColor = primaryCV.layer?.shadowColor
            cv.layer?.shadowRadius = primaryCV.layer?.shadowRadius ?? 0
            cv.layer?.shadowOpacity = primaryCV.layer?.shadowOpacity ?? 0
            cv.layer?.shadowOffset = primaryCV.layer?.shadowOffset ?? .zero

            v.body.isHidden = false
            v.detail.isHidden = false
            v.countdownLbl.isHidden = true
            v.countdownSub.isHidden = true
            v.progressBar.isHidden = true
            v.lottieView?.isHidden = false
            loadCurrentAnimation(into: v.lottieView)

            v.primaryBtn.setLabel("Thanks, Count!")
            v.primaryBtn.isHidden = false
            v.primaryPaired.isActive = false
            v.primaryCenterX.isActive = true
            v.secondaryBtn.isHidden = true
            v.dismissBtn.isHidden = true
            v.escHint.isHidden = true
            v.enterHint.isHidden = false

            resizeCompanion(c.window, to: fullHeight)
        }
    }

    private func loadCurrentAnimation(into lottieView: LottieAnimationView?) {
        guard let lv = lottieView, let path = currentAnimationPath else { return }
        if let animation = LottieAnimation.filepath(path) {
            lv.animation = animation
            lv.play()
        }
    }
}
