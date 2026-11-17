import AppKit
import CoreGraphics

/// Watches the Option key through `CGEventSource.flagsState`.
///
/// This is a read-only query of session modifier state, not an event tap: no
/// keystrokes are logged, and nothing is intercepted. The peek appears only
/// after Option has been held still for `threshold` seconds, so normal fast
/// ⌥+key use never flashes it.
///
/// Polling runs at 10 Hz — enough for a 0.3 s threshold — and stops entirely
/// while the display is asleep.
@MainActor
final class ModifierWatcher {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var threshold: TimeInterval = 0.3

    private var timer: Timer?
    private var altSince: Date?
    private var peeking = false
    private var suppressed = false
    private var sleepObservers: [NSObjectProtocol] = []

    func start() {
        guard timer == nil else { return }
        installSleepObservers()
        startTimer()
    }

    func stop() {
        stopTimer()
        let center = NSWorkspace.shared.notificationCenter
        for observer in sleepObservers { center.removeObserver(observer) }
        sleepObservers.removeAll()
    }

    /// The user committed to a binding: hide the peek and stay quiet until
    /// Option is released, so it does not pop straight back up.
    func suppressUntilRelease() {
        suppressed = true
        if peeking {
            peeking = false
            onEnd?()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // The timer runs on the main run loop, but its block is not typed
            // as main-actor isolated. assumeIsolated asserts that instead of
            // allocating a Task on every tick (20 Tasks/s was measurable).
            if #available(macOS 14, *) {
                MainActor.assumeIsolated {
                    self.tick()
                }
            } else {
                Task { @MainActor in
                    self.tick()
                }
            }
        }
        // .common keeps the timer alive while menus or tracking loops run.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        altSince = nil
        if peeking {
            peeking = false
            onEnd?()
        }
    }

    private func installSleepObservers() {
        guard sleepObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopTimer() }
        })
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startTimer() }
        })
    }

    private func tick() {
        let altDown = Self.isOptionDown()

        if altDown {
            if altSince == nil { altSince = Date() }
            guard !peeking, !suppressed, let since = altSince else { return }
            if Date().timeIntervalSince(since) >= threshold {
                peeking = true
                onBegin?()
            }
        } else {
            altSince = nil
            suppressed = false
            if peeking {
                peeking = false
                onEnd?()
            }
        }
    }

    /// Read-only query of the session's modifier state. `flagsState` needs no
    /// TCC grant; the AppKit value is a cheap cross-check for the same table.
    static func isOptionDown() -> Bool {
        if CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
            return true
        }
        return NSEvent.modifierFlags.contains(.option)
    }
}
