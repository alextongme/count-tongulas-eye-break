import Cocoa
import IOKit

class IdleDetector {
    static let shared = IdleDetector()

    private(set) var isSystemSleeping = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // Cached state updated on a background queue every 3 seconds
    private let pollQueue = DispatchQueue(label: "com.counttongula.idledetector", qos: .utility)
    private var pollTimer: DispatchSourceTimer?
    private(set) var cachedIsScreenLocked = false
    private(set) var cachedIsDNDActive = false
    private(set) var cachedSecondsSinceLastInput: TimeInterval = 0

    // MARK: - Sleep/wake monitoring

    func startMonitoring() {
        let workspace = NSWorkspace.shared.notificationCenter

        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSystemSleeping = true
        }

        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSystemSleeping = false
        }

        startBackgroundPolling()
    }

    func stopMonitoring() {
        let workspace = NSWorkspace.shared.notificationCenter
        if let observer = sleepObserver {
            workspace.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            workspace.removeObserver(observer)
            wakeObserver = nil
        }
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Background polling

    /// Moves expensive I/O (IORegistry, file reads, CGEventSource IPC) off the main thread.
    /// Cached values are read by the 1-second UI timer without blocking compositing.
    private func startBackgroundPolling() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(3), leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.cachedIsScreenLocked = self.pollScreenLocked()
            self.cachedIsDNDActive = self.pollDNDActive()
            self.cachedSecondsSinceLastInput = self.pollSecondsSinceLastInput()
        }
        timer.resume()
        pollTimer = timer
    }

    // MARK: - Screen lock (IOKit IPC)

    private func pollScreenLocked() -> Bool {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }

        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            "IOConsoleLocked" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return false
        }
        return value
    }

    var isScreenLocked: Bool { cachedIsScreenLocked }

    // MARK: - DND / Focus (file I/O + JSON parse)

    private func pollDNDActive() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let assertionsURL = home
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

        guard let data = try? Data(contentsOf: assertionsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = root["data"] as? [[String: Any]]
        else { return false }

        for entry in dataArray {
            if let records = entry["storeAssertionRecords"] as? [Any], !records.isEmpty {
                return true
            }
        }
        return false
    }

    var isDNDActive: Bool { cachedIsDNDActive }

    // MARK: - Idle detection (WindowServer IPC)

    private func pollSecondsSinceLastInput() -> TimeInterval {
        let keyIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .keyDown)
        let mouseIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .mouseMoved)
        let clickIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .leftMouseDown)
        return min(keyIdle, min(mouseIdle, clickIdle))
    }

    var secondsSinceLastInput: TimeInterval { cachedSecondsSinceLastInput }

    var isUserIdle: Bool {
        guard Preferences.shared.idleDetectionEnabled else { return false }
        return cachedSecondsSinceLastInput >= TimeInterval(Preferences.shared.idleThreshold)
    }

    // MARK: - Break deferral

    var shouldDeferBreak: Bool {
        if isSystemSleeping { return true }
        if cachedIsScreenLocked { return true }
        if Preferences.shared.dndAware && cachedIsDNDActive { return true }
        return false
    }
}
