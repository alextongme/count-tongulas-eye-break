#!/usr/bin/env swift
// Count Tongula's Eye Break Reminder — Dracula Theme
// A native macOS window using the Dracula color palette and mascot.

import Cocoa

// ─── Dracula Palette ────────────────────────────────────────────────
struct Drac {
    static let background  = NSColor(srgbRed: 0x1A/255.0, green: 0x1B/255.0, blue: 0x26/255.0, alpha: 1)
    static let currentLine = NSColor(srgbRed: 0x22/255.0, green: 0x23/255.0, blue: 0x2E/255.0, alpha: 1)
    static let selection   = NSColor(srgbRed: 0x2D/255.0, green: 0x2F/255.0, blue: 0x3D/255.0, alpha: 1)
    static let foreground  = NSColor(srgbRed: 0xF0/255.0, green: 0xF0/255.0, blue: 0xEC/255.0, alpha: 1)
    static let comment     = NSColor(srgbRed: 0x62/255.0, green: 0x72/255.0, blue: 0xA4/255.0, alpha: 1)
    static let purple      = NSColor(srgbRed: 0x9B/255.0, green: 0x87/255.0, blue: 0xD5/255.0, alpha: 1)
    static let pink        = NSColor(srgbRed: 0xFF/255.0, green: 0x79/255.0, blue: 0xC6/255.0, alpha: 1)
    static let green       = NSColor(srgbRed: 0x50/255.0, green: 0xFA/255.0, blue: 0x7B/255.0, alpha: 1)
    static let cyan        = NSColor(srgbRed: 0x8B/255.0, green: 0xE9/255.0, blue: 0xFD/255.0, alpha: 1)
    static let orange      = NSColor(srgbRed: 0xFF/255.0, green: 0xB8/255.0, blue: 0x6C/255.0, alpha: 1)
    static let red         = NSColor(srgbRed: 0xFF/255.0, green: 0x55/255.0, blue: 0x55/255.0, alpha: 1)
    static let yellow      = NSColor(srgbRed: 0xF1/255.0, green: 0xFA/255.0, blue: 0x8C/255.0, alpha: 1)
}

// ─── Resolve asset path relative to the binary ─────────────────────
func assetPath(_ name: String) -> String {
    let exec = ProcessInfo.processInfo.arguments[0]
    let dir  = (exec as NSString).deletingLastPathComponent
    // Check next to the binary first (installed layout: ~/.eye-break/assets/)
    let candidate = (dir as NSString).appendingPathComponent("assets/\(name)")
    if FileManager.default.fileExists(atPath: candidate) { return candidate }
    // Fall back to repo layout (scripts/../assets/)
    let repoAssets = ((dir as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent("assets/\(name)")
    return repoAssets
}

// ─── Vampire Quotes ─────────────────────────────────────────────────
struct Quotes {
    static let prompt = [
        "I am Count Tongula, and I bid you...\nrest your eyes.",
        "Listen to them, the children of the night.\nBut first — rest your eyes.",
        "I never drink... coffee\nwithout an eye break.",
        "There are far worse things awaiting you\nthan death... like screen fatigue.",
        "To rest, to truly rest your eyes —\nthat must be glorious.",
        "Welcome. I bid you...\nlook away from your screen.",
        "The strength of the vampire is that\nno one believes in eye breaks.",
        "Enter freely and of your own will —\ninto this eye break.",
        "We are in Transylvania, and Transylvania\nis not England. Rest your eyes.",
        "I have crossed oceans of time\nto remind you: rest your eyes.",
    ]

    static let countdown = [
        "Gaze into the distance, mortal!",
        "The night calls — look toward it.",
        "Even vampires rest their eyes.",
        "Peer into the darkness beyond...",
        "Let your eyes wander the shadows.",
        "Stare into the void. It stares back.",
        "The distant horizon awaits your gaze.",
        "Look away... if you dare.",
    ]

    static let complete = [
        "Count Tongula is pleased.",
        "Excellent. Your eyes serve you well.",
        "The night rewards those who rest.",
        "You have earned the Count's approval.",
        "Your devotion to eye health is... noted.",
        "The vampire nods approvingly.",
        "Most impressive, mortal.",
        "Count Tongula himself would be proud.",
    ]

    static func random(_ list: [String]) -> String {
        list[Int.random(in: 0..<list.count)]
    }
}

// ─── Progress Bar ───────────────────────────────────────────────────
class ProgressBarView: NSView {
    var progress: CGFloat = 1.0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        Drac.currentLine.setFill(); bg.fill()
        if progress > 0 {
            var r = bounds; r.size.width *= progress
            let fg = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            Drac.purple.setFill(); fg.fill()
        }
    }
}

// ─── Hover Button ───────────────────────────────────────────────────
class HoverButton: NSButton {
    private let normalBg: NSColor
    private let hoverBg: NSColor
    private let fg: NSColor

    init(_ title: String, bg: NSColor, hover: NSColor, fg: NSColor = Drac.foreground,
         target: AnyObject?, action: Selector?) {
        normalBg = bg; hoverBg = hover; self.fg = fg
        super.init(frame: .zero)
        isBordered = false; wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = normalBg.cgColor
        self.target = target; self.action = action
        setLabel(title)
    }

    func setLabel(_ text: String) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: fg,
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with e: NSEvent) { layer?.backgroundColor = hoverBg.cgColor }
    override func mouseExited(with e: NSEvent)  { layer?.backgroundColor = normalBg.cgColor }
    required init?(coder: NSCoder) { fatalError() }
}

