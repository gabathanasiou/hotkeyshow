import AppKit
import CoreGraphics

/// Watches the Option key through `CGEventSource.flagsState`.
///
/// This is a read-only query of session modifier state, not an event tap: no
/// keystrokes are logged, and nothing is intercepted. The peek appears only
/// after Option has been held still for `threshold` seconds, so normal fast
/// ⌥+key use never flashes it.
@MainActor
final class ModifierWatcher {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var threshold: TimeInterval = 0.3

    private var timer: Timer?
    private var altSince: Date?
    private var peeking = false
    private var suppressed = false

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps the timer alive while menus or tracking loops run.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

    /// Read-only query of session modifier state. `flagsState` needs no TCC
    /// grant (verified: no Input Monitoring, no Accessibility); the AppKit
    /// value is a cheap cross-check for the same state table.
    static func isOptionDown() -> Bool {
        if CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
            return true
        }
        return NSEvent.modifierFlags.contains(.option)
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
}
