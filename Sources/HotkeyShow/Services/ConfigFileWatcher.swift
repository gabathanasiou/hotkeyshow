import Foundation

/// Polls the config file for changes.
///
/// A 1 s stat poll is deliberately boring: it survives atomic writes, editor
/// rename dances, symlinked configs and editors that keep the old inode.
/// Config edits are rare, so the cost is irrelevant.
final class ConfigFileWatcher {
    private let url: URL
    private var timer: Timer?
    private var signature: String

    var onChange: (() -> Void)?

    init(url: URL) {
        self.url = url
        signature = Self.signature(of: url)
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = Self.signature(of: url)
        guard current != signature else { return }
        signature = current
        Log.write("config file changed (\(url.lastPathComponent))")
        onChange?()
    }

    private static func signature(of url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "missing"
        }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return "\(modified)-\(size)"
    }
}
