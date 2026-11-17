import Foundation

/// Where a binding belongs on a sheet. The order here is the column order.
enum BindingCategory: Int, CaseIterable, Identifiable {
    case focus
    case move
    case join
    case resize
    case layout
    case workspace
    case moveToWorkspace
    case fullscreen
    case monitor
    case navigation
    case mode
    case window
    case system
    case other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .move: return "Move window"
        case .join: return "Join window"
        case .resize: return "Resize"
        case .layout: return "Layout"
        case .workspace: return "Workspaces"
        case .moveToWorkspace: return "Send to workspace"
        case .fullscreen: return "Fullscreen"
        case .monitor: return "Monitors"
        case .navigation: return "Navigation"
        case .mode: return "Modes"
        case .window: return "Windows"
        case .system: return "AeroSpace"
        case .other: return "Other"
        }
    }

    /// Bindings the user already has in muscle memory. The peek hides these
    /// (it collapses them into one dim line instead); the full sheet keeps them.
    var isBasics: Bool {
        switch self {
        case .focus, .move, .workspace, .moveToWorkspace: return true
        default: return false
        }
    }
}

struct CommandSummary: Hashable {
    var label: String
    var category: BindingCategory
    /// True when the binding returns to the main mode, i.e. it is the way out.
    var isExit: Bool
    var raw: String
}

/// Turns AeroSpace command strings into something readable.
/// Purely presentational: unknown commands fall back to the raw text rather
/// than being dropped, so a custom config still shows up.
enum CommandFormatter {
    static func summarize(_ raw: String, mainMode: String = "main") -> CommandSummary {
        let commands = splitCommands(raw)
        guard let first = commands.first else {
            return CommandSummary(label: raw.isEmpty ? "—" : raw, category: .other, isExit: false, raw: raw)
        }

        let described = describe(first)
        let isExit = commands.contains { command in
            let tokens = command.split(separator: " ").map(String.init)
            return tokens.count >= 2 && tokens[0] == "mode" && tokens[1] == mainMode
        }

        var label = described.label
        if commands.count > 1 && !isExit {
            label += "  +\(commands.count - 1)"
        }
        return CommandSummary(
            label: label,
            category: described.category,
            isExit: isExit || described.isExit,
            raw: raw
        )
    }

    private static func splitCommands(_ raw: String) -> [String] {
        raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func describe(_ command: String) -> (label: String, category: BindingCategory, isExit: Bool) {
        let tokens = command.split(separator: " ").map(String.init)
        guard let name = tokens.first else { return ("—", .other, false) }
        let args = Array(tokens.dropFirst())
        let first = args.first ?? ""

        switch name {
        case "focus":
            return ("Focus \(direction(first))", .focus, false)
        case "move":
            return ("Move \(direction(first))", .move, false)
        case "join-with":
            return ("Join with \(arrow(first))", .join, false)
        case "resize":
            if args.count >= 2, args[0] == "smart" {
                if args[1].hasPrefix("-") { return ("Shrink", .resize, false) }
                if args[1].hasPrefix("+") { return ("Grow", .resize, false) }
            }
            return ("Resize \(args.joined(separator: " "))", .resize, false)
        case "workspace":
            return ("Workspace \(first)", .workspace, false)
        case "workspace-back-and-forth":
            return ("Back & forth", .navigation, false)
        case "focus-back-and-forth":
            return ("Focus back & forth", .navigation, false)
        case "move-node-to-workspace":
            return ("Send to \(first)", .moveToWorkspace, false)
        case "summon-workspace":
            return ("Summon \(first)", .moveToWorkspace, false)
        case "layout":
            if args.contains("tiles") { return ("Tiling", .layout, false) }
            if args.contains("accordion") { return ("Accordion", .layout, false) }
            if args.contains("floating") { return ("Toggle floating", .layout, false) }
            return ("Layout \(args.joined(separator: " "))", .layout, false)
        case "flatten-workspace-tree":
            return ("Reset layout", .layout, false)
        case "split":
            return ("Split \(first)", .layout, false)
        case "fullscreen", "macos-native-fullscreen":
            return ("Fullscreen", .fullscreen, false)
        case "macos-native-minimize":
            return ("Minimize", .fullscreen, false)
        case "move-workspace-to-monitor":
            return ("Workspace → next screen", .monitor, false)
        case "move-node-to-monitor":
            return ("Window → next screen", .monitor, false)
        case "focus-monitor":
            return ("Focus screen \(first)", .monitor, false)
        case "mode":
            return ("\(first.capitalized) mode", .mode, false)
        case "close":
            return ("Close window", .window, false)
        case "close-all-windows-but-current":
            return ("Close others", .window, false)
        case "reload-config":
            return ("Reload config", .system, false)
        case "balance-sizes":
            return ("Balance sizes", .system, false)
        case "enable", "disable":
            return ("\(name.capitalized) AeroSpace", .system, false)
        case "exec-and-forget", "exec-and-wait":
            return ("Run script", .system, false)
        case "trigger-binding", "run-callback", "move-mouse", "volume":
            return (pretty(name), .system, false)
        default:
            let suffix = first.isEmpty ? "" : " \(first)"
            return (pretty(name) + suffix, .other, false)
        }
    }

    private static func pretty(_ command: String) -> String {
        let words = command.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        guard let firstWord = words.first else { return command }
        return ([firstWord.prefix(1).uppercased() + firstWord.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    private static func direction(_ value: String) -> String {
        switch value {
        case "dfs-next": return "next"
        case "dfs-prev": return "previous"
        case "left", "down", "up", "right": return value
        default: return value
        }
    }

    private static func arrow(_ value: String) -> String {
        switch value {
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        default: return value
        }
    }
}
