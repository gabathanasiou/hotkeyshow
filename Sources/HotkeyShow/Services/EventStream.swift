import Foundation

/// Streams `aerospace subscribe --all` JSON lines.
///
/// This is how the app stays contextual without any keyboard monitoring:
/// AeroSpace tells us when the mode changes, when a binding fires and which
/// workspace is focused.
final class EventStream {
    struct Event: Decodable {
        let name: String
        let mode: String?
        let binding: String?
        let workspace: String?
        let prevWorkspace: String?
        let monitorId: Int?

        enum CodingKeys: String, CodingKey {
            case name = "_event"
            case mode, binding, workspace, prevWorkspace, monitorId
        }
    }

    var onEvent: ((Event) -> Void)?
    var onStatusChange: ((Bool) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var restartScheduled = false
    private var restartDelay: TimeInterval = 2

    func start() {
        guard process == nil, !restartScheduled else { return }
        guard let binary = AeroSpaceClient.shared.binary else {
            Log.write("event stream: aerospace binary not found")
            scheduleRestart()
            return
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["subscribe", "--all"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
                self?.onStatusChange?(false)
                Log.write("event stream ended, retrying in \(self?.restartDelay ?? 2)s")
                self?.scheduleRestart()
            }
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        do {
            try process.run()
            self.process = process
            restartDelay = 2
            Log.write("event stream connected")
            onStatusChange?(true)
        } catch {
            Log.write("event stream failed to start: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    private func scheduleRestart() {
        guard !restartScheduled else { return }
        restartScheduled = true
        let delay = restartDelay
        restartDelay = min(restartDelay * 1.6, 15)
        Log.write("event stream retrying in \(Int(delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.restartScheduled = false
            self.start()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            guard let event = try? JSONDecoder().decode(Event.self, from: line) else {
                Log.write("event stream: unparseable line \(String(decoding: line, as: UTF8.self))")
                continue
            }
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        }
        // A runaway buffer means we are not actually reading newlines.
        if buffer.count > 1_000_000 { buffer.removeAll() }
    }
}
