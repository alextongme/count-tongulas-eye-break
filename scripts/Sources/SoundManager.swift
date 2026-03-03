import Cocoa

class SoundManager {
    static let shared = SoundManager()

    // macOS system sounds available for user selection
    static let availableSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink",
    ]

    func playPromptSound() {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name(Preferences.shared.promptSound))?.play()
    }

    func playCompleteSound() {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name(Preferences.shared.completeSound))?.play()
    }

    func playMilestoneSound() {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name("Hero"))?.play()
    }

    func playSound(_ name: String) {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // Always plays regardless of soundEnabled — used for settings preview
    func previewSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
