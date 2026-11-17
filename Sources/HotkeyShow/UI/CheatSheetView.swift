import SwiftUI

enum Theme {
    static let card = Color(red: 0.075, green: 0.082, blue: 0.095)
    static let stroke = Color.white.opacity(0.13)
    static let text = Color.white.opacity(0.90)
    static let dim = Color.white.opacity(0.42)
    static let faint = Color.white.opacity(0.28)
    static let peekAccent = Color(red: 0.47, green: 0.85, blue: 0.94)
    static let serviceAccent = Color(red: 1.0, green: 0.78, blue: 0.36)
    static let warning = Color(red: 1.0, green: 0.55, blue: 0.42)
}

struct SheetMetrics {
    var columnWidth: CGFloat
    var keycapFont: CGFloat
    var labelFont: CGFloat
    var keycapSlot: CGFloat
    var maxColumns: Int
    var padding: CGFloat
    var headerFont: CGFloat
    var groupTitleFont: CGFloat
    var rowSpacing: CGFloat
    var columnSpacing: CGFloat
    var cornerRadius: CGFloat

    static let peek = SheetMetrics(
        columnWidth: 200, keycapFont: 12, labelFont: 12, keycapSlot: 38,
        maxColumns: 3, padding: 20, headerFont: 11, groupTitleFont: 9.5,
        rowSpacing: 6, columnSpacing: 26, cornerRadius: 18
    )

    static let service = SheetMetrics(
        columnWidth: 210, keycapFont: 14.5, labelFont: 13, keycapSlot: 64,
        maxColumns: 3, padding: 22, headerFont: 11.5, groupTitleFont: 10,
        rowSpacing: 8, columnSpacing: 28, cornerRadius: 20
    )

    static let menu = SheetMetrics(
        columnWidth: 190, keycapFont: 12, labelFont: 12, keycapSlot: 56,
        maxColumns: 3, padding: 16, headerFont: 10.5, groupTitleFont: 9.5,
        rowSpacing: 6, columnSpacing: 16, cornerRadius: 14
    )
}

struct KeyCapView: View {
    let text: String
    var isExit: Bool = false
    var isHighlighted: Bool = false
    var fontSize: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .frame(minWidth: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHighlighted ? Color.white.opacity(0.92) : Color.white.opacity(0.095))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isExit ? Theme.serviceAccent.opacity(0.6) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
            )
    }

    private var foreground: Color {
        if isHighlighted { return Theme.card }
        return isExit ? Theme.serviceAccent : Color.white.opacity(0.93)
    }
}

struct SheetColumn: Identifiable {
    let id: Int
    let groups: [BindingGroup]
}

enum SheetLayout {
    /// Splits groups into balanced columns while keeping their order intact.
    ///
    /// Greedy shortest-column balancing is compact but scatters the reading
    /// order (Focus ends up on the right). This minimises the tallest column
    /// over contiguous runs, so columns read left to right, top to bottom, and
    /// a 9-row "workspaces" group stops leaving a hole beside "focus".
    static func columns(_ groups: [BindingGroup], count: Int) -> [SheetColumn] {
        guard !groups.isEmpty, count > 0 else { return [] }
        let columnCount = min(count, groups.count)
        let heights = groups.map { $0.rows.count + 2 }   // + heading

        // best[k][i] = lowest possible tallest column for the first i groups
        // laid out over k columns.
        var best = Array(repeating: Array(repeating: Int.max, count: groups.count + 1), count: columnCount + 1)
        var cut = Array(repeating: Array(repeating: 0, count: groups.count + 1), count: columnCount + 1)
        best[0][0] = 0

        for k in 1...columnCount {
            for i in 1...groups.count {
                var sum = 0
                for j in stride(from: i, through: 1, by: -1) {
                    sum += heights[j - 1]
                    guard best[k - 1][j - 1] != Int.max else { continue }
                    let candidate = max(best[k - 1][j - 1], sum)
                    if candidate < best[k][i] {
                        best[k][i] = candidate
                        cut[k][i] = j - 1
                    }
                }
            }
        }

        guard best[columnCount][groups.count] != Int.max else {
            // Degenerate fallback: even chunks.
            return groups.chunked(into: columnCount).enumerated().map {
                SheetColumn(id: $0.offset, groups: $0.element)
            }
        }

        var result: [[BindingGroup]] = []
        var index = groups.count
        for k in stride(from: columnCount, through: 1, by: -1) {
            let start = cut[k][index]
            result.append(Array(groups[start..<index]))
            index = start
        }
        result.reverse()
        return result.enumerated().map { SheetColumn(id: $0.offset, groups: $0.element) }
    }
}

