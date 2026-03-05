import Cocoa

let appVersion = "0.10.0"

// ── Single-instance guard ────────────────────────────────────────────
// Skip lock for development/preview modes so they don't block normal app operation.
let devModes = ["--gallery", "--demo", "--screenshot", "--screenshot-all", "--screenshot-long", "--trigger-eye", "--trigger-long"]
let isDevMode = ProcessInfo.processInfo.arguments.contains(where: { devModes.contains($0) })
if !isDevMode {
    let lockFD = open("/tmp/com.counttongula.eyebreak.lock", O_WRONLY | O_CREAT, 0o600)
    if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        fputs("Another instance is already running.\n", stderr)
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No Dock icon

// Check for --screenshot mode (automated screenshot capture)
let args = ProcessInfo.processInfo.arguments

if args.contains("--demo") {
    // Demo mode: show each screen live for 3 seconds
    let pause: Double = 3.0

    // 1. Onboarding
    let onboarding = OnboardingController()
    onboarding.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
        onboarding.window.orderOut(nil)

        // 2. Settings
        let settings = SettingsWindowController()
        settings.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            settings.window.orderOut(nil)

            // 3. Eye break prompt
            let eyeBreak = BreakWindowController(type: .eye, allowSnooze: true)
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                // 4. Eye break countdown
                eyeBreak.showCountdown()

                DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                    // 5. Eye break complete
                    eyeBreak.timer?.invalidate()
                    eyeBreak.timer = nil
                    eyeBreak.showComplete()
                    // Cancel auto-quit so we control timing
                    for ow in eyeBreak.overlayWindows { ow.orderOut(nil) }

                    DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                        eyeBreak.window.orderOut(nil)

                        // 6. Long break prompt
                        let longBreak = BreakWindowController(type: .long, allowSnooze: true)
                        NSApp.activate(ignoringOtherApps: true)

                        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                            // 7. Long break countdown
                            longBreak.showCountdown()

                            DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
    }
} else if args.contains("--screenshot-all") {
    let outdir = args.last(where: { $0.hasPrefix("--outdir=") })
        .map { String($0.dropFirst("--outdir=".count)) } ?? "/tmp"
    let delay: Double = 0.5

    // 1. Onboarding
    let onboarding = OnboardingController()
    onboarding.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        captureWindow(onboarding.window, to: "\(outdir)/all-01-onboarding.png")
        onboarding.window.orderOut(nil)

        // 2. Settings
        let settings = SettingsWindowController()
        settings.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            captureWindow(settings.window, to: "\(outdir)/all-02-settings.png")
            settings.window.orderOut(nil)

            // 3. Eye break prompt
            let eyeBreak = BreakWindowController(type: .eye, allowSnooze: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                captureWindow(eyeBreak.window, to: "\(outdir)/all-03-eye-prompt.png")

                // 4. Eye break countdown
                eyeBreak.showCountdown()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    captureWindow(eyeBreak.window, to: "\(outdir)/all-04-eye-countdown.png")

                    // 5. Eye break complete
                    eyeBreak.timer?.invalidate()
                    eyeBreak.timer = nil
                    eyeBreak.heading.textColor = Drac.green
                    eyeBreak.heading.stringValue = "Break complete!"
                    eyeBreak.body.stringValue = "The night rewards those who rest."
                    eyeBreak.detail.stringValue = "You may return to your screen."
                    eyeBreak.body.isHidden = false
                    eyeBreak.detail.isHidden = false
                    eyeBreak.countdownLbl.isHidden = true
                    eyeBreak.countdownSub.isHidden = true
                    eyeBreak.progressBar.isHidden = true
                    eyeBreak.primaryBtn.setLabel("Thanks, Count!")
                    eyeBreak.primaryBtn.isHidden = false
                    eyeBreak.secondaryBtn.isHidden = true
                    eyeBreak.dismissBtn.isHidden = true
                    eyeBreak.escHint.isHidden = true
                    eyeBreak.enterHint.isHidden = false
                    eyeBreak.primaryPaired.isActive = false
                    eyeBreak.primaryCenterX.isActive = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        captureWindow(eyeBreak.window, to: "\(outdir)/all-05-eye-complete.png")
                        eyeBreak.window.orderOut(nil)
                        for ow in eyeBreak.overlayWindows { ow.orderOut(nil) }

                        // 6. Long break prompt
                        let longBreak = BreakWindowController(type: .long, allowSnooze: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            captureWindow(longBreak.window, to: "\(outdir)/all-06-long-prompt.png")

                            // 7. Long break countdown
                            longBreak.showCountdown()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                captureWindow(longBreak.window, to: "\(outdir)/all-07-long-countdown.png")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
    }
} else if args.contains("--gallery") {
    // Gallery mode: arrow keys to cycle through all screens
    print("Gallery mode: → next, ← prev, Esc quit")

    let galleryScreens: [(String, String)] = [
        ("eye", "prompt"), ("eye", "countdown"), ("eye", "complete"), ("eye", "milestone"),
        ("long", "prompt"), ("long", "countdown"), ("long", "complete"), ("long", "milestone"),
        ("settings", "settings"),
    ]
    var galleryIndex = 0
    var galleryCtrl: BreakWindowController?
    var gallerySettings: SettingsWindowController?

    func showGallery() {
        // Clean up previous controller
        galleryCtrl?.timer?.invalidate()
        galleryCtrl?.timer = nil
        galleryCtrl?.overlayWindows.forEach { $0.orderOut(nil) }
        galleryCtrl?.window.orderOut(nil)
        gallerySettings?.window.orderOut(nil)
        galleryCtrl = nil
        gallerySettings = nil

        let (category, screen) = galleryScreens[galleryIndex]

        if category == "settings" {
            let settings = SettingsWindowController()
            settings.window.makeKeyAndOrderFront(nil)
            gallerySettings = settings
        } else {
            let type: BreakType = category == "long" ? .long : .eye
            let ctrl = BreakWindowController(type: type, allowSnooze: true)

            if screen == "countdown" {
                ctrl.showCountdown()
                ctrl.timer?.invalidate()
                ctrl.timer = nil
            } else if screen == "complete" {
                ctrl.showComplete()
            } else if screen == "milestone" {
                ctrl.showMilestonePreview()
            }

            galleryCtrl = ctrl
        }

        print("  [\(galleryIndex + 1)/\(galleryScreens.count)] \(category) — \(screen)")
        NSApp.activate(ignoringOtherApps: true)
    }

    showGallery()

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        switch event.keyCode {
        case 124 where galleryIndex < galleryScreens.count - 1:
            galleryIndex += 1; showGallery()
        case 123 where galleryIndex > 0:
            galleryIndex -= 1; showGallery()
        case 53:
            NSApp.terminate(nil)
        default: break
        }
        return event
    }
} else if args.contains("--trigger-long") {
    // Interactive long break — shows the real window you can interact with
    let controller = BreakWindowController(type: .long, allowSnooze: true)
    // Keep a strong reference so it doesn't get deallocated
    _ = controller
} else if args.contains("--trigger-eye") {
    // Interactive eye break
    let controller = BreakWindowController(type: .eye, allowSnooze: true)
    _ = controller
} else if args.contains("--screenshot-long") {
    let outdir = args.last(where: { $0.hasPrefix("--outdir=") })
        .map { String($0.dropFirst("--outdir=".count)) } ?? "/tmp"

    let controller = BreakWindowController(type: .long, allowSnooze: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        captureWindow(controller.window, to: "\(outdir)/screenshot-long-prompt.png")

        controller.showCountdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            captureWindow(controller.window, to: "\(outdir)/screenshot-long-countdown.png")
            NSApp.terminate(nil)
        }
    }
} else if args.contains("--screenshot") {
    // Screenshot mode: show break window, cycle through phases, capture screenshots
    let outdir = args.last(where: { $0.hasPrefix("--outdir=") })
        .map { String($0.dropFirst("--outdir=".count)) } ?? "/tmp"

    let controller = BreakWindowController(type: .eye, allowSnooze: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        captureWindow(controller.window, to: "\(outdir)/screenshot-prompt.png")

        controller.showCountdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            captureWindow(controller.window, to: "\(outdir)/screenshot-countdown.png")

            controller.timer?.invalidate()
            // Manually set complete state for screenshot
            controller.heading.textColor = Drac.green
            controller.heading.stringValue = "Break complete!"
            controller.body.stringValue = "The night rewards those who rest."
            controller.detail.stringValue = "You may return to your screen."
            controller.body.isHidden = false
            controller.detail.isHidden = false
            controller.countdownLbl.isHidden = true
            controller.countdownSub.isHidden = true
            controller.progressBar.isHidden = true
            controller.primaryBtn.setLabel("Thanks, Count!")
            controller.primaryBtn.isHidden = false
            controller.secondaryBtn.isHidden = true
            controller.dismissBtn.isHidden = true
            controller.primaryPaired.isActive = false
            controller.primaryCenterX.isActive = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                captureWindow(controller.window, to: "\(outdir)/screenshot-complete.png")
                NSApp.terminate(nil)
            }
        }
    }
} else {
    // Normal mode: launch as persistent menu bar app
    let delegate = AppDelegate()
    app.delegate = delegate
}

app.run()
