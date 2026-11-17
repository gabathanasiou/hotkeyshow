import Foundation

/// The few things we read from the config file directly.
///
/// `aerospace config --get` only exposes a curated subset of keys (it does not
/// expose `auto-reload-config` or even `gaps`), so this one setting is read
/// from the file itself. Everything else comes from the running server.
enum AeroSpaceConfigFile {
    static func autoReloadEnabled(at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), line.hasPrefix("auto-reload-config") else { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return value.lowercased().hasPrefix("true")
        }
        return false
    }
}
