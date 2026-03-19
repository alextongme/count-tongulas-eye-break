import Foundation

struct Reminder: Codable {
    var id: UUID
    var message: String
    var hour: Int       // 0-23
    var minute: Int     // 0-59
    var days: Set<Int>  // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat. Empty = every day
    var enabled: Bool

    init(id: UUID = UUID(), message: String = "", hour: Int = 9, minute: Int = 0, days: Set<Int> = [], enabled: Bool = true) {
        self.id = id
        self.message = message
        self.hour = hour
        self.minute = minute
        self.days = days
        self.enabled = enabled
    }

    /// Human-readable time string (e.g. "9:00 AM")
    var timeString: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    /// Human-readable days string
    var daysString: String {
        if days.isEmpty { return "Every day" }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = days.sorted()
        return sorted.map { names[$0] }.joined(separator: ", ")
    }
}

// MARK: - Persistence

class ReminderStore {
    static let shared = ReminderStore()
    static let didChangeNotification = Notification.Name("CountTongulaRemindersDidChange")

    private(set) var reminders: [Reminder] = []

    /// Tracks which reminders have already fired today: [reminderID: dateString]
    private var firedToday: [String: String] = [:]

    private var filePath: String {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CountTongula")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reminders.json").path
    }

    init() { load() }

    func load() {
        guard let data = FileManager.default.contents(atPath: filePath) else { return }
        if let decoded = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = decoded
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        FileManager.default.createFile(atPath: filePath, contents: data)
        NotificationCenter.default.post(name: ReminderStore.didChangeNotification, object: self)
    }

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        save()
    }

    func update(_ reminder: Reminder) {
        if let idx = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[idx] = reminder
            save()
        }
    }

    func delete(at index: Int) {
        guard index >= 0 && index < reminders.count else { return }
        reminders.remove(at: index)
        save()
    }

    // MARK: - Scheduling

    /// Returns reminders that should fire right now (haven't fired yet today, time matches, day matches).
    func dueReminders() -> [Reminder] {
        let cal = Calendar.current
        let now = Date()
        let todayStr = dateString(now)
        let currentHour = cal.component(.hour, from: now)
        let currentMinute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 7=Sat

        return reminders.filter { r in
            guard r.enabled else { return false }
            guard r.hour == currentHour && r.minute == currentMinute else { return false }
            if !r.days.isEmpty && !r.days.contains(weekday) { return false }
            let key = r.id.uuidString
            if firedToday[key] == todayStr { return false }
            return true
        }
    }

    /// Mark a reminder as fired for today.
    func markFired(_ reminder: Reminder) {
        firedToday[reminder.id.uuidString] = dateString(Date())
    }

    /// Clean up stale entries (called once per day or on check).
    func cleanFiredCache() {
        let today = dateString(Date())
        firedToday = firedToday.filter { $0.value == today }
    }

    private func dateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}
