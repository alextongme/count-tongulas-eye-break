import Cocoa

class StatsChartWindowController: NSObject {
    let window: NSWindow
    private var chartView: StatsChartView!
    private var segmentButtons: [NSButton] = []
    private var selectedSegment = 0
    private var summaryLabel: NSTextField!
    private var selectionIndicator: NSView!

    override init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.appearance = NSAppearance(named: .darkAqua)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = Drac.background
        win.hasShadow = true
        win.level = .floating
        self.window = win

        super.init()
        buildUI()
        updateChart()
        win.center()
    }

    private func buildUI() {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Drac.background.cgColor

        // Title
        let title = makeLabel("Break History", size: 24, weight: .bold, color: Drac.purple)
        cv.addSubview(title)

        // Custom segmented control
        let segContainer = NSView()
        segContainer.wantsLayer = true
        segContainer.layer?.backgroundColor = Drac.currentLine.cgColor
        segContainer.layer?.cornerRadius = 8
        segContainer.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(segContainer)

        // Selection indicator (slides behind the active tab)
        selectionIndicator = NSView()
        selectionIndicator.wantsLayer = true
        selectionIndicator.layer?.backgroundColor = Drac.purple.cgColor
        selectionIndicator.layer?.cornerRadius = 6
        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        segContainer.addSubview(selectionIndicator)

        let labels = ["7 Days", "30 Days"]
        let segStack = NSStackView()
        segStack.orientation = .horizontal
        segStack.spacing = 0
        segStack.distribution = .fillEqually
        segStack.translatesAutoresizingMaskIntoConstraints = false
        segContainer.addSubview(segStack)

        for (i, label) in labels.enumerated() {
            let btn = PointerButton()
            btn.isBordered = false
            btn.wantsLayer = true
            btn.tag = i
            btn.target = self
            btn.action = #selector(segmentTapped(_:))
            let color: NSColor = i == 0 ? Drac.foreground : Drac.comment
            btn.attributedTitle = NSAttributedString(string: label, attributes: [
                .foregroundColor: color,
                .font: dmSans(size: 13, weight: .semibold),
            ])
            btn.translatesAutoresizingMaskIntoConstraints = false
            segStack.addArrangedSubview(btn)
            segmentButtons.append(btn)
        }

        // Chart view
        chartView = StatsChartView()
        chartView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(chartView)

        // Summary label
        summaryLabel = makeLabel("", size: 14, weight: .regular, color: Drac.comment)
        cv.addSubview(summaryLabel)

        // Legend
        let legendStack = NSStackView()
        legendStack.orientation = .horizontal
        legendStack.spacing = 20
        legendStack.translatesAutoresizingMaskIntoConstraints = false

        let completedLegend = makeLegendItem(color: Drac.green, label: "Completed")
        let skippedLegend = makeLegendItem(color: Drac.orange, label: "Skipped")
        legendStack.addArrangedSubview(completedLegend)
        legendStack.addArrangedSubview(skippedLegend)
        cv.addSubview(legendStack)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: cv.topAnchor, constant: 28),
            title.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            segContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            segContainer.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            segContainer.widthAnchor.constraint(equalToConstant: 200),
            segContainer.heightAnchor.constraint(equalToConstant: 36),

            segStack.topAnchor.constraint(equalTo: segContainer.topAnchor, constant: 3),
            segStack.bottomAnchor.constraint(equalTo: segContainer.bottomAnchor, constant: -3),
            segStack.leadingAnchor.constraint(equalTo: segContainer.leadingAnchor, constant: 3),
            segStack.trailingAnchor.constraint(equalTo: segContainer.trailingAnchor, constant: -3),

            selectionIndicator.topAnchor.constraint(equalTo: segContainer.topAnchor, constant: 3),
            selectionIndicator.bottomAnchor.constraint(equalTo: segContainer.bottomAnchor, constant: -3),
            selectionIndicator.widthAnchor.constraint(equalTo: segContainer.widthAnchor, multiplier: 0.5, constant: -3),

            chartView.topAnchor.constraint(equalTo: segContainer.bottomAnchor, constant: 24),
            chartView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 50),
            chartView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -32),
            chartView.bottomAnchor.constraint(equalTo: legendStack.topAnchor, constant: -16),

            legendStack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            legendStack.bottomAnchor.constraint(equalTo: summaryLabel.topAnchor, constant: -10),

            summaryLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            summaryLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
        ])

        // Position the indicator on the first segment
        updateIndicatorPosition(animated: false)
    }

    private func updateIndicatorPosition(animated: Bool) {
        let leading = selectionIndicator.superview!.leadingAnchor
        // Remove old leading constraint
        for c in selectionIndicator.superview!.constraints where c.firstItem === selectionIndicator && c.firstAttribute == .leading {
            c.isActive = false
        }
        let offset: CGFloat = selectedSegment == 0 ? 3 : 100
        let constraint = selectionIndicator.leadingAnchor.constraint(equalTo: leading, constant: offset)
        constraint.isActive = true

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                selectionIndicator.superview?.layoutSubtreeIfNeeded()
            }
        }
    }

    private func makeLegendItem(color: NSColor, label: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6

        let swatch = NSView()
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 3
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 14),
            swatch.heightAnchor.constraint(equalToConstant: 14),
        ])

        let lbl = makeLabel(label, size: 12, weight: .medium, color: Drac.comment)
        stack.addArrangedSubview(swatch)
        stack.addArrangedSubview(lbl)
        return stack
    }

    @objc private func segmentTapped(_ sender: NSButton) {
        selectedSegment = sender.tag
        // Update button text colors
        for (i, btn) in segmentButtons.enumerated() {
            let color: NSColor = i == selectedSegment ? Drac.foreground : Drac.comment
            btn.attributedTitle = NSAttributedString(string: btn.attributedTitle.string, attributes: [
                .foregroundColor: color,
                .font: dmSans(size: 13, weight: .semibold),
            ])
        }
        updateIndicatorPosition(animated: true)
        updateChart()
    }

    private func updateChart() {
        let dayCount = selectedSegment == 0 ? 7 : 30
        let days = Statistics.shared.recentDays(count: dayCount)
        chartView.days = days

        let totalCompleted = days.reduce(0) { $0 + $1.completed }
        let totalSkipped = days.reduce(0) { $0 + $1.skipped }
        let total = totalCompleted + totalSkipped
        let rate = total > 0 ? Int(Double(totalCompleted) / Double(total) * 100) : 100
        let period = dayCount == 7 ? "This week" : "Last 30 days"
        summaryLabel.stringValue = "\(period): \(totalCompleted) completed, \(totalSkipped) skipped (\(rate)% approval)"
    }
}

