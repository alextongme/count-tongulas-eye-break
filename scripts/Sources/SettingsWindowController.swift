import Cocoa

// Borderless window that can become key
private class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Content view that accepts first mouse click
private class FirstClickView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class SettingsWindowController: NSObject {
    let window: NSWindow

    var intervalSlider: NSSlider!
    var intervalValueLabel: NSTextField!
    var durationSlider: NSSlider!
    var durationValueLabel: NSTextField!
    var snoozeSlider: NSSlider!
    var snoozeValueLabel: NSTextField!
    var soundToggle: NSSwitch!
    var promptSoundPicker: NSPopUpButton!
    var completeSoundPicker: NSPopUpButton!
    var dndToggle: NSSwitch!
    var idleToggle: NSSwitch!
    var fullscreenToggle: NSSwitch!
    var cloudsToggle: NSSwitch!
    var launchToggle: NSSwitch!
    var longBreakToggle: NSSwitch!
    var longBreakEverySlider: NSSlider!
    var longBreakEveryLabel: NSTextField!
    var longBreakDurationSlider: NSSlider!
    var longBreakDurationLabel: NSTextField!
    var strictToggle: NSSwitch!
    var appExclusionToggle: NSSwitch!
    var preBreakNotifyToggle: NSSwitch!

    private let W: CGFloat = 740
    private let H: CGFloat = 740
    private let colW: CGFloat = 300
    private let leftX: CGFloat = 44
    private let rightX: CGFloat = 396  // 44 + 300 + 52 gap
    private let rowStep: CGFloat = 44  // Uniform spacing for all row types

    override init() {
        let win = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 740),
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
        win.contentView = FirstClickView(frame: NSRect(x: 0, y: 0, width: 740, height: 740))
        self.window = win

        super.init()
        buildUI()
        loadPreferences()

        // Center on active screen
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

    // MARK: - Frame-based two-column layout

    func buildUI() {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 16
        cv.layer?.masksToBounds = true

        // ── Title ──
        let title = field("Settings", size: 22, weight: .bold, color: Drac.purple)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: H - 56, width: W, height: 30)
        cv.addSubview(title)

        // ── Close button (top-right) ──
        let closeBtn = HoverLink(
            "Done",
            color: Drac.green,
            hover: Drac.foreground,
            size: 13,
            target: self,
            action: #selector(closeTapped)
        )
        closeBtn.translatesAutoresizingMaskIntoConstraints = true
        closeBtn.sizeToFit()
        closeBtn.frame = NSRect(x: W - closeBtn.frame.width - 36, y: H - 52, width: closeBtn.frame.width, height: 20)
        cv.addSubview(closeBtn)

        // ── Left Column: Timing + Long Breaks ──
        var y = H - 100

        y = addHeading("Timing", x: leftX, y: y, to: cv)

