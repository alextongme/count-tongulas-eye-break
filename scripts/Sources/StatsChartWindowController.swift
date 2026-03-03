import Cocoa

class StatsChartWindowController: NSObject {
    let window: NSWindow
    private var chartView: StatsChartView!
    private var segmentedControl: NSSegmentedControl!
    private var summaryLabel: NSTextField!

    override init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
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
        let title = makeLabel("Break History", size: 20, weight: .bold, color: Drac.purple)
        cv.addSubview(title)

        // Segmented control
        segmentedControl = NSSegmentedControl(labels: ["7 Days", "30 Days"], trackingMode: .selectOne, target: self, action: #selector(segmentChanged))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(segmentedControl)

        // Chart view
        chartView = StatsChartView()
        chartView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(chartView)

        // Summary label
        summaryLabel = makeLabel("", size: 13, weight: .regular, color: Drac.comment)
        cv.addSubview(summaryLabel)

        // Legend
        let legendStack = NSStackView()
        legendStack.orientation = .horizontal
        legendStack.spacing = 16
        legendStack.translatesAutoresizingMaskIntoConstraints = false

        let completedLegend = makeLegendItem(color: Drac.green, label: "Completed")
        let skippedLegend = makeLegendItem(color: Drac.orange, label: "Skipped")
        legendStack.addArrangedSubview(completedLegend)
        legendStack.addArrangedSubview(skippedLegend)
        cv.addSubview(legendStack)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            title.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            segmentedControl.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            segmentedControl.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            chartView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            chartView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 40),
            chartView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),
            chartView.bottomAnchor.constraint(equalTo: legendStack.topAnchor, constant: -12),

            legendStack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            legendStack.bottomAnchor.constraint(equalTo: summaryLabel.topAnchor, constant: -8),

            summaryLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            summaryLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
        ])
    }

    private func makeLegendItem(color: NSColor, label: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4

        let swatch = NSView()
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 3
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 12),
            swatch.heightAnchor.constraint(equalToConstant: 12),
        ])

        let lbl = makeLabel(label, size: 11, weight: .medium, color: Drac.comment)
        stack.addArrangedSubview(swatch)
        stack.addArrangedSubview(lbl)
        return stack
    }

    @objc private func segmentChanged() {
        updateChart()
    }

    private func updateChart() {
        let dayCount = segmentedControl.selectedSegment == 0 ? 7 : 30
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

        let barSpacing: CGFloat = 2
        let labelHeight: CGFloat = 20
        let chartArea = NSRect(
            x: bounds.minX + 30,
            y: bounds.minY + labelHeight,
            width: bounds.width - 30,
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
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            ]
            let size = (labelStr as NSString).size(withAttributes: attrs)
            (labelStr as NSString).draw(at: NSPoint(x: chartArea.minX - size.width - 4, y: y - size.height / 2), withAttributes: attrs)

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
                let completedPath = NSBezierPath(roundedRect: completedRect, xRadius: 2, yRadius: 2)
                Drac.green.setFill()
                completedPath.fill()
            }

            // Skipped bar (orange, stacked on top)
            if day.skipped > 0 {
                let skippedRect = NSRect(x: x, y: chartArea.minY + completedHeight, width: barWidth, height: totalHeight - completedHeight)
                let skippedPath = NSBezierPath(roundedRect: skippedRect, xRadius: 2, yRadius: 2)
                Drac.orange.setFill()
                skippedPath.fill()
            }

            // X-axis label
            if let date = Statistics.dateFormatter.date(from: day.date) {
                let label = dateFormatter.string(from: date)
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Drac.comment,
                    .font: NSFont.systemFont(ofSize: 9),
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
