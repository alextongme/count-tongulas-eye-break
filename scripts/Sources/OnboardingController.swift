import Cocoa

// Borderless window that can become key but cannot be moved
private class FixedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Content view that accepts first mouse click (bypasses activate-on-click for borderless windows)
private class FirstClickView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class OnboardingController: NSObject {
    static let didCompleteNotification = Notification.Name("CountTongulaOnboardingComplete")

    let window: NSWindow
    var intervalSlider: NSSlider!
    var intervalLabel: NSTextField!
    var durationSlider: NSSlider!
    var durationLabel: NSTextField!

    private let W: CGFloat = 500
    private let H: CGFloat = 520

    override init() {
        let win = FixedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.isMovableByWindowBackground = false
        win.hasShadow = true
        win.level = .floating
        win.contentView = FirstClickView(frame: NSRect(x: 0, y: 0, width: 500, height: 520))
        self.window = win

        super.init()
        buildUI()

        // Always dead center on the screen with the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let screen = targetScreen {
            let sf = screen.visibleFrame
            let wf = win.frame
            let x = sf.minX + (sf.width - wf.width) / 2
            let y = sf.minY + (sf.height - wf.height) / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            win.center()
        }
    }

    // Frame-based layout — no Auto Layout ambiguity.
    func buildUI() {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 16
        cv.layer?.masksToBounds = true

        // ── Mascot (centered, top — clipped to circle) ──
        let mascotSize: CGFloat = 120
        let mascotY = H - 36 - mascotSize
        let mascotImage = NSImageView(frame: NSRect(
            x: (W - mascotSize) / 2, y: mascotY, width: mascotSize, height: mascotSize
        ))
        mascotImage.imageScaling = .scaleProportionallyDown
        mascotImage.wantsLayer = true
        if let img = NSImage(contentsOfFile: assetPath("dracula.svg"))
                  ?? NSImage(contentsOfFile: assetPath("dracula.png")) {
            mascotImage.image = img
        }
        cv.addSubview(mascotImage)

        // Floating animation (matches the break window)
        let floatAnim = CABasicAnimation(keyPath: "transform.translation.y")
        floatAnim.fromValue = 0
        floatAnim.toValue = -5
        floatAnim.duration = 2.0
        floatAnim.autoreverses = true
        floatAnim.repeatCount = .infinity
        floatAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mascotImage.layer?.add(floatAnim, forKey: "float")

        // ── Heading ──
        let headingH: CGFloat = 28
        let headingY = mascotY - 14 - headingH
        let heading = NSTextField(frame: NSRect(x: 24, y: headingY, width: W - 48, height: headingH))
        heading.stringValue = "Welcome to Count Tongula's Eye Break"
        heading.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        heading.textColor = Drac.purple
        heading.backgroundColor = .clear
        heading.isBezeled = false
        heading.isEditable = false
        heading.isSelectable = false
        heading.alignment = .center
        cv.addSubview(heading)

        // ── Rule text ──
        let ruleText = "Every 20 minutes, take a 20-second break\nand look at something 20 feet away.\n\nThe Count will remind you."
        let ruleH: CGFloat = 80
        let ruleY = headingY - 8 - ruleH
        let ruleLabel = NSTextField(frame: NSRect(x: 40, y: ruleY, width: W - 80, height: ruleH))
        ruleLabel.stringValue = ruleText
        ruleLabel.font = NSFont.systemFont(ofSize: 14)
        ruleLabel.textColor = Drac.foreground
        ruleLabel.backgroundColor = .clear
        ruleLabel.isBezeled = false
        ruleLabel.isEditable = false
        ruleLabel.isSelectable = false
        ruleLabel.alignment = .center
        ruleLabel.maximumNumberOfLines = 0
        ruleLabel.lineBreakMode = .byWordWrapping
        cv.addSubview(ruleLabel)

        // ── Slider rows (aligned: both labels 110px, sliders same width) ──
        let rowH: CGFloat = 24
        let labelW: CGFloat = 110  // Same width for both row labels
        let valueW: CGFloat = 60
        let sliderX: CGFloat = 32 + labelW + 12
        let sliderW: CGFloat = W - sliderX - 8 - valueW - 32

        // Break interval row
        let sliderRowY = ruleY - 24 - rowH

        let intervalRowLabel = makeField("Break every", size: 13, color: Drac.cyan)
        intervalRowLabel.frame = NSRect(x: 32, y: sliderRowY, width: labelW, height: rowH)
        cv.addSubview(intervalRowLabel)

        intervalLabel = makeField("20 min", size: 13, color: Drac.comment)
        intervalLabel.alignment = .right
        intervalLabel.frame = NSRect(x: W - 32 - valueW, y: sliderRowY, width: valueW, height: rowH)
        cv.addSubview(intervalLabel)

        intervalSlider = NSSlider(frame: NSRect(x: sliderX, y: sliderRowY, width: sliderW, height: rowH))
        intervalSlider.minValue = 5
        intervalSlider.maxValue = 60
        intervalSlider.intValue = 20
        intervalSlider.isContinuous = true
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalChanged)
        cv.addSubview(intervalSlider)

        // Break duration row
        let durationRowY = sliderRowY - 16 - rowH

        let durationRowLabel = makeField("Break duration", size: 13, color: Drac.cyan)
        durationRowLabel.frame = NSRect(x: 32, y: durationRowY, width: labelW, height: rowH)
        cv.addSubview(durationRowLabel)

        durationLabel = makeField("20 sec", size: 13, color: Drac.comment)
        durationLabel.alignment = .right
        durationLabel.frame = NSRect(x: W - 32 - valueW, y: durationRowY, width: valueW, height: rowH)
        cv.addSubview(durationLabel)

        durationSlider = NSSlider(frame: NSRect(x: sliderX, y: durationRowY, width: sliderW, height: rowH))
        durationSlider.minValue = 5
        durationSlider.maxValue = 60
        durationSlider.intValue = 20
        durationSlider.isContinuous = true
        durationSlider.target = self
        durationSlider.action = #selector(durationChanged)
        cv.addSubview(durationSlider)

        // ── "Begin the Night Watch" button ──
        let btnW: CGFloat = 220
        let btnH: CGFloat = 44
        let btnY = durationRowY - 32 - btnH
        let startButton = HoverButton(
            "Begin the Night Watch",
            bg: Drac.green,
            hover: Drac.cyan,
            fg: Drac.background,
            target: self,
            action: #selector(getStarted)
        )
        startButton.frame = NSRect(x: (W - btnW) / 2, y: btnY, width: btnW, height: btnH)
        startButton.translatesAutoresizingMaskIntoConstraints = true
        cv.addSubview(startButton)

        // ── "I'll configure later" link ──
        let skipButton = HoverLink(
            "I'll configure later",
            color: Drac.comment,
            hover: Drac.foreground,
            size: 12,
            target: self,
            action: #selector(skipTapped)
        )
        skipButton.translatesAutoresizingMaskIntoConstraints = true
        skipButton.sizeToFit()
        let skipW = skipButton.frame.width
        skipButton.frame = NSRect(x: (W - skipW) / 2, y: btnY - 12 - 20, width: skipW, height: 20)
        cv.addSubview(skipButton)
    }

    // Simple text field factory (frame-based, no Auto Layout)
    private func makeField(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let f = NSTextField(frame: .zero)
        f.stringValue = text
        f.font = NSFont.systemFont(ofSize: size)
        f.textColor = color
        f.backgroundColor = .clear
        f.isBezeled = false
        f.isEditable = false
        f.isSelectable = false
        return f
    }

    @objc func getStarted() {
        let intervalMin = Int(intervalSlider.intValue)
        let durationSec = Int(durationSlider.intValue)
        Preferences.shared.breakInterval = intervalMin * 60
        Preferences.shared.breakDuration = durationSec
        Preferences.shared.hasCompletedOnboarding = true
        window.orderOut(nil)
        NotificationCenter.default.post(name: OnboardingController.didCompleteNotification, object: nil)
    }

    @objc func skipTapped() {
        Preferences.shared.hasCompletedOnboarding = true
        window.orderOut(nil)
        NotificationCenter.default.post(name: OnboardingController.didCompleteNotification, object: nil)
    }

    @objc func intervalChanged() {
        let val = Int(intervalSlider.intValue)
        intervalLabel.stringValue = "\(val) min"
    }

    @objc func durationChanged() {
        let val = Int(durationSlider.intValue)
        durationLabel.stringValue = "\(val) sec"
    }
}
