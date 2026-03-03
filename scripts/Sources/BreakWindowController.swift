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
    private var animationFiles: [String] = []
    private var unusedAnimations: [String] = []
    private var escMonitor: Any?

    var primaryCenterX: NSLayoutConstraint!
    var primaryPaired: NSLayoutConstraint!
    var dismissAtBottom: NSLayoutConstraint!
    var dismissBelowProgress: NSLayoutConstraint!
    var mascotTopFixed: NSLayoutConstraint!
    var countdownCentering: [NSLayoutConstraint] = []


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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
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
        self.countdownLbl = makeLabel("", size: 80, weight: .heavy, color: Drac.green)
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
            "Not now — remind me later",
            color: Drac.comment,
            hover: Drac.pink,
            size: 13,
            target: self,
            action: #selector(dismissTapped)
        )

        // Esc hint label
        escHint = makeLabel("Press Esc to skip", size: 11, weight: .regular, color: Drac.comment)
        escHint.alphaValue = 0.6
        escHint.isHidden = true

        // Esc key monitor
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc key
                if !Preferences.shared.strictMode {
                    self?.finishWithResult(.skipped)
                }
                return nil
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
                  progressBar, primaryBtn!, secondaryBtn!, dismissBtn!, escHint!] as [NSView] {
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
            mascot.widthAnchor.constraint(equalToConstant: 90),
            mascot.heightAnchor.constraint(equalToConstant: 90),

            // Heading
            heading.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 32),
            heading.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -32),

            // Body
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14),
            body.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            body.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            // Detail
            detail.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 14),
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
            escHint.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
        ])

        // Mascot top: fixed for prompt/complete, flexible for countdown centering
        mascotTopFixed = mascot.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24)

        dismissAtBottom = dismissBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -18)
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

    private let fullHeight: CGFloat = 520

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
        // mascot(90) + gap(20) + heading + gap(20) + countdown + gap(-2) + sub
        // + gap(24) + progress(6) + gap(40) + dismiss
        let content = 90 + 20 + headingH + 20 + countdownH + (-2) + subH + 24 + 6 + 40 + dismissH
        return content + 70  // 35px padding top + bottom
    }

    // MARK: - Animation

    private func loadRandomAnimation() {
        guard let lv = lottieView, !animationFiles.isEmpty else { return }
        if unusedAnimations.isEmpty {
            unusedAnimations = animationFiles.shuffled()
        }
        let path = unusedAnimations.removeLast()
        if let animation = LottieAnimation.filepath(path) {
            lv.animation = animation
            lv.play()
        }
    }

    // MARK: - Screen States

    func showPrompt() {
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
    }

    func showCountdown() {
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
        progressBar.progress = CGFloat(secondsLeft) / total
    }

    func showComplete() {
        SoundManager.shared.playCompleteSound()

        timer?.invalidate()
        timer = nil

        heading.stringValue = "Break complete!"
        heading.textColor = Drac.green

        body.stringValue = Quotes.random(Quotes.complete)
        detail.stringValue = "You may return to your screen."

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
        dismissBelowProgress.isActive = false
        dismissAtBottom.isActive = true
        NSLayoutConstraint.deactivate(countdownCentering)
        mascotTopFixed.isActive = true

        resizeWindow(to: fullHeight)

        lottieView?.isHidden = false
        loadRandomAnimation()

        let delay = Preferences.shared.autoQuitDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
            self?.finishWithResult(.completed)
        }
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

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.window.animator().alphaValue = 0
            for ow in self.overlayWindows {
                ow.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            for ow in self.overlayWindows {
                ow.orderOut(nil)
            }
            self.overlayWindows.removeAll()
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
            panel.collectionBehavior = [.canJoinAllSpaces]
            panel.isMovableByWindowBackground = false
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

        let cloudPath = assetPath("clouds.png")
        guard let cloudImage = NSImage(contentsOfFile: cloudPath),
              let cgImage = cloudImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let h = screenFrame.height
        let texW = CGFloat(cgImage.width)

        // Two copies side by side for seamless scrolling
        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: texW * 2, height: h)

        for i in 0..<2 {
            let tile = CALayer()
            tile.frame = CGRect(x: CGFloat(i) * texW, y: 0, width: texW, height: h)
            tile.contents = cgImage
            tile.contentsGravity = .resizeAspectFill
            container.addSublayer(tile)
        }

        container.opacity = 0
        cv.layer?.addSublayer(container)

        // Start shifted left so clouds fill the screen, scroll right for drift effect
        let scroll = CABasicAnimation(keyPath: "position.x")
        scroll.fromValue = container.position.x - texW
        scroll.toValue = container.position.x
        scroll.duration = 80
        scroll.repeatCount = .infinity
        container.add(scroll, forKey: "scroll")

        // Fade in
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 0.35
        fadeIn.duration = 2.5
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        container.add(fadeIn, forKey: "fadeIn")
    }

    // MARK: - Mascot Animation

    private func startMascotAnimation() {
        mascot.wantsLayer = true

        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 0
        animation.toValue = -5
        animation.duration = 2.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        mascot.layer?.add(animation, forKey: "float")
    }
}
