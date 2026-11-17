import Foundation

struct BindingRow: Identifiable, Hashable {
    let id: String          // raw chord as written in the config
    let chord: KeyChord
    let summary: CommandSummary
}

struct BindingGroup: Identifiable {
    let category: BindingCategory
    let rows: [BindingRow]
    var id: Int { category.rawValue }
}

/// One AeroSpace binding mode, laid out for display.
struct ModeSheet: Identifiable {
    let id: String
    let allGroups: [BindingGroup]
    /// Modifiers shared by most bindings in this mode. Shown once in the
    /// header ("hold ⌥") and stripped from each row.
    let baseModifiers: Set<KeyChord.Modifier>

    var allRows: [BindingRow] { allGroups.flatMap(\.rows) }

    /// A mode usually has one obvious way out. Preferring a plain `mode main`
    /// or the reload binding keeps the accent on the real escape hatch instead
    /// of on every one-shot binding that happens to end in `mode main`.
    var primaryExit: KeyChord? {
        let exits = allRows.filter(\.summary.isExit)
        let trimmed = { (row: BindingRow) in row.summary.raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let exact = exits.first(where: { trimmed($0) == "mode main" }) {
            return exact.chord
        }
        if let reload = exits.first(where: { trimmed($0).hasPrefix("reload-config") }) {
            return reload.chord
        }
        return exits.first?.chord
    }

    /// How you get back, in plain words. When every binding in a mode ends in
    /// `mode main` — as a one-shot service mode usually does — that is worth
    /// saying outright instead of leaving it to a tinted keycap.
    var returnHint: String? {
        guard !allRows.isEmpty else { return nil }
        if allRows.allSatisfy(\.summary.isExit) {
            return "Any key returns to main mode"
        }
        guard let exit = primaryExit else { return nil }
        let chord = exit.contains(baseModifiers) ? exit.stripped(of: baseModifiers) : exit
        return "\(chord.display) returns to main mode"
    }

    func visibleGroups(includingBasics: Bool) -> [BindingGroup] {
        allGroups.filter { includingBasics || !$0.category.isBasics }
    }

    /// One dim line summarising the bindings the peek hides, generated from
    /// the config rather than assumed.
    var basicsLine: String? {
        let hidden = allGroups.filter { $0.category.isBasics }
        guard !hidden.isEmpty else { return nil }
        let parts = hidden.map { group -> String in
            let keys = group.rows.map { $0.chord.stripped(of: baseModifiers).display }
            return "\(group.category.title): \(Self.compressed(keys))"
        }
        return parts.joined(separator: "   ·   ")
    }

    /// "1 2 3 4 5 6 7 8 9" -> "1–9", and a shared modifier prefix is pulled
    /// out so "⇧1 … ⇧9" becomes "⇧1–9". Anything else stays space separated.
    static func compressed(_ glyphs: [String]) -> String {
        guard let firstGlyph = glyphs.first else { return "" }

        var prefix = firstGlyph
        for glyph in glyphs.dropFirst() {
            var shared = ""
            for (left, right) in zip(prefix, glyph) where left == right {
                shared.append(left)
            }
            prefix = shared
            if prefix.isEmpty { break }
        }
        // A numeric remainder is what makes compression worthwhile; also keep
        // the prefix short so "⇧H"-style keys do not get mangled.
        let suffixes = glyphs.map { String($0.dropFirst(prefix.count)) }

        var out: [String] = []
        var index = 0
        while index < suffixes.count {
            var end = index
            while end + 1 < suffixes.count,
                  let current = Int(suffixes[end]),
                  let next = Int(suffixes[end + 1]),
                  next == current + 1 {
                end += 1
            }
            if end - index >= 2 {
                out.append("\(prefix)\(suffixes[index])–\(suffixes[end])")
            } else {
                out.append(contentsOf: suffixes[index...end].map { prefix + $0 })
            }
            index = end + 1
        }
        return out.joined(separator: " ")
    }
}

enum SheetBuilder {
    static func build(mode: String, bindings: [String: String]) -> ModeSheet {
        var rows: [BindingRow] = []
        for (rawChord, rawCommand) in bindings {
            guard let chord = KeyChord(configValue: rawChord) else {
                Log.write("skipping unparseable chord '\(rawChord)' in mode '\(mode)'")
                continue
            }
            rows.append(BindingRow(
                id: rawChord,
                chord: chord,
                summary: CommandFormatter.summarize(rawCommand)
            ))
        }

        var byCategory: [BindingCategory: [BindingRow]] = [:]
        for row in rows {
            byCategory[row.summary.category, default: []].append(row)
        }

        let groups = BindingCategory.allCases.compactMap { category -> BindingGroup? in
            guard let rows = byCategory[category], !rows.isEmpty else { return nil }
            let sorted = rows.sorted { lhs, rhs in
                let left = lhs.chord.keyGlyph
                let right = rhs.chord.keyGlyph
                if left != right {
                    return left.localizedStandardCompare(right) == .orderedAscending
                }
                return lhs.chord.modifiers.count < rhs.chord.modifiers.count
            }
            return BindingGroup(category: category, rows: sorted)
        }

        return ModeSheet(
            id: mode,
            allGroups: groups,
            baseModifiers: dominantModifiers(rows.map(\.chord.modifiers))
        )
    }

    /// The modifier set most bindings share. Ties go to the smaller set, so a
    /// mode made of plain keys plus a few modified ones gets an empty base and
    /// each row keeps its full chord.
    private static func dominantModifiers(_ sets: [Set<KeyChord.Modifier>]) -> Set<KeyChord.Modifier> {
        guard !sets.isEmpty else { return [] }
        var counts: [Set<KeyChord.Modifier>: Int] = [:]
        for set in sets { counts[set, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        let candidates = counts.filter { $0.value == best }.map(\.key)
        return candidates.sorted { $0.count < $1.count }.first ?? []
    }
}