// ─── Hover Link (text-only button with color change on hover) ───────
class HoverLink: NSButton {
    private let normalColor: NSColor
    private let hoverColor: NSColor
    private let fontSize: CGFloat
    private let text: String

    init(_ title: String, color: NSColor = Drac.comment, hover: NSColor = Drac.foreground,
         size: CGFloat = 12, target: AnyObject?, action: Selector?) {
        normalColor = color; hoverColor = hover; fontSize = size; text = title
        super.init(frame: .zero)
        isBordered = false
        self.target = target; self.action = action
        applyStyle(normalColor)
    }

    private func applyStyle(_ color: NSColor) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: fontSize),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { applyStyle(hoverColor) }
    override func mouseExited(with e: NSEvent)  { applyStyle(normalColor) }
    required init?(coder: NSCoder) { fatalError() }
}

// ─── Label factory ──────────────────────────────────────────────────
func label(_ text: String = "", size: CGFloat, weight: NSFont.Weight = .regular,
           color: NSColor = Drac.foreground) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color; l.backgroundColor = .clear
    l.alignment = .center; l.lineBreakMode = .byWordWrapping
    l.maximumNumberOfLines = 0
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

// ─── Main Controller ────────────────────────────────────────────────
class EyeBreakController: NSObject, NSWindowDelegate {
    let window: NSWindow

    // Views
    let mascot      = NSImageView()
    let heading     = label(size: 22, weight: .bold, color: Drac.purple)
    let body        = label(size: 15, color: Drac.foreground)
    let detail      = label(size: 15, color: Drac.foreground)
    let countdownLbl = label(size: 80, weight: .heavy, color: Drac.green)
    let countdownSub = label(size: 14, color: Drac.comment)
    let progressBar  = ProgressBarView()
    var primaryBtn:   HoverButton!
    var secondaryBtn: HoverButton!
    var dismissBtn:   HoverLink!

    // Constraints swapped between phases
    var primaryCenterX: NSLayoutConstraint!
    var primaryPaired:  NSLayoutConstraint!

    var secondsLeft = 20
    var timer: Timer?

