import Cocoa

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
    var delay: Double = 0.5

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
