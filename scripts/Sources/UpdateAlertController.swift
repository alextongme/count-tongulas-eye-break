import Cocoa

private class UpdateAlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class UpdateAlertController: NSObject {
    let window: NSWindow

    private var release: GitHubRelease?

    // MARK: - Update Available

    init(release: GitHubRelease, currentVersion: String) {
        self.release = release

        let W: CGFloat = 420
        let H: CGFloat = 300

        let win = UpdateAlertWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.isMovableByWindowBackground = true
        win.hasShadow = true
        win.level = .floating
        self.window = win

        super.init()
        buildUpdateAvailableUI(width: W, height: H, release: release, currentVersion: currentVersion)
        centerOnScreen(win, width: W, height: H)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Up To Date

    init(currentVersion: String) {
        let W: CGFloat = 420
        let H: CGFloat = 180

        let win = UpdateAlertWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.isMovableByWindowBackground = true
        win.hasShadow = true
        win.level = .floating
        self.window = win

        super.init()
        buildUpToDateUI(width: W, height: H, currentVersion: currentVersion)
        centerOnScreen(win, width: W, height: H)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Update Available Layout

    private func buildUpdateAvailableUI(width W: CGFloat, height H: CGFloat,
                                         release: GitHubRelease, currentVersion: String) {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 16
        cv.layer?.masksToBounds = true

        let pad: CGFloat = 32
        let contentW = W - pad * 2
        var y = H - 48

        // Heading
        let heading = frameLabel("Update Available", size: 20, weight: .bold, color: Drac.green)
        heading.frame = NSRect(x: pad, y: y, width: contentW, height: 26)
        cv.addSubview(heading)
        y -= 32

        // Version line
        let versionLine = frameLabel("v\(currentVersion) → v\(release.version)",
                                      size: 15, weight: .medium, color: Drac.foreground)
        versionLine.frame = NSRect(x: pad, y: y, width: contentW, height: 20)
        cv.addSubview(versionLine)
        y -= 28

        // Release notes excerpt
        let excerpt = String(release.body.prefix(200))
        let notes = frameLabel(excerpt.isEmpty ? "A new version is available." : excerpt,
                               size: 12, color: Drac.comment)
        notes.lineBreakMode = .byWordWrapping
        notes.maximumNumberOfLines = 4
        notes.frame = NSRect(x: pad, y: y - 50, width: contentW, height: 60)
        cv.addSubview(notes)
        y -= 100

        // Download button
        let downloadBtn = HoverButton("Download Update", bg: Drac.purple, hover: Drac.pink,
                                       target: self, action: #selector(downloadTapped))
        downloadBtn.translatesAutoresizingMaskIntoConstraints = true
        downloadBtn.frame = NSRect(x: (W - 200) / 2, y: y, width: 200, height: 44)
        cv.addSubview(downloadBtn)
        y -= 30

        // Remind me later
        let remindBtn = HoverLink("Remind Me Later", color: Drac.comment, hover: Drac.foreground,
                                   size: 13, target: self, action: #selector(remindLaterTapped))
        remindBtn.translatesAutoresizingMaskIntoConstraints = true
        remindBtn.sizeToFit()
        remindBtn.frame = NSRect(x: (W - remindBtn.frame.width) / 2, y: y, width: remindBtn.frame.width, height: 20)
        cv.addSubview(remindBtn)
        y -= 22

        // Skip this version
        let skipBtn = HoverLink("Skip This Version", color: Drac.comment, hover: Drac.foreground,
                                 size: 11, target: self, action: #selector(skipVersionTapped))
        skipBtn.translatesAutoresizingMaskIntoConstraints = true
        skipBtn.sizeToFit()
        skipBtn.frame = NSRect(x: (W - skipBtn.frame.width) / 2, y: y, width: skipBtn.frame.width, height: 18)
        cv.addSubview(skipBtn)
    }

    // MARK: - Up To Date Layout

    private func buildUpToDateUI(width W: CGFloat, height H: CGFloat, currentVersion: String) {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 16
        cv.layer?.masksToBounds = true

        let pad: CGFloat = 32
        let contentW = W - pad * 2

        // Heading
        let heading = frameLabel("You're up to date!", size: 20, weight: .bold, color: Drac.green)
        heading.frame = NSRect(x: pad, y: H - 60, width: contentW, height: 26)
        cv.addSubview(heading)

        // Subtitle
        let subtitle = frameLabel("Count Tongula's Eye Break v\(currentVersion) is the latest version.",
                                   size: 14, color: Drac.foreground)
        subtitle.frame = NSRect(x: pad, y: H - 92, width: contentW, height: 20)
        cv.addSubview(subtitle)

        // OK button
        let okBtn = HoverButton("OK", bg: Drac.purple, hover: Drac.pink,
                                 target: self, action: #selector(dismissTapped))
        okBtn.translatesAutoresizingMaskIntoConstraints = true
        okBtn.frame = NSRect(x: (W - 120) / 2, y: 28, width: 120, height: 40)
        cv.addSubview(okBtn)
    }

    // MARK: - Helpers

    private func centerOnScreen(_ win: NSWindow, width: CGFloat, height: CGFloat) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let screen = targetScreen {
            let sf = screen.visibleFrame
            let x = sf.minX + (sf.width - width) / 2
            let y = sf.minY + (sf.height - height) / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            win.center()
        }
    }

    private func frameLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                            color: NSColor = Drac.foreground) -> NSTextField {
        let lbl = makeLabel(text, size: size, weight: weight, color: color)
        lbl.translatesAutoresizingMaskIntoConstraints = true
        lbl.alignment = .left
        return lbl
    }

    // MARK: - Actions

    @objc private func downloadTapped() {
        if let url = release?.htmlURL {
            NSWorkspace.shared.open(url)
        }
        window.orderOut(nil)
    }

    @objc private func remindLaterTapped() {
        window.orderOut(nil)
    }

    @objc private func skipVersionTapped() {
        if let version = release?.version {
            Preferences.shared.skippedVersion = version
        }
        window.orderOut(nil)
    }

    @objc private func dismissTapped() {
        window.orderOut(nil)
    }
}