private extension Array {
    func chunked(into count: Int) -> [[Element]] {
        guard count > 0 else { return [self] }
        let size = (self.count + count - 1) / count
        guard size > 0 else { return [self] }
        return stride(from: 0, to: self.count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, self.count)])
        }
    }
}

/// The cheat sheet itself. Shared by the overlay, the menu bar and the
/// snapshot renderer, so every surface shows the same thing.
struct CheatSheetView: View {
    let sheet: ModeSheet
    let title: String
    let subtitle: String
    let accent: Color
    let includeBasics: Bool
    let metrics: SheetMetrics
    var highlight: String? = nil
    var background: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if sheet.allGroups.isEmpty {
                Text("No bindings configured for this mode")
                    .font(.system(size: metrics.labelFont))
                    .foregroundStyle(Theme.dim)
            } else {
                let columns = SheetLayout.columns(
                    sheet.visibleGroups(includingBasics: includeBasics),
                    count: metrics.maxColumns
                )
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    ForEach(columns) { column in
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(column.groups) { group in
                                groupView(group)
                            }
                        }
                        .frame(width: metrics.columnWidth, alignment: .leading)
                    }
                }
            }

            if !includeBasics, let basics = sheet.basicsLine {
                Text(basics)
                    .font(.system(size: metrics.groupTitleFont + 0.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(metrics.padding)
        .background {
            if background {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(Theme.card.opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: metrics.headerFont, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(accent)
            Text(subtitle)
                .font(.system(size: metrics.headerFont - 0.5))
                .foregroundStyle(Theme.dim)
        }
    }

    private func groupView(_ group: BindingGroup) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            Text(group.category.title.uppercased())
                .font(.system(size: metrics.groupTitleFont, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 1)

            ForEach(group.rows) { row in
                rowView(row)
            }
        }
        .frame(width: metrics.columnWidth, alignment: .leading)
    }

    private func rowView(_ row: BindingRow) -> some View {
        let chord = row.chord.contains(sheet.baseModifiers)
            ? row.chord.stripped(of: sheet.baseModifiers)
            : row.chord

        return HStack(spacing: 8) {
            HStack(spacing: 0) {
                KeyCapView(
                    text: chord.display,
                    isExit: row.chord == sheet.primaryExit,
                    isHighlighted: highlight == row.id,
                    fontSize: metrics.keycapFont
                )
                Spacer(minLength: 0)
            }
            .frame(width: metrics.keycapSlot, alignment: .leading)

            Text(row.summary.label)
                .font(.system(size: metrics.labelFont))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .help(row.summary.raw)
    }
}

/// Wraps the sheet with the live app state so highlights and config refreshes
/// update without rebuilding the window.
struct HUDContentView: View {
    @ObservedObject var state: AppState
    let modeID: String
    let includeBasics: Bool
    let metrics: SheetMetrics

    var body: some View {
        if let sheet = state.sheets[modeID] {
            let isMain = modeID == "main"
            CheatSheetView(
                sheet: sheet,
                title: isMain ? holdTitle(sheet) : "\(modeID.uppercased()) MODE",
                subtitle: isMain ? "release to dismiss" : exitSubtitle(sheet),
                accent: isMain ? Theme.peekAccent : Theme.serviceAccent,
                includeBasics: includeBasics,
                metrics: metrics,
                highlight: state.highlight
            )
        } else {
            Color.clear
        }
    }

    private func holdTitle(_ sheet: ModeSheet) -> String {
        guard !sheet.baseModifiers.isEmpty else { return "SHORTCUTS" }
        return "HOLD " + sheet.baseModifiers.sorted { $0.sortOrder < $1.sortOrder }.map(\.symbol).joined()
    }

    private func exitSubtitle(_ sheet: ModeSheet) -> String {
        guard let exit = sheet.primaryExit else { return "modifier held" }
        let chord = exit.contains(sheet.baseModifiers) ? exit.stripped(of: sheet.baseModifiers) : exit
        return "\(chord.display) exits to main"
    }
}