    override init() {
        // ── Window ──
        let w: CGFloat = 460, h: CGFloat = 440
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Drac.background
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        super.init()
        window.delegate = self

        // ── Mascot image ──
        if let img = NSImage(contentsOfFile: assetPath("dracula.svg"))
                  ?? NSImage(contentsOfFile: assetPath("dracula.png")) {
            mascot.image = img
        }
        mascot.imageScaling = .scaleProportionallyDown
        mascot.translatesAutoresizingMaskIntoConstraints = false

        // ── Buttons ──
        primaryBtn   = HoverButton("", bg: Drac.currentLine, hover: Drac.selection, fg: Drac.purple,
                                   target: self, action: #selector(primaryTapped))
        secondaryBtn = HoverButton("", bg: Drac.currentLine, hover: Drac.comment,
                                   target: self, action: #selector(snoozeTapped))

        // ── Dismiss link ──
        dismissBtn = HoverLink("Not now — remind me in 20 min",
                               color: Drac.comment, hover: Drac.pink, size: 13,
                               target: self, action: #selector(dismissTapped))
        dismissBtn.translatesAutoresizingMaskIntoConstraints = false

        layout()
        showPrompt(allowSnooze: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ── Auto Layout ──
    func layout() {
        let cv = window.contentView!
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor

        progressBar.translatesAutoresizingMaskIntoConstraints  = false
        primaryBtn.translatesAutoresizingMaskIntoConstraints   = false
        secondaryBtn.translatesAutoresizingMaskIntoConstraints = false

        [mascot, heading, body, detail, countdownLbl, countdownSub,
         progressBar, primaryBtn!, secondaryBtn!, dismissBtn!].forEach { cv.addSubview($0) }

        // Primary button: two mutually exclusive horizontal positions
        primaryCenterX = primaryBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor)
        primaryPaired  = primaryBtn.trailingAnchor.constraint(equalTo: cv.centerXAnchor, constant: -8)

        NSLayoutConstraint.activate([
            // Mascot
            mascot.topAnchor.constraint(equalTo: cv.topAnchor, constant: 36),
            mascot.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            mascot.widthAnchor.constraint(equalToConstant: 110),
            mascot.heightAnchor.constraint(equalToConstant: 110),

            // Heading
            heading.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 14),
            heading.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 32),
            heading.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -32),

            // Body
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            body.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            body.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            // Detail
            detail.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 4),
            detail.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            detail.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -40),

            // Countdown number (overlaps body/detail area — toggled)
            countdownLbl.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            countdownLbl.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Countdown subtitle
            countdownSub.topAnchor.constraint(equalTo: countdownLbl.bottomAnchor, constant: -2),
            countdownSub.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Progress bar
            progressBar.topAnchor.constraint(equalTo: countdownSub.bottomAnchor, constant: 14),
            progressBar.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            progressBar.widthAnchor.constraint(equalToConstant: 300),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            // Buttons — vertical
            primaryBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -28),
            primaryBtn.widthAnchor.constraint(equalToConstant: 160),
            primaryBtn.heightAnchor.constraint(equalToConstant: 42),

            secondaryBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -28),
            secondaryBtn.leadingAnchor.constraint(equalTo: cv.centerXAnchor, constant: 8),
            secondaryBtn.widthAnchor.constraint(equalToConstant: 160),
            secondaryBtn.heightAnchor.constraint(equalToConstant: 42),

