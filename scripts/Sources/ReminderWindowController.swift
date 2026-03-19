import Cocoa

/// Shows a pop-up for a single reminder — similar to the break prompt but simpler.
class ReminderWindowController: NSObject, NSWindowDelegate {

    let window: NSWindow
    private let reminder: Reminder
    private var escMonitor: Any?
    private var hasDismissed = false

    /// Called when the user dismisses the reminder.
    var onDismiss: (() -> Void)?

    init(reminder: Reminder) {
        self.reminder = reminder

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
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

        super.init()
        win.delegate = self
        buildUI()

        // Center on screen with cursor
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

        // Key monitors
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 || event.keyCode == 36 { // Esc or Enter
                self?.dismiss()
                return nil
            }
            return event
        }

        // Show with fade-in
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            win.animator().alphaValue = 1.0
        }

        SoundManager.shared.playPromptSound()

        // Auto-dismiss after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.dismiss()
        }
    }

    private func buildUI() {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true
        cv.layer?.borderWidth = 1
        cv.layer?.borderColor = Drac.currentLine.cgColor

        // Mascot
        let mascot = NSImageView()
        mascot.translatesAutoresizingMaskIntoConstraints = false
        mascot.imageScaling = .scaleProportionallyDown
        if let img = NSImage(contentsOfFile: assetPath("alex_final.png"))
                  ?? NSImage(contentsOfFile: assetPath("dracula.png")) {
            mascot.image = img
        }
        cv.addSubview(mascot)

        // Floating animation
        mascot.wantsLayer = true
        let floatAnim = CABasicAnimation(keyPath: "transform.translation.y")
        floatAnim.fromValue = 0
        floatAnim.toValue = -9
        floatAnim.duration = 2.0
        floatAnim.autoreverses = true
        floatAnim.repeatCount = .infinity
        floatAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mascot.layer?.add(floatAnim, forKey: "float")

        // "Reminder" heading
        let heading = makeLabel("🔔 Reminder", size: 16, weight: .bold, color: Drac.orange)
        cv.addSubview(heading)

        // Time label
        let timeLabel = makeLabel(reminder.timeString, size: 13, weight: .medium, color: Drac.comment)
        cv.addSubview(timeLabel)

        // Message
        let message = makeLabel(reminder.message, size: 14, weight: .regular, color: Drac.foreground)
        message.maximumNumberOfLines = 0
        message.lineBreakMode = .byWordWrapping
        message.preferredMaxLayoutWidth = 340
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cv.addSubview(message)

        // Dismiss button
        let dismissBtn = HoverButton(
            "Got it!",
            bg: Drac.currentLine,
            hover: Drac.selection,
            fg: Drac.purple,
            target: self,
            action: #selector(dismissTapped)
        )
        cv.addSubview(dismissBtn)

        // Enter hint
        let hint = makeLabel("Press Enter to dismiss", size: 12, weight: .regular, color: Drac.comment)
        cv.addSubview(hint)

        NSLayoutConstraint.activate([
            mascot.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            mascot.topAnchor.constraint(equalTo: cv.topAnchor, constant: 28),
            mascot.widthAnchor.constraint(equalToConstant: 64),
            mascot.heightAnchor.constraint(equalToConstant: 64),

            heading.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 16),
            heading.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            timeLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            timeLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            message.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 16),
            message.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            message.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            dismissBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -36),
            dismissBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            dismissBtn.widthAnchor.constraint(equalToConstant: 140),
            dismissBtn.heightAnchor.constraint(equalToConstant: 36),

            hint.topAnchor.constraint(equalTo: dismissBtn.bottomAnchor, constant: 8),
            hint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
        ])
    }

    @objc private func dismissTapped() {
        dismiss()
    }

    private func dismiss() {
        guard !hasDismissed else { return }
        hasDismissed = true

        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.onDismiss?()
        })
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }
}
