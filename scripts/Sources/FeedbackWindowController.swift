import Cocoa
import CoreServices

enum FeedbackMode {
    case bug
    case feature
}

// Borderless window that can become key
private class FeedbackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class FeedbackWindowController: NSObject {
    let window: NSWindow
    let mode: FeedbackMode

    private var descriptionField: NSTextView!
    private var stepsField: NSTextView!
    private var stepsLabel: NSTextField!
    private var stepsScroll: NSScrollView!
    private var screenshotLabel: NSTextField!
    private var screenshotURL: URL?
    private var screenshotWarning: NSTextField!

    private let supportEmail = "alextongme@gmail.com"

    init(mode: FeedbackMode) {
        self.mode = mode

        let W: CGFloat = 500
        let H: CGFloat = mode == .bug ? 600 : 440
        let win = FeedbackWindow(
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
        buildUI(width: W, height: H)

        // Center on screen
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let screen = targetScreen {
            let sf = screen.visibleFrame
            let x = sf.minX + (sf.width - W) / 2
            let y = sf.minY + (sf.height - H) / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            win.center()
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI(width W: CGFloat, height H: CGFloat) {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true

        let pad: CGFloat = 32
        let contentW = W - pad * 2

        // Frame-based label helper (makeLabel sets translatesAutoresizingMaskIntoConstraints=false)
        func frameLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Drac.foreground) -> NSTextField {
            let lbl = makeLabel(text, size: size, weight: weight, color: color)
            lbl.translatesAutoresizingMaskIntoConstraints = true
            return lbl
        }

        // Title
        let title = frameLabel(
            mode == .bug ? "Report a Bug" : "Request a Feature",
            size: 16, weight: .bold, color: mode == .bug ? Drac.red : Drac.cyan
        )
        title.frame = NSRect(x: pad, y: H - 50, width: contentW, height: 26)
        cv.addSubview(title)

        // Close button
        let closeBtn = HoverLink("Cancel", color: Drac.comment, hover: Drac.foreground,
                                  size: 13, target: self, action: #selector(closeTapped))
        closeBtn.translatesAutoresizingMaskIntoConstraints = true
        closeBtn.sizeToFit()
        closeBtn.frame = NSRect(x: W - closeBtn.frame.width - pad, y: H - 48, width: closeBtn.frame.width, height: 20)
        cv.addSubview(closeBtn)

        var y = H - 80

        // Description label
        let descLabel = frameLabel(
            mode == .bug ? "Describe the problem:" : "Describe the feature you'd like:",
            size: 13, weight: .medium, color: Drac.foreground
        )
        descLabel.frame = NSRect(x: pad, y: y, width: contentW, height: 18)
        cv.addSubview(descLabel)
        y -= 100

        // Description text area
        let descScroll = makeTextArea(frame: NSRect(x: pad, y: y, width: contentW, height: 90))
        descriptionField = descScroll.documentView as? NSTextView
        cv.addSubview(descScroll)
        y -= 28

        if mode == .bug {
            // Steps to reproduce
            stepsLabel = frameLabel("Steps to reproduce:", size: 13, weight: .medium, color: Drac.foreground)
            stepsLabel.frame = NSRect(x: pad, y: y, width: contentW, height: 18)
            cv.addSubview(stepsLabel)
            y -= 100

            stepsScroll = makeTextArea(frame: NSRect(x: pad, y: y, width: contentW, height: 90))
            stepsField = stepsScroll.documentView as? NSTextView
            stepsField.string = "1. \n2. \n3. "
            cv.addSubview(stepsScroll)
            y -= 28
        }

        // Screenshot section (with vertical spacing)
        y -= 8
        let screenshotBtn = HoverButton("Attach Screenshot", bg: Drac.currentLine, hover: Drac.comment,
                                         target: self, action: #selector(attachScreenshot))
        screenshotBtn.translatesAutoresizingMaskIntoConstraints = true
        screenshotBtn.frame = NSRect(x: pad, y: y, width: 180, height: 32)
        cv.addSubview(screenshotBtn)

        screenshotLabel = frameLabel("No file selected", size: 12, color: Drac.comment)
        screenshotLabel.frame = NSRect(x: pad + 190, y: y + 6, width: contentW - 190, height: 20)
        screenshotLabel.alignment = .left
        cv.addSubview(screenshotLabel)
        y -= 28

        screenshotWarning = frameLabel("", size: 11, color: Drac.red)
        screenshotWarning.frame = NSRect(x: pad, y: y, width: contentW, height: 18)
        screenshotWarning.alignment = .left
        cv.addSubview(screenshotWarning)
        y -= 32

        // System info (auto-populated, read-only) — each field on its own line
        let sysInfoLabel = frameLabel("System info (auto-included):", size: 13, weight: .medium)
        sysInfoLabel.frame = NSRect(x: pad, y: y, width: contentW, height: 18)
        cv.addSubview(sysInfoLabel)
        y -= 22

        let (appLine, osLine, macLine) = systemInfoLines()
        let infoSize: CGFloat = 12.5
        let lineH: CGFloat = 18

        let appInfo = frameLabel(appLine, size: infoSize, color: Drac.comment)
        appInfo.frame = NSRect(x: pad, y: y, width: contentW, height: lineH)
        cv.addSubview(appInfo)
        y -= lineH + 2

        let osInfo = frameLabel(osLine, size: infoSize, color: Drac.comment)
        osInfo.frame = NSRect(x: pad, y: y, width: contentW, height: lineH)
        cv.addSubview(osInfo)
        y -= lineH + 2

        let macInfo = frameLabel(macLine, size: infoSize, color: Drac.comment)
        macInfo.frame = NSRect(x: pad, y: y, width: contentW, height: lineH)
        cv.addSubview(macInfo)
        y -= 16

        // Send button
        let sendBtn = HoverButton("Send Report", bg: Drac.currentLine, hover: Drac.selection, fg: Drac.purple,
                                   target: self, action: #selector(sendReport))
        sendBtn.translatesAutoresizingMaskIntoConstraints = true
        sendBtn.frame = NSRect(x: (W - 200) / 2, y: 28, width: 200, height: 36)
        cv.addSubview(sendBtn)
    }

    // MARK: - Text Area Factory

    private func makeTextArea(frame: NSRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = dmSans(size: 13)
        textView.textColor = Drac.foreground
        textView.backgroundColor = Drac.currentLine
        textView.insertionPointColor = Drac.foreground
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.masksToBounds = true

        return scrollView
    }

    // MARK: - System Info

    private func systemInfoLines() -> (String, String, String) {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let model = macModel()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return ("App: v\(appVersion)", "macOS: \(osVersion)", "Mac: \(model)")
    }

    private func systemInfoString() -> String {
        let (app, os, mac) = systemInfoLines()
        return "\(app)\n\(os)\n\(mac)"
    }

    private func macModel() -> String {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    // MARK: - Screenshot Validation

    @objc private func attachScreenshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a macOS screenshot (PNG only)"
        panel.level = .floating

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Validate it's a real macOS screenshot using Spotlight metadata
        if isValidScreenshot(url) {
            screenshotURL = url
            screenshotLabel.stringValue = url.lastPathComponent
            screenshotLabel.textColor = Drac.green
            screenshotWarning.stringValue = ""
        } else {
            screenshotURL = nil
            screenshotLabel.stringValue = "No file selected"
            screenshotLabel.textColor = Drac.comment
            screenshotWarning.stringValue = "Only macOS screenshots are accepted (use Cmd+Shift+3 or 4)"
        }
    }

    private func isValidScreenshot(_ url: URL) -> Bool {
        // Must be a PNG file
        guard url.pathExtension.lowercased() == "png" else { return false }

        // Check file size (screenshots are typically < 20MB, reject suspiciously large files)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size < 20_000_000 else { return false }

        // Use Spotlight metadata to verify it's a macOS screenshot
        // macOS sets kMDItemIsScreenCapture = 1 on screenshots taken with the system tool
        guard let mdItem = MDItemCreateWithURL(nil, url as CFURL) else { return false }
        if let isScreenCapture = MDItemCopyAttribute(mdItem, "kMDItemIsScreenCapture" as CFString) as? Bool {
            return isScreenCapture
        }
        // Also check kMDItemScreenCaptureType which is set on all macOS screenshots
        if let _ = MDItemCopyAttribute(mdItem, "kMDItemScreenCaptureType" as CFString) {
            return true
        }

        // Fallback: check if filename matches macOS screenshot naming pattern
        // e.g. "Screenshot 2024-01-15 at 10.30.45.png" or "Screen Shot ..."
        let name = url.lastPathComponent
        if name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ") ||
           name.hasPrefix("CleanShot ") {
            return true
        }

        return false
    }

    // MARK: - Send

    @objc private func sendReport() {
        let description = descriptionField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            screenshotWarning.stringValue = "Please describe the \(mode == .bug ? "problem" : "feature")."
            return
        }

        let subject: String
        var body: String

        if mode == .bug {
            subject = "Count Tongula's Eye Break — Bug Report"
            let steps = stepsField?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            body = """
            Problem:
            \(description)

            Steps to reproduce:
            \(steps.isEmpty ? "(not provided)" : steps)

            """
        } else {
            subject = "Count Tongula's Eye Break — Feature Request"
            body = """
            Feature request:
            \(description)

            """
        }

        body += """

        -----
        \(systemInfoString())
        """

        // Try NSSharingService for email with attachment support
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = [supportEmail]
            service.subject = subject

            var items: [Any] = [body]
            if let url = screenshotURL {
                items.append(url)
            }

            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                window.orderOut(nil)
                return
            }
        }

        // Fallback to mailto: (no attachment support)
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        let urlString = "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        window.orderOut(nil)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        window.orderOut(nil)
    }
}
