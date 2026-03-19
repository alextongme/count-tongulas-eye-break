import Cocoa
import Lottie

// MARK: - Screen Blend Helper

/// Converts black background to transparency: alpha = max(R,G,B) per pixel.
/// Replicates CSS `mix-blend-mode: screen` against a black backdrop.
func screenBlendToAlpha(_ src: CGImage) -> CGImage? {
    let w = src.width, h = src.height
    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }

    let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    for i in 0..<(w * h) {
        let off = i * 4
        let r = ptr[off], g = ptr[off + 1], b = ptr[off + 2]
        let luminance = max(r, max(g, b))
        // Set alpha to luminance; premultiply RGB
        let a = Float(luminance) / 255.0
        ptr[off]     = UInt8(Float(r) * a)   // R premul
        ptr[off + 1] = UInt8(Float(g) * a)   // G premul
        ptr[off + 2] = UInt8(Float(b) * a)   // B premul
        ptr[off + 3] = luminance             // A
    }

    return ctx.makeImage()
}

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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
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
        self.heading      = makeLabel("", size: 18, weight: .bold, color: Drac.purple)
        self.body         = makeLabel("", size: 14, weight: .regular, color: Drac.foreground)
        self.detail       = makeLabel("", size: 13, weight: .medium, color: Drac.comment)
        self.countdownLbl = {
        let lbl = NSTextField(labelWithString: "")
        lbl.font = dmMono(size: 56, weight: .medium)
        lbl.textColor = Drac.green
        lbl.alignment = .center
        lbl.lineBreakMode = .byWordWrapping
        lbl.maximumNumberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
        self.countdownSub = makeLabel("", size: 12, weight: .regular, color: Drac.comment)
        self.progressBar  = ProgressBarView()

        super.init()

        win.delegate = self

        // Buttons
        primaryBtn = HoverButton(
            "Start Break",
            bg: Drac.currentLine,
            hover: Drac.selection,
            fg: Drac.purple,
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
        escHint = makeLabel("Press Esc to skip", size: 12, weight: .regular, color: Drac.comment)

        // Enter hint label (shown on complete screen)
        enterHint = makeLabel("Press Enter to dismiss", size: 12, weight: .regular, color: Drac.comment)
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
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true

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
            lbl.preferredMaxLayoutWidth = 376
            lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        NSLayoutConstraint.activate([
            // Mascot
            mascot.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            mascot.widthAnchor.constraint(equalToConstant: 80),
            mascot.heightAnchor.constraint(equalToConstant: 80),

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
            primaryBtn.widthAnchor.constraint(equalToConstant: 140),
            primaryBtn.heightAnchor.constraint(equalToConstant: 36),

            // Secondary button
            secondaryBtn.bottomAnchor.constraint(equalTo: dismissBtn.topAnchor, constant: -14),
            secondaryBtn.leadingAnchor.constraint(equalTo: cv.centerXAnchor, constant: 8),
            secondaryBtn.widthAnchor.constraint(equalToConstant: 140),
            secondaryBtn.heightAnchor.constraint(equalToConstant: 36),

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
                lv.widthAnchor.constraint(equalToConstant: 140),
                lv.heightAnchor.constraint(equalToConstant: 140),
            ])
        }

        // Paired layout: two buttons side by side
        primaryPaired = primaryBtn.trailingAnchor.constraint(equalTo: cv.centerXAnchor, constant: -8)
        // Centered layout: single button
        primaryCenterX = primaryBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor)
    }

    private let fullHeight: CGFloat = 480

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
        // mascot(80) + gap(16) + heading + gap(16) + countdown + gap(-2) + sub
        // + gap(20) + progress(6) + gap(32) + dismiss
        let content = 80 + 16 + headingH + 16 + countdownH + (-2) + subH + 20 + 6 + 32 + dismissH
        return content + 140  // 70px padding top + bottom
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
            cv.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x1F/255.0, blue: 0x38/255.0, alpha: 1).cgColor
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
        cv.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x1F/255.0, blue: 0x38/255.0, alpha: 1).cgColor
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
            panel.backgroundColor = Drac.background
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
        }
    }

    private func addOverlayClouds(to panel: NSPanel, screenFrame: NSRect) {
        guard let cv = panel.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.masksToBounds = true

        let screenW = screenFrame.width
        let h = screenFrame.height

        // Load two fog textures (matching the alextong.me layered fog)
        let fog1Path = assetPath("fog1-baked.png")
        let fog2Path = assetPath("fog2-baked.png")
        guard let fog1Image = NSImage(contentsOfFile: fog1Path),
              let fog1CG = fog1Image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let fog2Image = NSImage(contentsOfFile: fog2Path),
              let fog2CG = fog2Image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        // Container for all fog layers
        let fogContainer = CALayer()
        fogContainer.frame = CGRect(x: 0, y: 0, width: screenW, height: h)
        fogContainer.masksToBounds = true
        cv.layer?.addSublayer(fogContainer)

        // ── Night sky: stars + moon (matching alextong.me) ──

        // Starfield — random twinkling dots
        let starCount = 60
        for _ in 0..<starCount {
            let star = CALayer()
            let radius = CGFloat.random(in: 0.4...1.6)
            let x = CGFloat.random(in: 0...screenW)
            let y = CGFloat.random(in: 0...h)
            star.frame = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
            star.cornerRadius = radius
            star.backgroundColor = Drac.foreground.cgColor

            let baseOpacity = Float.random(in: 0.3...0.8)
            star.opacity = baseOpacity

            // Twinkle animation
            let twinkle = CAKeyframeAnimation(keyPath: "opacity")
            let peak = min(baseOpacity + Float.random(in: 0.15...0.4), 1.0)
            let dip = max(baseOpacity - Float.random(in: 0.1...0.3), 0.05)
            twinkle.values = [baseOpacity, peak, baseOpacity, dip, baseOpacity].map { NSNumber(value: $0) }
            twinkle.keyTimes = [0, 0.25, 0.5, 0.75, 1.0]
            twinkle.duration = Double.random(in: 3...8)
            twinkle.repeatCount = .infinity
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Stagger start times so stars don't all pulse in sync
            twinkle.beginTime = CACurrentMediaTime() + Double.random(in: 0...5)
            star.add(twinkle, forKey: "twinkle")

            fogContainer.addSublayer(star)
        }

        // Moon — positioned top-right with shimmer glow
        // The moon-glow.png has a black background (designed for CSS screen blend).
        // Convert black → transparent by setting alpha = max(R,G,B) per pixel.
        if let moonImage = NSImage(contentsOfFile: assetPath("moon-glow.png")),
           let moonCG = moonImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let processedCG = screenBlendToAlpha(moonCG) {
            let moonSize = min(screenW, h) * 0.30
            let moonLayer = CALayer()
            moonLayer.frame = CGRect(
                x: screenW * 0.80 - moonSize / 2,
                y: h * 0.78 - moonSize / 2,
                width: moonSize,
                height: moonSize
            )
            moonLayer.contents = processedCG
            moonLayer.contentsGravity = .resizeAspect
            moonLayer.opacity = 0.9

            // Shimmer — slow brightness pulse
            let shimmer = CAKeyframeAnimation(keyPath: "opacity")
            shimmer.values = [0.80, 0.92, 0.78, 0.88, 0.80].map { NSNumber(value: $0) }
            shimmer.keyTimes = [0, 0.3, 0.5, 0.75, 1.0]
            shimmer.duration = 7
            shimmer.repeatCount = .infinity
            shimmer.calculationMode = .cubic
            moonLayer.add(shimmer, forKey: "shimmer")

            fogContainer.addSublayer(moonLayer)
        }

        // Each layer is 200% screen width, two fog images side by side with soft-edge masks,
        // drifting left infinitely. Different speeds + opacity pulses create depth.
        struct FogLayerSpec {
            let cgImage: CGImage
            let driftDuration: Double       // how long to scroll one full 50% (left loop)
            let opacityKeys: [NSNumber]     // keyTimes
            let opacityVals: [Float]        // opacity values at each keyTime
            let opacityDuration: Double
            let bobDuration: Double
            let bobKeyframes: [CGFloat]     // translateY keyframes (4 values: 0%, ~25%, ~50%, ~75%)
        }

        let layers: [FogLayerSpec] = [
            FogLayerSpec(
                cgImage: fog1CG,
                driftDuration: 60,
                opacityKeys: [0, 0.22, 0.40, 0.58, 0.80, 1.0],
                opacityVals: [0.18, 0.26, 0.21, 0.24, 0.18, 0.18],
                opacityDuration: 30,
                bobDuration: 18,
                bobKeyframes: [0, -6, 4, -3]
            ),
            FogLayerSpec(
                cgImage: fog2CG,
                driftDuration: 45,
                opacityKeys: [0, 0.25, 0.50, 0.80, 1.0],
                opacityVals: [0.15, 0.10, 0.08, 0.13, 0.15],
                opacityDuration: 42,
                bobDuration: 24,
                bobKeyframes: [0, 5, -7, 2]
            ),
            FogLayerSpec(
                cgImage: fog2CG,
                driftDuration: 35,
                opacityKeys: [0, 0.27, 0.52, 0.68, 1.0],
                opacityVals: [0.12, 0.06, 0.10, 0.06, 0.12],
                opacityDuration: 36,
                bobDuration: 14,
                bobKeyframes: [0, -4, 6, -2]
            ),
        ]

        for spec in layers {
            let stripW = screenW * 2
            let imgAspect = CGFloat(spec.cgImage.width) / CGFloat(spec.cgImage.height)
            let singleW = max(ceil(imgAspect * h), screenW * 0.7)

            // Bob container — vertical floating motion
            let bobLayer = CALayer()
            bobLayer.frame = CGRect(x: 0, y: 0, width: stripW, height: h)

            // Two copies of the fog image, side by side, with soft-edge gradient masks
            for i in 0..<2 {
                let img = CALayer()
                let xOff = CGFloat(i) * singleW * 0.5 - singleW * 0.1
                img.frame = CGRect(x: xOff, y: 0, width: singleW, height: h)
                img.contents = spec.cgImage
                img.contentsGravity = .resizeAspectFill

                // Soft-edge gradient mask (transparent → opaque → opaque → transparent)
                let mask = CAGradientLayer()
                mask.frame = img.bounds
                mask.startPoint = CGPoint(x: 0, y: 0.5)
                mask.endPoint = CGPoint(x: 1, y: 0.5)
                mask.colors = [
                    NSColor.clear.cgColor,
                    NSColor.black.cgColor,
                    NSColor.black.cgColor,
                    NSColor.clear.cgColor,
                ]
                mask.locations = [0, 0.2, 0.8, 1.0]
                img.mask = mask

                bobLayer.addSublayer(img)
            }

            // Bob animation
            let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bob.values = spec.bobKeyframes.map { NSNumber(value: Double($0)) }
            bob.keyTimes = [0, 0.27, 0.52, 0.78]
            bob.duration = spec.bobDuration
            bob.repeatCount = .infinity
            bob.calculationMode = .cubic
            bobLayer.add(bob, forKey: "bob")

            // Drift container — horizontal infinite scroll
            let driftLayer = CALayer()
            driftLayer.frame = CGRect(x: 0, y: 0, width: stripW, height: h)
            driftLayer.addSublayer(bobLayer)

            let drift = CABasicAnimation(keyPath: "transform.translation.x")
            drift.fromValue = 0
            drift.toValue = -stripW * 0.5
            drift.duration = spec.driftDuration
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .linear)
            driftLayer.add(drift, forKey: "drift")

            // Opacity pulse
            let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnim.values = spec.opacityVals.map { NSNumber(value: $0) }
            opacityAnim.keyTimes = spec.opacityKeys
            opacityAnim.duration = spec.opacityDuration
            opacityAnim.repeatCount = .infinity
            opacityAnim.calculationMode = .linear
            driftLayer.add(opacityAnim, forKey: "opacityPulse")

            fogContainer.addSublayer(driftLayer)
        }

        // Fade in the entire fog wrapper
        fogContainer.opacity = 0
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1.0
        fadeIn.duration = 2.5
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        fogContainer.add(fadeIn, forKey: "fadeIn")
    }

    // MARK: - Wake Recovery

    /// Rebuilds all CA-driven visuals that freeze when macOS sleeps.
    /// The render server is suspended on sleep and CACurrentMediaTime() jumps
    /// forward on wake, leaving beginTime-anchored animations expired/stuck.
    private func restoreAnimationsAfterWake() {
        // 1. Tear down and rebuild overlay windows (fog)
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: fullHeight),
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
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true

        // Mascot
        let cMascot = NSImageView()
        cMascot.translatesAutoresizingMaskIntoConstraints = false
        cMascot.imageScaling = .scaleProportionallyDown
        cMascot.image = mascot.image

        // Labels
        let cHeading      = makeLabel("", size: 18, weight: .bold, color: Drac.purple)
        let cBody         = makeLabel("", size: 14, weight: .regular, color: Drac.foreground)
        let cDetail        = makeLabel("", size: 13, weight: .medium, color: Drac.comment)
        let cCountdownLbl: NSTextField = {
            let lbl = NSTextField(labelWithString: "")
            lbl.font = dmMono(size: 56, weight: .medium)
            lbl.textColor = Drac.green
            lbl.alignment = .center
            lbl.lineBreakMode = .byWordWrapping
            lbl.maximumNumberOfLines = 0
            lbl.translatesAutoresizingMaskIntoConstraints = false
            return lbl
        }()
        let cCountdownSub = makeLabel("", size: 12, weight: .regular, color: Drac.comment)
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
            bg: Drac.currentLine, hover: Drac.selection, fg: Drac.purple,
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
        let cEscHint = makeLabel("Press Esc to skip", size: 12, weight: .regular, color: Drac.comment)
        cEscHint.isHidden = true
        let cEnterHint = makeLabel("Press Enter to dismiss", size: 12, weight: .regular, color: Drac.comment)
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
            lbl.preferredMaxLayoutWidth = 376
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
                lv.widthAnchor.constraint(equalToConstant: 140),
                lv.heightAnchor.constraint(equalToConstant: 140),
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
