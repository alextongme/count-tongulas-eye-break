import Cocoa

// Borderless key-capable window (same pattern as SettingsWindow)
private class RemindersWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private class RemindersFirstClickView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private class HoverCardView: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = NSColor(srgbRed: 0x2D/255.0, green: 0x2F/255.0, blue: 0x3D/255.0, alpha: 1).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = Drac.currentLine.cgColor
        }
    }
}

class RemindersWindowController: NSObject {
    let window: NSWindow

    private let W: CGFloat = 520
    private let H: CGFloat = 560
    private var listContainer: NSView!
    private var emptyLabel: NSTextField!

    override init() {
        let win = RemindersWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
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
        win.contentView = RemindersFirstClickView(frame: NSRect(x: 0, y: 0, width: 520, height: 560))
        self.window = win

        super.init()

        buildUI()

        // Center on cursor screen
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remindersDidChange),
            name: ReminderStore.didChangeNotification,
            object: nil
        )
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true

        // Title
        let title = field("Reminders", size: 18, weight: .bold, color: Drac.purple)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: H - 56, width: W, height: 30)
        cv.addSubview(title)

        // Close button
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

        // Add button
        let addBtn = HoverButton(
            "+ Add Reminder",
            bg: Drac.currentLine,
            hover: Drac.selection,
            fg: Drac.purple,
            target: self,
            action: #selector(addTapped)
        )
        addBtn.translatesAutoresizingMaskIntoConstraints = true
        addBtn.frame = NSRect(x: (W - 180) / 2, y: 24, width: 180, height: 38)
        cv.addSubview(addBtn)

        // Scrollable list area
        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 76, width: W - 48, height: H - 148))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let clipView = NSClipView(frame: scrollView.bounds)
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let docView = NSView(frame: NSRect(x: 0, y: 0, width: W - 48, height: 0))
        docView.wantsLayer = true
        scrollView.documentView = docView
        listContainer = docView

        cv.addSubview(scrollView)

        // Empty state
        emptyLabel = field("No reminders yet.\nClick + to add one.", size: 15, weight: .regular, color: Drac.comment)
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.frame = NSRect(x: 24, y: (H - 148) / 2 + 40, width: W - 48, height: 50)
        cv.addSubview(emptyLabel)

        rebuildList()
    }

    private func rebuildList() {
        // Clear existing
        for sub in listContainer.subviews { sub.removeFromSuperview() }

        let reminders = ReminderStore.shared.reminders
        emptyLabel.isHidden = !reminders.isEmpty

        let rowH: CGFloat = 72
        let gap: CGFloat = 8
        let totalH = CGFloat(reminders.count) * (rowH + gap)
        let containerW = listContainer.frame.width

        listContainer.frame = NSRect(x: 0, y: 0, width: containerW, height: max(totalH, 1))

        for (i, reminder) in reminders.enumerated() {
            let y = totalH - CGFloat(i + 1) * (rowH + gap)
            let row = makeReminderRow(reminder, index: i, at: NSRect(x: 0, y: y, width: containerW, height: rowH))
            listContainer.addSubview(row)
        }

        (listContainer.enclosingScrollView?.contentView)?.scroll(to: NSPoint(x: 0, y: totalH))
    }

    private func makeReminderRow(_ reminder: Reminder, index: Int, at frame: NSRect) -> NSView {
        let row = HoverCardView(frame: frame)
        row.wantsLayer = true
        row.layer?.backgroundColor = Drac.currentLine.cgColor
        row.layer?.cornerRadius = 10

        // Enable toggle
        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = reminder.enabled ? .on : .off
        toggle.tag = index
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.frame = NSRect(x: 14, y: (frame.height - 20) / 2, width: 44, height: 20)
        row.addSubview(toggle)

        // Time
        let timeLabel = field(reminder.timeString, size: 15, weight: .bold, color: Drac.orange)
        timeLabel.frame = NSRect(x: 66, y: frame.height - 28, width: 100, height: 20)
        row.addSubview(timeLabel)

        // Days
        let daysLabel = field(reminder.daysString, size: 11, weight: .regular, color: Drac.comment)
        daysLabel.frame = NSRect(x: 66, y: frame.height - 46, width: 200, height: 16)
        row.addSubview(daysLabel)

        // Message preview
        let msgPreview = field(reminder.message.isEmpty ? "(no message)" : reminder.message, size: 12, weight: .regular, color: reminder.message.isEmpty ? Drac.comment : Drac.foreground)
        msgPreview.lineBreakMode = .byTruncatingTail
        msgPreview.frame = NSRect(x: 66, y: 8, width: frame.width - 150, height: 16)
        row.addSubview(msgPreview)

        // Edit button
        let editBtn = HoverLink(
            "Edit",
            color: Drac.cyan,
            hover: Drac.foreground,
            size: 12,
            target: self,
            action: #selector(editTapped(_:))
        )
        editBtn.translatesAutoresizingMaskIntoConstraints = true
        editBtn.tag = index
        editBtn.sizeToFit()
        editBtn.frame = NSRect(x: frame.width - 90, y: (frame.height - 16) / 2 + 10, width: 30, height: 16)
        row.addSubview(editBtn)

        // Delete button
        let delBtn = HoverLink(
            "Delete",
            color: Drac.red,
            hover: Drac.orange,
            size: 12,
            target: self,
            action: #selector(deleteTapped(_:))
        )
        delBtn.translatesAutoresizingMaskIntoConstraints = true
        delBtn.tag = index
        delBtn.sizeToFit()
        delBtn.frame = NSRect(x: frame.width - 52, y: (frame.height - 16) / 2 + 10, width: 42, height: 16)
        row.addSubview(delBtn)

        return row
    }

    // MARK: - Actions

    @objc func closeTapped() {
        window.orderOut(nil)
    }

    @objc func addTapped() {
        showEditor(for: nil)
    }

    @objc func editTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < ReminderStore.shared.reminders.count else { return }
        showEditor(for: ReminderStore.shared.reminders[index])
    }

    @objc func deleteTapped(_ sender: NSButton) {
        let index = sender.tag
        ReminderStore.shared.delete(at: index)
        rebuildList()
    }

    @objc func toggleChanged(_ sender: NSSwitch) {
        let index = sender.tag
        guard index >= 0 && index < ReminderStore.shared.reminders.count else { return }
        var r = ReminderStore.shared.reminders[index]
        r.enabled = sender.state == .on
        ReminderStore.shared.update(r)
    }

    @objc func dayBtnToggled(_ sender: NSButton) {
        let isOn = sender.state == .on
        let name = sender.title
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            sender.layer?.backgroundColor = (isOn ? Drac.purple : Drac.currentLine).cgColor
        }
        sender.attributedTitle = NSAttributedString(string: name, attributes: [
            .foregroundColor: isOn ? Drac.foreground : Drac.comment,
            .font: dmSans(size: 11, weight: .medium),
        ])
    }

    @objc func remindersDidChange() {
        rebuildList()
    }

    // MARK: - Editor

    private var editorWindow: NSWindow?

    private func showEditor(for existing: Reminder?) {
        let reminder = existing ?? Reminder()
        let isNew = existing == nil

        let edW: CGFloat = 400
        let edH: CGFloat = 440

        let win = RemindersWindow(
            contentRect: NSRect(x: 0, y: 0, width: edW, height: edH),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

        let cv = RemindersFirstClickView(frame: NSRect(x: 0, y: 0, width: edW, height: edH))
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor
        cv.layer?.cornerRadius = 10
        cv.layer?.masksToBounds = true
        cv.layer?.borderWidth = 1
        cv.layer?.borderColor = Drac.currentLine.cgColor
        win.contentView = cv

        var y = edH - 52

        // Title
        let title = field(isNew ? "New Reminder" : "Edit Reminder", size: 16, weight: .bold, color: Drac.purple)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: y, width: edW, height: 26)
        cv.addSubview(title)
        y -= 44

        // Message label + text field
        let msgLabel = field("Message", size: 13, weight: .medium, color: Drac.cyan)
        msgLabel.frame = NSRect(x: 32, y: y, width: 100, height: 18)
        cv.addSubview(msgLabel)
        y -= 60

        let msgField = NSTextView(frame: NSRect(x: 32, y: y, width: edW - 64, height: 56))
        msgField.font = dmSans(size: 14)
        msgField.textColor = Drac.foreground
        msgField.backgroundColor = Drac.currentLine
        msgField.insertionPointColor = Drac.foreground
        msgField.isEditable = true
        msgField.isRichText = false
        msgField.string = reminder.message
        msgField.textContainerInset = NSSize(width: 8, height: 6)
        msgField.wantsLayer = true
        msgField.layer?.cornerRadius = 8
        msgField.layer?.borderWidth = 1
        msgField.layer?.borderColor = Drac.comment.withAlphaComponent(0.3).cgColor
        cv.addSubview(msgField)
        y -= 36

        // Time label
        let timeLabel = field("Time", size: 13, weight: .medium, color: Drac.cyan)
        timeLabel.frame = NSRect(x: 32, y: y, width: 100, height: 18)
        cv.addSubview(timeLabel)
        y -= 30

        // Hour picker
        let hourLabel = field("Hour", size: 12, weight: .regular, color: Drac.comment)
        hourLabel.frame = NSRect(x: 32, y: y, width: 40, height: 16)
        cv.addSubview(hourLabel)

        let hourPicker = NSPopUpButton(frame: NSRect(x: 72, y: y - 2, width: 70, height: 24))
        for h in 0..<24 {
            let display = h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM"
            hourPicker.addItem(withTitle: display)
        }
        hourPicker.selectItem(at: reminder.hour)
        cv.addSubview(hourPicker)

        // Minute picker
        let minLabel = field("Min", size: 12, weight: .regular, color: Drac.comment)
        minLabel.frame = NSRect(x: 164, y: y, width: 30, height: 16)
        cv.addSubview(minLabel)

        let minPicker = NSPopUpButton(frame: NSRect(x: 196, y: y - 2, width: 60, height: 24))
        for m in stride(from: 0, to: 60, by: 5) {
            minPicker.addItem(withTitle: String(format: ":%02d", m))
        }
        // Select nearest 5-min slot
        let minIdx = reminder.minute / 5
        minPicker.selectItem(at: min(minIdx, minPicker.numberOfItems - 1))
        cv.addSubview(minPicker)

        y -= 40

        // Days label
        let daysLbl = field("Days", size: 13, weight: .medium, color: Drac.cyan)
        daysLbl.frame = NSRect(x: 32, y: y, width: 100, height: 18)
        cv.addSubview(daysLbl)
        y -= 32

        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var dayButtons: [NSButton] = []
        let btnW: CGFloat = 42
        let totalBtnsW = CGFloat(dayNames.count) * btnW + CGFloat(dayNames.count - 1) * 4
        var dx = (edW - totalBtnsW) / 2

        for (i, name) in dayNames.enumerated() {
            let dayNum = i + 1 // 1=Sun, 7=Sat
            let btn = PointerButton(frame: NSRect(x: dx, y: y, width: btnW, height: 28))
            btn.setButtonType(.toggle)
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.tag = dayNum
            btn.target = self
            btn.action = #selector(dayBtnToggled(_:))

            let isOn = reminder.days.contains(dayNum)
            btn.state = isOn ? .on : .off
            btn.layer?.backgroundColor = (isOn ? Drac.purple : Drac.currentLine).cgColor
            btn.attributedTitle = NSAttributedString(string: name, attributes: [
                .foregroundColor: isOn ? Drac.foreground : Drac.comment,
                .font: dmSans(size: 11, weight: .medium),
            ])

            cv.addSubview(btn)
            dayButtons.append(btn)
            dx += btnW + 4
        }

        y -= 36

        let everyDayHint = field("Leave all unselected for every day", size: 11, weight: .regular, color: Drac.comment)
        everyDayHint.alignment = .center
        everyDayHint.frame = NSRect(x: 0, y: y, width: edW, height: 14)
        cv.addSubview(everyDayHint)

        // Buttons
        let cancelBtn = HoverButton(
            "Cancel",
            bg: Drac.currentLine,
            hover: Drac.comment,
            fg: Drac.foreground,
            target: nil,
            action: nil
        )
        cancelBtn.translatesAutoresizingMaskIntoConstraints = true
        cancelBtn.frame = NSRect(x: edW / 2 - 160 - 8, y: 24, width: 160, height: 38)
        cv.addSubview(cancelBtn)

        let saveBtn = HoverButton(
            isNew ? "Add Reminder" : "Save",
            bg: Drac.currentLine,
            hover: Drac.selection,
            fg: Drac.purple,
            target: nil,
            action: nil
        )
        saveBtn.translatesAutoresizingMaskIntoConstraints = true
        saveBtn.frame = NSRect(x: edW / 2 + 8, y: 24, width: 160, height: 38)
        cv.addSubview(saveBtn)

        editorWindow = win

        // Position relative to main reminders window
        if let mainFrame = self.window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let x = mainFrame.minX + (mainFrame.width - edW) / 2
            let yPos = mainFrame.minY + (mainFrame.height - edH) / 2
            win.setFrameOrigin(NSPoint(x: x, y: yPos))
        }

        win.makeKeyAndOrderFront(nil)

        // Wire up buttons with closures via target/action
        cancelBtn.target = self
        cancelBtn.action = #selector(editorCancelTapped)

        // Save closure — capture the pickers
        class SaveContext {
            var reminder: Reminder
            var msgField: NSTextView
            var hourPicker: NSPopUpButton
            var minPicker: NSPopUpButton
            var dayButtons: [NSButton]
            var isNew: Bool
            init(reminder: Reminder, msgField: NSTextView, hourPicker: NSPopUpButton, minPicker: NSPopUpButton, dayButtons: [NSButton], isNew: Bool) {
                self.reminder = reminder
                self.msgField = msgField
                self.hourPicker = hourPicker
                self.minPicker = minPicker
                self.dayButtons = dayButtons
                self.isNew = isNew
            }
        }

        let ctx = SaveContext(reminder: reminder, msgField: msgField, hourPicker: hourPicker, minPicker: minPicker, dayButtons: dayButtons, isNew: isNew)
        objc_setAssociatedObject(saveBtn, "saveContext", ctx, .OBJC_ASSOCIATION_RETAIN)
        saveBtn.target = self
        saveBtn.action = #selector(editorSaveTapped(_:))
    }

    @objc private func editorCancelTapped() {
        editorWindow?.orderOut(nil)
        editorWindow = nil
    }

    @objc private func editorSaveTapped(_ sender: NSButton) {
        guard let ctx = objc_getAssociatedObject(sender, "saveContext") as AnyObject? else { return }

        // Extract values using KVC-safe approach
        let reminder = ctx.value(forKey: "reminder") as! Reminder
        let msgField = ctx.value(forKey: "msgField") as! NSTextView
        let hourPicker = ctx.value(forKey: "hourPicker") as! NSPopUpButton
        let minPicker = ctx.value(forKey: "minPicker") as! NSPopUpButton
        let dayButtons = ctx.value(forKey: "dayButtons") as! [NSButton]
        let isNew = ctx.value(forKey: "isNew") as! Bool

        var updated = reminder
        updated.message = msgField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.hour = hourPicker.indexOfSelectedItem
        updated.minute = minPicker.indexOfSelectedItem * 5

        var selectedDays = Set<Int>()
        for btn in dayButtons {
            if btn.state == .on {
                selectedDays.insert(btn.tag)
            }
        }
        updated.days = selectedDays

        if isNew {
            ReminderStore.shared.add(updated)
        } else {
            ReminderStore.shared.update(updated)
        }

        editorWindow?.orderOut(nil)
        editorWindow = nil
        rebuildList()
    }

    // MARK: - Field factory

    private func field(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Drac.foreground) -> NSTextField {
        let f = NSTextField(frame: .zero)
        f.stringValue = text
        f.font = dmSans(size: size, weight: weight)
        f.textColor = color
        f.backgroundColor = .clear
        f.isBezeled = false
        f.isEditable = false
        f.isSelectable = false
        f.maximumNumberOfLines = 1
        f.lineBreakMode = .byTruncatingTail
        return f
    }
}