        (intervalSlider, intervalValueLabel) = addSliderRow(
            "Break interval", min: 5, max: 60, x: leftX, y: y, to: cv,
            target: self, action: #selector(intervalChanged))
        y -= rowStep

        (durationSlider, durationValueLabel) = addSliderRow(
            "Break duration", min: 5, max: 60, x: leftX, y: y, to: cv,
            target: self, action: #selector(durationChanged))
        y -= rowStep

        (snoozeSlider, snoozeValueLabel) = addSliderRow(
            "Snooze duration", min: 1, max: 10, x: leftX, y: y, to: cv,
            target: self, action: #selector(snoozeChanged))
        y -= rowStep + 20  // Extra gap before next section

        y = addHeading("Long Breaks", x: leftX, y: y, to: cv)

        longBreakToggle = addToggleRow(
            "Enable long breaks", x: leftX, y: y, to: cv,
            target: self, action: #selector(longBreakToggleChanged))
        y -= rowStep

        (longBreakEverySlider, longBreakEveryLabel) = addSliderRow(
            "Long break every", min: 2, max: 10, x: leftX, y: y, to: cv,
            target: self, action: #selector(longBreakEveryChanged))
        y -= rowStep

        (longBreakDurationSlider, longBreakDurationLabel) = addSliderRow(
            "Long break duration", min: 1, max: 10, x: leftX, y: y, to: cv,
            target: self, action: #selector(longBreakDurationChanged))

        // ── Right Column: Sounds + Behavior ──
        y = H - 100

        y = addHeading("Sounds", x: rightX, y: y, to: cv)

        soundToggle = addToggleRow(
            "Enable sounds", x: rightX, y: y, to: cv,
            target: self, action: #selector(soundToggleChanged))
        y -= rowStep

        promptSoundPicker = addPickerRow(
            "Prompt sound", items: SoundManager.availableSounds, x: rightX, y: y, to: cv,
            target: self, action: #selector(promptSoundChanged))
        y -= rowStep

        completeSoundPicker = addPickerRow(
            "Complete sound", items: SoundManager.availableSounds, x: rightX, y: y, to: cv,
            target: self, action: #selector(completeSoundChanged))
        y -= rowStep + 20  // Extra gap before next section

        y = addHeading("Behavior", x: rightX, y: y, to: cv)

        dndToggle = addToggleRow(
            "Pause during DND", x: rightX, y: y, to: cv,
            target: self, action: #selector(dndToggleChanged))
        y -= rowStep

        idleToggle = addToggleRow(
            "Detect inactivity", x: rightX, y: y, to: cv,
            target: self, action: #selector(idleToggleChanged))
        y -= rowStep

        fullscreenToggle = addToggleRow(
            "Dim screens on break", x: rightX, y: y, to: cv,
            target: self, action: #selector(fullscreenToggleChanged))
        y -= rowStep

        cloudsToggle = addToggleRow(
            "Cloud effect on break", x: rightX, y: y, to: cv,
            target: self, action: #selector(cloudsToggleChanged))
        y -= rowStep

        launchToggle = addToggleRow(
            "Launch at login", x: rightX, y: y, to: cv,
            target: self, action: #selector(launchToggleChanged))
        y -= rowStep

        strictToggle = addToggleRow(
            "Strict mode (no skip/snooze)", x: rightX, y: y, to: cv,
            target: self, action: #selector(strictToggleChanged))
        y -= rowStep

        appExclusionToggle = addToggleRow(
            "Pause for meetings/presentations", x: rightX, y: y, to: cv,
            target: self, action: #selector(appExclusionToggleChanged))
        y -= rowStep

        preBreakNotifyToggle = addToggleRow(
            "Notify before break", x: rightX, y: y, to: cv,
            target: self, action: #selector(preBreakNotifyToggleChanged))

        // ── Restore Defaults button (bottom center) ──
        let restoreBtn = HoverLink(
            "Restore Defaults",
            color: Drac.orange,
            hover: Drac.red,
            size: 13,
            target: self,
            action: #selector(restoreDefaults)
        )
        restoreBtn.translatesAutoresizingMaskIntoConstraints = true
        restoreBtn.sizeToFit()
        restoreBtn.frame = NSRect(x: (W - restoreBtn.frame.width) / 2, y: 30, width: restoreBtn.frame.width, height: 20)
        cv.addSubview(restoreBtn)
    }

    // MARK: - Row builders

    @discardableResult
    private func addHeading(_ text: String, x: CGFloat, y: CGFloat, to parent: NSView) -> CGFloat {
        let lbl = field(text, size: 15, weight: .bold, color: Drac.cyan)
        lbl.frame = NSRect(x: x, y: y, width: colW, height: 20)
        parent.addSubview(lbl)
        return y - 38
    }

    private func addSliderRow(
        _ text: String, min: Double, max: Double,
        x: CGFloat, y: CGFloat, to parent: NSView,
        target: AnyObject?, action: Selector?
    ) -> (NSSlider, NSTextField) {
        let labelW: CGFloat = 120
        let valueW: CGFloat = 80
        let sliderW = colW - labelW - valueW - 12

        let lbl = field(text, size: 13, color: Drac.foreground)
        lbl.frame = NSRect(x: x, y: y, width: labelW, height: 20)
        parent.addSubview(lbl)

        let slider = NSSlider(frame: NSRect(x: x + labelW + 4, y: y, width: sliderW, height: 20))
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        parent.addSubview(slider)

        let valLbl = field("", size: 13, color: Drac.comment)
        valLbl.alignment = .right
        valLbl.frame = NSRect(x: x + colW - valueW, y: y, width: valueW, height: 20)
        parent.addSubview(valLbl)

        return (slider, valLbl)
    }

    private func addToggleRow(
        _ text: String, x: CGFloat, y: CGFloat, to parent: NSView,
        target: AnyObject?, action: Selector?
    ) -> NSSwitch {
        let lbl = field(text, size: 13, color: Drac.foreground)
        lbl.frame = NSRect(x: x, y: y, width: colW - 54, height: 20)
        parent.addSubview(lbl)

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.target = target
        toggle.action = action
        toggle.frame = NSRect(x: x + colW - 44, y: y, width: 44, height: 20)
        parent.addSubview(toggle)

        return toggle
    }

    private func addPickerRow(
        _ text: String, items: [String], x: CGFloat, y: CGFloat, to parent: NSView,
        target: AnyObject?, action: Selector?
    ) -> NSPopUpButton {
        let lbl = field(text, size: 13, color: Drac.foreground)
        lbl.frame = NSRect(x: x, y: y, width: 120, height: 20)
        parent.addSubview(lbl)

        let picker = NSPopUpButton(frame: NSRect(x: x + 124, y: y - 2, width: colW - 124, height: 24))
        picker.addItems(withTitles: items)
        picker.target = target
        picker.action = action
        parent.addSubview(picker)

        return picker
    }

    // MARK: - Field factory

    private func field(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Drac.foreground) -> NSTextField {
        let f = NSTextField(frame: .zero)
        f.stringValue = text
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.backgroundColor = .clear
        f.isBezeled = false
        f.isEditable = false
        f.isSelectable = false
        return f
    }

    // MARK: - Load preferences

    func loadPreferences() {
        let prefs = Preferences.shared

        let intervalMin = prefs.breakInterval / 60
        intervalSlider.intValue = Int32(intervalMin)
        intervalValueLabel.stringValue = "\(intervalMin) min"

        durationSlider.intValue = Int32(prefs.breakDuration)
        durationValueLabel.stringValue = "\(prefs.breakDuration) sec"

        let snoozeMin = prefs.snoozeDuration / 60
        snoozeSlider.intValue = Int32(snoozeMin)
        snoozeValueLabel.stringValue = "\(snoozeMin) min"

        soundToggle.state = prefs.soundEnabled ? .on : .off
        promptSoundPicker.selectItem(withTitle: prefs.promptSound)
        completeSoundPicker.selectItem(withTitle: prefs.completeSound)

        dndToggle.state = prefs.dndAware ? .on : .off
        idleToggle.state = prefs.idleDetectionEnabled ? .on : .off
        fullscreenToggle.state = prefs.fullscreenOverlay ? .on : .off
        cloudsToggle.state = prefs.cloudsEnabled ? .on : .off
        launchToggle.state = prefs.launchAtLogin ? .on : .off

        longBreakToggle.state = prefs.longBreakEnabled ? .on : .off
        strictToggle.state = prefs.strictMode ? .on : .off
        appExclusionToggle.state = prefs.appExclusionEnabled ? .on : .off
        preBreakNotifyToggle.state = prefs.preBreakNotifyEnabled ? .on : .off
        longBreakEverySlider.intValue = Int32(prefs.longBreakEveryN)
        longBreakEveryLabel.stringValue = "\(prefs.longBreakEveryN) eye breaks"

        let longBreakMin = prefs.longBreakDuration / 60
        longBreakDurationSlider.intValue = Int32(longBreakMin)
        longBreakDurationLabel.stringValue = "\(longBreakMin) min"
    }

    // MARK: - Actions

    @objc func closeTapped() {
        window.orderOut(nil)
    }

    @objc func intervalChanged() {
        let val = Int(intervalSlider.intValue)
        intervalValueLabel.stringValue = "\(val) min"
        Preferences.shared.breakInterval = val * 60
    }

    @objc func durationChanged() {
        let val = Int(durationSlider.intValue)
        durationValueLabel.stringValue = "\(val) sec"
        Preferences.shared.breakDuration = val
    }

    @objc func snoozeChanged() {
        let val = Int(snoozeSlider.intValue)
        snoozeValueLabel.stringValue = "\(val) min"
        Preferences.shared.snoozeDuration = val * 60
    }

    @objc func soundToggleChanged() {
        Preferences.shared.soundEnabled = soundToggle.state == .on
    }

    @objc func promptSoundChanged() {
        guard let title = promptSoundPicker.selectedItem?.title else { return }
        Preferences.shared.promptSound = title
        SoundManager.shared.previewSound(title)
    }

    @objc func completeSoundChanged() {
        guard let title = completeSoundPicker.selectedItem?.title else { return }
        Preferences.shared.completeSound = title
        SoundManager.shared.previewSound(title)
    }

    @objc func dndToggleChanged() {
        Preferences.shared.dndAware = dndToggle.state == .on
    }

    @objc func idleToggleChanged() {
        Preferences.shared.idleDetectionEnabled = idleToggle.state == .on
    }

    @objc func fullscreenToggleChanged() {
        Preferences.shared.fullscreenOverlay = fullscreenToggle.state == .on
    }

    @objc func cloudsToggleChanged() {
        Preferences.shared.cloudsEnabled = cloudsToggle.state == .on
    }

    @objc func launchToggleChanged() {
        Preferences.shared.launchAtLogin = launchToggle.state == .on
    }

    @objc func longBreakToggleChanged() {
        Preferences.shared.longBreakEnabled = longBreakToggle.state == .on
    }

    @objc func longBreakEveryChanged() {
        let val = Int(longBreakEverySlider.intValue)
        longBreakEveryLabel.stringValue = "\(val) eye breaks"
        Preferences.shared.longBreakEveryN = val
    }

    @objc func longBreakDurationChanged() {
        let val = Int(longBreakDurationSlider.intValue)
        longBreakDurationLabel.stringValue = "\(val) min"
        Preferences.shared.longBreakDuration = val * 60
    }

    @objc func strictToggleChanged() {
        Preferences.shared.strictMode = strictToggle.state == .on
    }

    @objc func appExclusionToggleChanged() {
        Preferences.shared.appExclusionEnabled = appExclusionToggle.state == .on
    }

    @objc func preBreakNotifyToggleChanged() {
        Preferences.shared.preBreakNotifyEnabled = preBreakNotifyToggle.state == .on
    }

    @objc func restoreDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.counttongula.eyebreak"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        // Re-register defaults and reload
        _ = Preferences.shared
        loadPreferences()
    }
}
