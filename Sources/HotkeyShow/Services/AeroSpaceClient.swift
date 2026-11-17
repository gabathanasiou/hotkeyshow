import Foundation

enum AeroSpaceError: LocalizedError {
    case binaryNotFound
    case commandFailed(arguments: [String], status: Int32, message: String)
    case timedOut([String])
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "AeroSpace CLI not found"
        case .commandFailed(let arguments, let status, let message):
            let detail = message.isEmpty ? "" : ": \(message)"
            return "aerospace \(arguments.joined(separator: " ")) failed (\(status))\(detail)"
        case .timedOut(let arguments):
            return "aerospace \(arguments.joined(separator: " ")) timed out"
        case .invalidOutput(let output):
            return "Unexpected AeroSpace output: \(output.prefix(200))"
        }
    }
}

/// Thin wrapper around the `aerospace` CLI.
///
/// The CLI talks to the running server, so `config --get` returns the config
/// AeroSpace has actually loaded (not re-parsed from disk). That is exactly
/// what a shortcut reminder should show.
final class AeroSpaceClient {
    static let shared = AeroSpaceClient()

    let binary: URL?

    private init() {
        binary = Self.locateBinary()
    }

    // MARK: - Locating the binary

    private static func locateBinary() -> URL? {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let custom = ProcessInfo.processInfo.environment["AEROSPACE_BIN"], !custom.isEmpty {
            candidates.append(custom)
        }
        candidates += [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
            "/Applications/AeroSpace.app/Contents/MacOS/aerospace",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/aerospace"),
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return loginShellBinary()
    }

    /// GUI apps inherit a minimal PATH, so as a last resort ask the user's
    /// login shell where `aerospace` lives.
    private static func loginShellBinary() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v aerospace"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Running commands

    private final class OutputCollector {
        var stdout = Data()
        var stderr = Data()
    }

    func run(_ arguments: [String], timeout: TimeInterval = 8) throws -> String {
        guard let binary else { throw AeroSpaceError.binaryNotFound }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw AeroSpaceError.commandFailed(
                arguments: arguments,
                status: -1,
                message: error.localizedDescription
            )
        }

        // Drain both pipes concurrently: a command that writes a lot of stderr
        // must not block on a full pipe while we wait for stdout.
        let collector = OutputCollector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            collector.stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            collector.stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        if process.isRunning {
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                throw AeroSpaceError.timedOut(arguments)
            }
        }
        process.waitUntilExit()
        readers.wait()

        let stdout = String(decoding: collector.stdout, as: UTF8.self)
        let stderr = String(decoding: collector.stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw AeroSpaceError.commandFailed(
                arguments: arguments,
                status: process.terminationStatus,
                message: stderr
            )
        }
        return stdout
    }

    // MARK: - Queries

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw AeroSpaceError.invalidOutput(output)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AeroSpaceError.invalidOutput(output)
        }
    }

    func listModes() throws -> [String] {
        struct Entry: Decodable {
            let id: String
            enum CodingKeys: String, CodingKey { case id = "mode-id" }
        }
        let output = try run(["list-modes", "--json"])
        return try decode([Entry].self, from: output).map(\.id)
    }

    func bindings(for mode: String) throws -> [String: String] {
        let output = try run(["config", "--get", "mode.\(mode).binding", "--json"])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        // A mode with no bindings can come back as something other than an
        // object; an empty sheet is a fine answer there.
        return (try? decode([String: String].self, from: output)) ?? [:]
    }

    /// One sheet per mode. Two CLI calls per mode: the mode list, then the
    /// whole binding map in a single `config --get`.
    func loadSheets() throws -> [ModeSheet] {
        let modes = try listModes()
        return modes.map { mode in
            let bindings = (try? bindings(for: mode)) ?? [:]
            return SheetBuilder.build(mode: mode, bindings: bindings)
        }
    }

    func currentMode() throws -> String {
        try run(["list-modes", "--current"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func focusedWorkspace() throws -> String {
        try run(["list-workspaces", "--focused"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func configPath() throws -> String {
        try run(["config", "--config-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reloadConfig() throws {
        _ = try run(["reload-config"])
    }

    func isRunning() -> Bool {
        (try? run(["list-modes", "--count"])) != nil
    }
}