// MARK: - Chart View

class StatsChartView: NSView {
    var days: [DayStats] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !days.isEmpty else { return }

        let barSpacing: CGFloat = 3
        let labelHeight: CGFloat = 24
        let chartArea = NSRect(
            x: bounds.minX + 36,
            y: bounds.minY + labelHeight,
            width: bounds.width - 36,
            height: bounds.height - labelHeight
        )

        let maxVal = max(days.map { $0.completed + $0.skipped }.max() ?? 1, 1)
        let barWidth = (chartArea.width - barSpacing * CGFloat(days.count - 1)) / CGFloat(days.count)

        // Y-axis labels
        for i in 0...4 {
            let val = Int(Double(maxVal) * Double(i) / 4.0)
            let y = chartArea.minY + chartArea.height * CGFloat(i) / 4.0
            let labelStr = "\(val)"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: Drac.comment,
                .font: dmMono(size: 10),
            ]
            let size = (labelStr as NSString).size(withAttributes: attrs)
            (labelStr as NSString).draw(at: NSPoint(x: chartArea.minX - size.width - 6, y: y - size.height / 2), withAttributes: attrs)

            // Grid line
            let gridPath = NSBezierPath()
            gridPath.move(to: NSPoint(x: chartArea.minX, y: y))
            gridPath.line(to: NSPoint(x: chartArea.maxX, y: y))
            Drac.currentLine.withAlphaComponent(0.5).setStroke()
            gridPath.lineWidth = 0.5
            gridPath.stroke()
        }

        // Bars
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = days.count <= 7 ? "EEE" : "M/d"

        for (i, day) in days.enumerated() {
            let x = chartArea.minX + (barWidth + barSpacing) * CGFloat(i)
            let total = day.completed + day.skipped
            let totalHeight = chartArea.height * CGFloat(total) / CGFloat(maxVal)
            let completedHeight = chartArea.height * CGFloat(day.completed) / CGFloat(maxVal)

            // Completed bar (green, bottom)
            if day.completed > 0 {
                let completedRect = NSRect(x: x, y: chartArea.minY, width: barWidth, height: completedHeight)
                let completedPath = NSBezierPath(roundedRect: completedRect, xRadius: 3, yRadius: 3)
                Drac.green.setFill()
                completedPath.fill()
            }

            // Skipped bar (orange, stacked on top)
            if day.skipped > 0 {
                let skippedRect = NSRect(x: x, y: chartArea.minY + completedHeight, width: barWidth, height: totalHeight - completedHeight)
                let skippedPath = NSBezierPath(roundedRect: skippedRect, xRadius: 3, yRadius: 3)
                Drac.orange.setFill()
                skippedPath.fill()
            }

            // X-axis label
            if let date = Statistics.dateFormatter.date(from: day.date) {
                let label = dateFormatter.string(from: date)
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Drac.comment,
                    .font: dmSans(size: 10),
                ]
                let size = (label as NSString).size(withAttributes: attrs)
                let labelX = x + (barWidth - size.width) / 2

                // Only show every Nth label to prevent overlap
                let showEvery = days.count <= 7 ? 1 : (days.count <= 14 ? 2 : 3)
                if i % showEvery == 0 || i == days.count - 1 {
                    (label as NSString).draw(at: NSPoint(x: labelX, y: chartArea.minY - labelHeight + 4), withAttributes: attrs)
                }
            }
        }
    }
}
