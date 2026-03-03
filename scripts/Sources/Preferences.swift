import Foundation

class Preferences {
    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("CountTongulaPreferencesDidChange")

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case breakInterval, breakDuration, snoozeDuration, autoQuitDelay
        case soundEnabled, promptSound, completeSound
        case dndAware, idleDetectionEnabled, idleThreshold
        case launchAtLogin, fullscreenOverlay, cloudsEnabled
        case longBreakEnabled, longBreakEveryN, longBreakDuration
        case hasCompletedOnboarding
        case strictMode, appExclusionEnabled, excludedBundleIDs, preBreakNotifyEnabled
    }

    init() { registerDefaults() }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.breakInterval.rawValue: 1200,
            Key.breakDuration.rawValue: 20,
            Key.snoozeDuration.rawValue: 300,
            Key.autoQuitDelay.rawValue: 8,
            Key.soundEnabled.rawValue: true,
            Key.promptSound.rawValue: "Sosumi",
            Key.completeSound.rawValue: "Blow",
            Key.dndAware.rawValue: true,
            Key.idleDetectionEnabled.rawValue: true,
            Key.idleThreshold.rawValue: 300,
            Key.launchAtLogin.rawValue: true,
            Key.fullscreenOverlay.rawValue: true,
            Key.cloudsEnabled.rawValue: true,
            Key.longBreakEnabled.rawValue: true,
            Key.longBreakEveryN.rawValue: 3,
            Key.longBreakDuration.rawValue: 300,
            Key.hasCompletedOnboarding.rawValue: false,
            Key.strictMode.rawValue: false,
            Key.appExclusionEnabled.rawValue: true,
            Key.excludedBundleIDs.rawValue: ["us.zoom.xos", "com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "com.microsoft.teams2", "com.microsoft.teams", "com.cisco.webexmeetingsapp", "com.apple.FaceTime"],
            Key.preBreakNotifyEnabled.rawValue: true,
        ])
    }

    private func notify() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }

    var breakInterval: Int {
        get { defaults.integer(forKey: Key.breakInterval.rawValue) }
        set { defaults.set(newValue, forKey: Key.breakInterval.rawValue); notify() }
    }

    var breakDuration: Int {
        get { defaults.integer(forKey: Key.breakDuration.rawValue) }
        set { defaults.set(newValue, forKey: Key.breakDuration.rawValue); notify() }
    }

    var snoozeDuration: Int {
        get { defaults.integer(forKey: Key.snoozeDuration.rawValue) }
        set { defaults.set(newValue, forKey: Key.snoozeDuration.rawValue); notify() }
    }

    var autoQuitDelay: Int {
        get { defaults.integer(forKey: Key.autoQuitDelay.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoQuitDelay.rawValue); notify() }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.soundEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.soundEnabled.rawValue); notify() }
    }

    var promptSound: String {
        get { defaults.string(forKey: Key.promptSound.rawValue) ?? "Sosumi" }
        set { defaults.set(newValue, forKey: Key.promptSound.rawValue); notify() }
    }

    var completeSound: String {
        get { defaults.string(forKey: Key.completeSound.rawValue) ?? "Blow" }
        set { defaults.set(newValue, forKey: Key.completeSound.rawValue); notify() }
    }

    var dndAware: Bool {
        get { defaults.bool(forKey: Key.dndAware.rawValue) }
        set { defaults.set(newValue, forKey: Key.dndAware.rawValue); notify() }
    }

    var idleDetectionEnabled: Bool {
        get { defaults.bool(forKey: Key.idleDetectionEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.idleDetectionEnabled.rawValue); notify() }
    }

    var idleThreshold: Int {
        get { defaults.integer(forKey: Key.idleThreshold.rawValue) }
        set { defaults.set(newValue, forKey: Key.idleThreshold.rawValue); notify() }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue); notify() }
    }

    var fullscreenOverlay: Bool {
        get { defaults.bool(forKey: Key.fullscreenOverlay.rawValue) }
        set { defaults.set(newValue, forKey: Key.fullscreenOverlay.rawValue); notify() }
    }

    var cloudsEnabled: Bool {
        get { defaults.bool(forKey: Key.cloudsEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.cloudsEnabled.rawValue); notify() }
    }

    var longBreakEnabled: Bool {
        get { defaults.bool(forKey: Key.longBreakEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.longBreakEnabled.rawValue); notify() }
    }

    var longBreakEveryN: Int {
        get { defaults.integer(forKey: Key.longBreakEveryN.rawValue) }
        set { defaults.set(newValue, forKey: Key.longBreakEveryN.rawValue); notify() }
    }

    var longBreakDuration: Int {
        get { defaults.integer(forKey: Key.longBreakDuration.rawValue) }
        set { defaults.set(newValue, forKey: Key.longBreakDuration.rawValue); notify() }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding.rawValue); notify() }
    }

    var strictMode: Bool {
        get { defaults.bool(forKey: Key.strictMode.rawValue) }
        set { defaults.set(newValue, forKey: Key.strictMode.rawValue); notify() }
    }

    var appExclusionEnabled: Bool {
        get { defaults.bool(forKey: Key.appExclusionEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.appExclusionEnabled.rawValue); notify() }
    }

    var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.excludedBundleIDs.rawValue) ?? [] }
        set { defaults.set(newValue, forKey: Key.excludedBundleIDs.rawValue); notify() }
    }

    var preBreakNotifyEnabled: Bool {
        get { defaults.bool(forKey: Key.preBreakNotifyEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.preBreakNotifyEnabled.rawValue); notify() }
    }
}
