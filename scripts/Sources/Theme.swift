import Cocoa
import CoreText

// ─── Custom Fonts (DM Sans + DM Mono from draculatheme.com) ────────

/// Register bundled TTF fonts so they're available by name without system install.
func registerCustomFonts() {
    let fontFiles = [
        "fonts/DMSans-Regular.ttf",
        "fonts/DMSans-Medium.ttf",
        "fonts/DMSans-Bold.ttf",
        "fonts/DMMono-Regular.ttf",
        "fonts/DMMono-Medium.ttf",
    ]
    for file in fontFiles {
        let path = assetPath(file)
        let url = URL(fileURLWithPath: path) as CFURL
        CTFontManagerRegisterFontsForURL(url, .process, nil)
    }
}

/// DM Sans font matching the Dracula website typography.
func dmSans(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let name: String
    switch weight {
    case .bold, .heavy, .black:
        name = "DMSans-Bold"
    case .medium, .semibold:
        name = "DMSans-Medium"
    default:
        name = "DMSans-Regular"
    }
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

/// DM Mono font for monospace/code contexts.
func dmMono(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let name = (weight == .medium || weight == .semibold || weight == .bold)
        ? "DMMono-Medium" : "DMMono-Regular"
    return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

// ─── Dracula Palette ────────────────────────────────────────────────
struct Drac {
    static let background  = NSColor(srgbRed: 0x28/255.0, green: 0x2A/255.0, blue: 0x36/255.0, alpha: 1)
    static let currentLine = NSColor(srgbRed: 0x44/255.0, green: 0x47/255.0, blue: 0x5A/255.0, alpha: 1)
    static let foreground  = NSColor(srgbRed: 0xF8/255.0, green: 0xF8/255.0, blue: 0xF2/255.0, alpha: 1)
    static let comment     = NSColor(srgbRed: 0x62/255.0, green: 0x72/255.0, blue: 0xA4/255.0, alpha: 1)
    static let purple      = NSColor(srgbRed: 0xBD/255.0, green: 0x93/255.0, blue: 0xF9/255.0, alpha: 1)
    static let pink        = NSColor(srgbRed: 0xFF/255.0, green: 0x79/255.0, blue: 0xC6/255.0, alpha: 1)
    static let green       = NSColor(srgbRed: 0x50/255.0, green: 0xFA/255.0, blue: 0x7B/255.0, alpha: 1)
    static let cyan        = NSColor(srgbRed: 0x8B/255.0, green: 0xE9/255.0, blue: 0xFD/255.0, alpha: 1)
    static let orange      = NSColor(srgbRed: 0xFF/255.0, green: 0xB8/255.0, blue: 0x6C/255.0, alpha: 1)
    static let red         = NSColor(srgbRed: 0xFF/255.0, green: 0x55/255.0, blue: 0x55/255.0, alpha: 1)
    static let yellow      = NSColor(srgbRed: 0xF1/255.0, green: 0xFA/255.0, blue: 0x8C/255.0, alpha: 1)
}

// ─── Asset Resolution ────────────────────────────────────────────────
func assetPath(_ name: String) -> String {
    // Check install directory (binary launched via .app resolves through symlinks,
    // so argv[0] won't match ~/.eye-break/; check the known install path directly)
    let installDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".eye-break/assets/\(name)").path
    if FileManager.default.fileExists(atPath: installDir) {
        return installDir
    }

    let binaryURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let binaryDir = binaryURL.deletingLastPathComponent()

    // Check alongside the binary (symlink install)
    let primary = binaryDir.appendingPathComponent("assets/\(name)").path
    if FileManager.default.fileExists(atPath: primary) {
        return primary
    }

    // Check one level up (repo layout)
    let repoFallback = binaryDir.appendingPathComponent("../assets/\(name)").path
    if FileManager.default.fileExists(atPath: repoFallback) {
        return repoFallback
    }

    // Check inside .app bundle Resources (Homebrew Cask / .app distribution)
    let bundleResources = binaryDir
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/assets/\(name)").path
    if FileManager.default.fileExists(atPath: bundleResources) {
        return bundleResources
    }

    // Check current working directory (development with SPM)
    let cwdFallback = FileManager.default.currentDirectoryPath + "/assets/\(name)"
    return cwdFallback
}

// ─── Label Factory ───────────────────────────────────────────────────
func makeLabel(
    _ text: String,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = Drac.foreground
) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = dmSans(size: size, weight: weight)
    label.textColor = color
    label.alignment = .center
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

// ─── Progress Bar ────────────────────────────────────────────────────
class ProgressBarView: NSView {
    var progress: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }

    private let cornerRadius: CGFloat = 4

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background track
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        Drac.currentLine.setFill()
        trackPath.fill()

        // Foreground fill proportional to progress
        guard progress > 0 else { return }
        let fillWidth = bounds.width * min(max(progress, 0), 1)
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height)

        // Clip to rounded track so fill doesn't bleed outside corners
        trackPath.addClip()
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        Drac.purple.setFill()
        fillPath.fill()
    }
}

// ─── Pointer Button (plain button with pointing-hand cursor) ────────
class PointerButton: NSButton {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// ─── Hover Button ────────────────────────────────────────────────────
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
        translatesAutoresizingMaskIntoConstraints = false
        setLabel(title)
    }

    func setLabel(_ text: String) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: fg,
            .font: dmSans(size: 15, weight: .semibold)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = hoverBg.cgColor
        }
    }
    override func mouseExited(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = normalBg.cgColor
        }
    }
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
        translatesAutoresizingMaskIntoConstraints = false
        applyStyle(normalColor)
    }

    private func applyStyle(_ color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: dmSans(size: fontSize, weight: .medium),
        ]
        attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.applyStyle(self.hoverColor)
        }
    }
    override func mouseExited(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.applyStyle(self.normalColor)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ─── Screenshot Capture ──────────────────────────────────────────────
func captureWindow(_ window: NSWindow, to path: String) {
    guard let contentView = window.contentView else { return }

    let bounds = contentView.bounds
    guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
    contentView.cacheDisplay(in: bounds, to: bitmap)

    // Composite into an image with rounded corners applied via clipping mask
    let size = bounds.size
    guard let image = NSImage(size: size, flipped: false, drawingHandler: { rect in
        let clipPath = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        clipPath.addClip()
        bitmap.draw(in: rect)
        return true
    }) as NSImage? else { return }

    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

    try? pngData.write(to: URL(fileURLWithPath: path))
}
