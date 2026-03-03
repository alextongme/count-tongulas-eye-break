import Foundation

struct DayStats: Codable {
    var date: String  // "YYYY-MM-DD"
    var completed: Int = 0
    var skipped: Int = 0
    var snoozed: Int = 0
}

struct StatsData: Codable {
    var days: [DayStats] = []
    var longestStreak: Int = 0
    var currentStreakCount: Int = 0
}

class Statistics {
    static let shared = Statistics()

    private var data = StatsData()
    private let fileURL: URL

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayString: String {
        Statistics.dateFormatter.string(from: Date())
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CountTongula", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("statistics.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let jsonData = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StatsData.self, from: jsonData)
        else { return }
        data = decoded
    }

    private func save() {
        pruneOldDays()
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    private func pruneOldDays() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let cutoffString = Statistics.dateFormatter.string(from: cutoff)
        data.days = data.days.filter { $0.date >= cutoffString }
    }

    // MARK: - Today entry

    private func todayIndex() -> Int {
        let today = todayString
        if let idx = data.days.firstIndex(where: { $0.date == today }) {
            return idx
        }
        data.days.append(DayStats(date: today))
        return data.days.count - 1
    }

    // MARK: - Recording

    func recordBreakCompleted() {
        let idx = todayIndex()
        data.days[idx].completed += 1
        data.currentStreakCount += 1
        if data.currentStreakCount > data.longestStreak {
            data.longestStreak = data.currentStreakCount
        }
        save()
    }

    func recordBreakSkipped() {
        let idx = todayIndex()
        data.days[idx].skipped += 1
        data.currentStreakCount = 0
        save()
    }

    func recordBreakSnoozed() {
        let idx = todayIndex()
        data.days[idx].snoozed += 1
        save()
    }

    // MARK: - Computed stats

    var breaksCompletedToday: Int {
        let today = todayString
        return data.days.first(where: { $0.date == today })?.completed ?? 0
    }

    var breaksSkippedToday: Int {
        let today = todayString
        return data.days.first(where: { $0.date == today })?.skipped ?? 0
    }

    var breaksSnoozedToday: Int {
        let today = todayString
        return data.days.first(where: { $0.date == today })?.snoozed ?? 0
    }

    var currentStreak: Int {
        return data.currentStreakCount
    }

    var longestStreak: Int {
        return data.longestStreak
    }

    var nextStreak: Int {
        return data.currentStreakCount + 1
    }

    func nextStreakMilestone() -> String? {
        return Quotes.milestones[nextStreak]
    }

    var approvalRating: Int {
        let completed = breaksCompletedToday
        let skipped = breaksSkippedToday
        let total = completed + skipped
        guard total > 0 else { return 100 }
        return Int(Double(completed) / Double(total) * 100)
    }

    func todaySummary() -> String {
        return "Today: \(breaksCompletedToday) breaks, \(breaksSkippedToday) skipped"
    }

    func streakMessage() -> String? {
        return Quotes.milestones[currentStreak]
    }

    func recentDays(count: Int) -> [DayStats] {
        let calendar = Calendar.current
        var result: [DayStats] = []
        for i in (0..<count).reversed() {
            let date = calendar.date(byAdding: .day, value: -i, to: Date())!
            let dateStr = Statistics.dateFormatter.string(from: date)
            if let existing = data.days.first(where: { $0.date == dateStr }) {
                result.append(existing)
            } else {
                result.append(DayStats(date: dateStr))
            }
        }
        return result
    }
}