            // Dismiss link
            dismissBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            dismissBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
        ])
    }

    // ── Phase: Prompt ──
    func showPrompt(allowSnooze: Bool) {
        heading.stringValue  = "Time for an eye break!"
        body.stringValue     = "Look at something 20 feet away for 20 seconds."
        detail.stringValue   = ""

        body.isHidden = false; detail.isHidden = false
        countdownLbl.isHidden = true; countdownSub.isHidden = true; progressBar.isHidden = true

        primaryBtn.setLabel("Start Break")
        primaryBtn.isHidden = false
        dismissBtn.isHidden = false

        if allowSnooze {
            secondaryBtn.setLabel("Snooze 5 min")
            secondaryBtn.isHidden = false
            primaryCenterX.isActive = false
            primaryPaired.isActive  = true
        } else {
            secondaryBtn.isHidden = true
            primaryPaired.isActive  = false
            primaryCenterX.isActive = true
        }
    }

    // ── Phase: Countdown ──
    func showCountdown() {
        heading.stringValue = Quotes.random(Quotes.countdown)

        body.isHidden = true; detail.isHidden = true
        countdownLbl.isHidden = false; countdownSub.isHidden = false; progressBar.isHidden = false
        primaryBtn.isHidden = true; secondaryBtn.isHidden = true; dismissBtn.isHidden = false

        secondsLeft = 20
        updateCountdown()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.secondsLeft -= 1
            self.updateCountdown()
            if self.secondsLeft <= 0 {
                self.timer?.invalidate(); self.timer = nil
                self.showComplete()
            }
        }
    }

    func updateCountdown() {
        countdownLbl.stringValue = "\(secondsLeft)"
        countdownSub.stringValue = "seconds remaining"
        progressBar.progress     = CGFloat(secondsLeft) / 20.0
    }

    // ── Phase: Complete ──
    func showComplete() {
        playSound("Hero")

        heading.stringValue = "Break complete!"
        heading.textColor   = Drac.green
        body.stringValue    = Quotes.random(Quotes.complete)
        detail.stringValue  = "You may return to your screen."

        body.isHidden = false; detail.isHidden = false
        countdownLbl.isHidden = true; countdownSub.isHidden = true; progressBar.isHidden = true

        primaryBtn.setLabel("Thanks, Count!")
        primaryBtn.isHidden = false
        secondaryBtn.isHidden = true; dismissBtn.isHidden = true
        primaryPaired.isActive  = false
        primaryCenterX.isActive = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.quit() }
    }

    // ── Actions ──
    @objc func primaryTapped() {
        if primaryBtn.attributedTitle.string == "Thanks, Count!" { quit() }
        else { showCountdown() }
    }

    @objc func dismissTapped() { quit() }

    @objc func snoozeTapped() {
        window.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self = self else { return }
            self.playSound("Basso")
            self.showPrompt(allowSnooze: false)
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func quit() { timer?.invalidate(); NSApp.terminate(nil) }

    func playSound(_ name: String) { NSSound(named: NSSound.Name(name))?.play() }

    func windowWillClose(_ n: Notification) { quit() }
}

// ─── Screenshot helper ──────────────────────────────────────────────
func captureWindow(_ window: NSWindow, to path: String) {
    guard let view = window.contentView else { return }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)

    let size = view.bounds.size
    let radius: CGFloat = 10
    let rounded = NSImage(size: size)
    rounded.lockFocus()
    let clip = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                            xRadius: radius, yRadius: radius)
    clip.addClip()
    rep.draw(in: NSRect(origin: .zero, size: size))
    rounded.unlockFocus()

    guard let tiff = rounded.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let data = bmp.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

// ─── Entry Point ────────────────────────────────────────────────────
let args = ProcessInfo.processInfo.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = EyeBreakController()

if args.contains("--screenshot") {
    let dir = args.last(where: { $0.hasPrefix("--outdir=") })
        .map { String($0.dropFirst("--outdir=".count)) } ?? "/tmp"

    // Prompt phase (already shown)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        captureWindow(controller.window, to: "\(dir)/screenshot-prompt.png")
        // Countdown phase
        controller.showCountdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            captureWindow(controller.window, to: "\(dir)/screenshot-countdown.png")
            controller.timer?.invalidate()
            // Complete phase
            controller.heading.textColor = Drac.green
            controller.heading.stringValue = "Break complete!"
            controller.body.stringValue = "The night rewards those who rest."
            controller.detail.stringValue = "You may return to your screen."
            controller.body.isHidden = false; controller.detail.isHidden = false
            controller.countdownLbl.isHidden = true; controller.countdownSub.isHidden = true
            controller.progressBar.isHidden = true
            controller.primaryBtn.setLabel("Thanks, Count!")
            controller.primaryBtn.isHidden = false; controller.secondaryBtn.isHidden = true
            controller.primaryPaired.isActive = false; controller.primaryCenterX.isActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                captureWindow(controller.window, to: "\(dir)/screenshot-complete.png")
                NSApp.terminate(nil)
            }
        }
    }
} else {
    controller.playSound("Basso")
}

app.run()
