import Foundation

/// A parsed AeroSpace binding key, e.g. `alt-shift-semicolon`.
///
/// AeroSpace writes chords as `modifier-modifier-key`, with `ctrl`, `alt`,
/// `shift` and `cmd`. Keys use AeroSpace's own vocabulary (`semicolon`,
/// `leftSquareBracket`, `pageDown`, …), so the glyph table below is the
/// translation layer between config and human.
struct KeyChord: Hashable {
    enum Modifier: String, CaseIterable, Hashable {
        case control = "ctrl"
        case alt
        case shift
        case command = "cmd"

        var symbol: String {
            switch self {
            case .control: return "⌃"
            case .alt: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }

        /// macOS convention: ⌃⌥⇧⌘
        var sortOrder: Int {
            switch self {
            case .control: return 0
            case .alt: return 1
            case .shift: return 2
            case .command: return 3
            }
        }

        var isHighBit: Bool { self == .alt || self == .command }
    }

    var modifiers: Set<Modifier>
    /// Key exactly as written in the config ("h", "semicolon", "tab").
    var key: String

    init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    init?(configValue raw: String) {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }

        var modifiers: Set<Modifier> = []
        for part in parts.dropLast() {
            guard let modifier = Modifier(rawValue: part) else { return nil }
            modifiers.insert(modifier)
        }
        self.init(modifiers: modifiers, key: key)
    }

    var configValue: String {
        let parts = modifiers.sorted { $0.sortOrder < $1.sortOrder }.map(\.rawValue) + [key]
        return parts.joined(separator: "-")
    }

    var modifierSymbols: String {
        modifiers.sorted { $0.sortOrder < $1.sortOrder }.map(\.symbol).joined()
    }

    /// The key without its modifiers, for sheets that strip a shared prefix.
    var keyGlyph: String {
        if let glyph = Self.glyphs[key] { return glyph }
        if key.count == 1 { return key.uppercased() }
        if key.lowercased().hasPrefix("f"), let number = Int(key.dropFirst()), (1...20).contains(number) {
            return "F\(number)"
        }
        return key
    }

    var display: String { modifierSymbols + keyGlyph }

    func stripped(of base: Set<Modifier>) -> KeyChord {
        guard modifiers.isSuperset(of: base) else { return self }
        return KeyChord(modifiers: modifiers.subtracting(base), key: key)
    }

    func contains(_ base: Set<Modifier>) -> Bool {
        modifiers.isSuperset(of: base)
    }

    private static let glyphs: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "tab": "⇥", "esc": "⎋", "backspace": "⌫", "enter": "↩", "space": "␣",
        "minus": "−", "equal": "=", "comma": ",", "period": ".", "slash": "/",
        "backslash": "\\", "quote": "'", "semicolon": ";", "backtick": "`",
        "leftSquareBracket": "[", "rightSquareBracket": "]",
        "forwardDelete": "⌦", "pageUp": "⇞", "pageDown": "⇟", "home": "↖", "end": "↘",
        "sectionSign": "§",
        "keypadClear": "⌧", "keypadDecimalMark": ".", "keypadDivide": "÷",
        "keypadEnter": "⌤", "keypadEqual": "=", "keypadMinus": "−",
        "keypadMultiply": "×", "keypadPlus": "+",
        "keypad0": "0", "keypad1": "1", "keypad2": "2", "keypad3": "3", "keypad4": "4",
        "keypad5": "5", "keypad6": "6", "keypad7": "7", "keypad8": "8", "keypad9": "9",
    ]
}
