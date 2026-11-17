import SwiftUI

enum Theme {
    /// HUD surfaces stay dark on purpose; the fill is light enough that the
    /// .hudWindow vibrancy behind it still reads.
    static let hudFill = Color.black.opacity(0.45)
    static let hudStroke = Color.white.opacity(0.13)
    /// Only the "this key leaves the mode" affordance is tinted.
    static let exitAccent = Color(nsColor: .systemOrange)
    static let warning = Color(nsColor: .systemRed)
}

enum KeycapStyle {
    /// Rounded chip on the left — used by the HUD peek.
    case chip
    /// Plain shortcut text on the trailing edge, like a menu item.
    case trailingText
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
    var keycapStyle: KeycapStyle

    static let peek = SheetMetrics(
        columnWidth: 200, keycapFont: 12, labelFont: 13, keycapSlot: 38,
        maxColumns: 3, padding: 20, headerFont: 12, groupTitleFont: 11,
        rowSpacing: 6, columnSpacing: 24, cornerRadius: 18, keycapStyle: .chip
    )

    static let service = SheetMetrics(
        columnWidth: 220, keycapFont: 13.5, labelFont: 13, keycapSlot: 62,
        maxColumns: 3, padding: 20, headerFont: 12, groupTitleFont: 11,
        rowSpacing: 6, columnSpacing: 24, cornerRadius: 18, keycapStyle: .chip
    )

    static let menu = SheetMetrics(
        columnWidth: 220, keycapFont: 12, labelFont: 13, keycapSlot: 0,
        maxColumns: 3, padding: 16, headerFont: 13, groupTitleFont: 11,
        rowSpacing: 2, columnSpacing: 24, cornerRadius: 10, keycapStyle: .trailingText
    )
}

struct KeyCapView: View {
    let text: String
    var isExit: Bool = false
    var isHighlighted: Bool = false
    var fontSize: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .frame(minWidth: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHighlighted ? Color.white.opacity(0.92) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isExit ? Theme.exitAccent.opacity(0.7) : Color.white.opacity(0.13),
                        lineWidth: 1
                    )
            )
    }

    private var foreground: Color {
        if isHighlighted { return .black }
        return isExit ? Theme.exitAccent : Color.white.opacity(0.94)
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

/// A single binding row. Two presentations share the same data:
/// a HUD keycap chip, or a menu-style label with a trailing shortcut.
struct SheetRowView: View {
    let row: BindingRow
    let chord: KeyChord
    let isExit: Bool
    let isHighlighted: Bool
    let metrics: SheetMetrics
    var onNavigate: ((String) -> Void)? = nil

    @State private var hovering = false

    private var navigationTarget: String? {
        guard onNavigate != nil else { return nil }
        return row.summary.modeTarget
    }

    var body: some View {
        Group {
            if let target = navigationTarget, let onNavigate {
                Button {
                    onNavigate(target)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .help("Show \(target) mode shortcuts")
            } else {
                content
                    .help(row.summary.raw)
            }
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch metrics.keycapStyle {
        case .chip:
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    KeyCapView(
                        text: chord.display,
                        isExit: isExit,
                        isHighlighted: isHighlighted,
                        fontSize: metrics.keycapFont
                    )
                    Spacer(minLength: 0)
                }
                .frame(width: metrics.keycapSlot, alignment: .leading)

                Text(row.summary.label)
                    .font(.system(size: metrics.labelFont))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

        case .trailingText:
            HStack(spacing: 6) {
                Text(row.summary.label)
                    .font(.system(size: metrics.labelFont))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 6)

                Text(chord.display)
                    .font(.system(size: metrics.keycapFont, weight: .medium))
                    .foregroundStyle(isExit ? Theme.exitAccent : .secondary)
                    .lineLimit(1)
                    .fixedSize()

                if navigationTarget != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.07) : Color.clear)
            )
        }
    }
}

/// The cheat sheet itself. Shared by the overlay, the menu bar and the
/// snapshot renderer, so every surface shows the same thing.
struct CheatSheetView: View {
    let sheet: ModeSheet
    let title: String
    let subtitle: String
    let includeBasics: Bool
    let metrics: SheetMetrics
    var highlight: String? = nil
    var background: Bool = true
    var onNavigate: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if sheet.allGroups.isEmpty {
                Text("No bindings configured for this mode")
                    .font(.system(size: metrics.labelFont))
                    .foregroundStyle(.secondary)
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
                    .font(.system(size: metrics.groupTitleFont))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(metrics.padding)
        .background {
            if background {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(Theme.hudFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .stroke(Theme.hudStroke, lineWidth: 1)
                    )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: metrics.headerFont, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: max(11, metrics.headerFont - 2)))
                .foregroundStyle(.secondary)
        }
    }

    private func groupView(_ group: BindingGroup) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            Text(group.category.title)
                .font(.system(size: metrics.groupTitleFont, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, metrics.keycapStyle == .trailingText ? 3 : 1)

            ForEach(group.rows) { row in
                SheetRowView(
                    row: row,
                    chord: row.chord.contains(sheet.baseModifiers)
                        ? row.chord.stripped(of: sheet.baseModifiers)
                        : row.chord,
                    isExit: row.chord == sheet.primaryExit,
                    isHighlighted: highlight == row.id,
                    metrics: metrics,
                    onNavigate: onNavigate
                )
            }
        }
        .frame(width: metrics.columnWidth, alignment: .leading)
    }
}

/// Wraps the sheet with the live app state so highlights and config refreshes
/// update without rebuilding the window. The overlay is always dark, so the
/// color scheme is forced here rather than in the sheet itself.
struct HUDContentView: View {
    @ObservedObject var state: AppState
    let modeID: String
    let includeBasics: Bool
    let metrics: SheetMetrics

    var body: some View {
        Group {
            if let sheet = state.sheets[modeID] {
                let isMain = modeID == "main"
                CheatSheetView(
                    sheet: sheet,
                    title: isMain ? holdTitle(sheet) : "\(modeID.capitalized) mode",
                    subtitle: isMain ? "release to dismiss" : (sheet.returnHint ?? "modifier held"),
                    includeBasics: includeBasics,
                    metrics: metrics,
                    highlight: state.highlight
                )
            } else {
                Color.clear
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func holdTitle(_ sheet: ModeSheet) -> String {
        guard !sheet.baseModifiers.isEmpty else { return "Shortcuts" }
        return "Hold " + sheet.baseModifiers.sorted { $0.sortOrder < $1.sortOrder }.map(\.symbol).joined()
    }
}
