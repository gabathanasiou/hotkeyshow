import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    /// The menu window sizes to its content, and a ScrollView has no intrinsic
    /// height, so the sheet would collapse to nothing. Measure it, then clamp.
    @State private var sheetHeight: CGFloat = 320

    private struct SheetHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            bodyContent
            Divider()
            footer
        }
        .frame(width: 740)
        .background(VisualEffectBackground(material: .menu))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("HotkeyShow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Workspace \(state.workspace)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if state.isServiceMode {
                Text("\(state.mode) mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.exitAccent)
            }

            Spacer(minLength: 12)

            Button {
                state.refresh(reason: "manual")
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Reload shortcuts from AeroSpace")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        if state.loading && state.currentSheet == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading AeroSpace config…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        } else if let sheet = state.currentSheet {
            searchField
            if query.isEmpty {
                ScrollView {
                    cheatSheet(sheet)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
                            }
                        )
                }
                .frame(height: min(max(sheetHeight, 120), 620))
                .onPreferenceChange(SheetHeightKey.self) { height in
                    if abs(height - sheetHeight) > 0.5 { sheetHeight = height }
                }
            } else {
                results
            }
        } else {
            Text(state.errorMessage ?? "AeroSpace is not reachable")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
                .padding(20)
        }
    }

    private func cheatSheet(_ sheet: ModeSheet) -> some View {
        CheatSheetView(
            sheet: sheet,
            title: "\(sheet.id.capitalized) mode",
            subtitle: sheet.returnHint ?? "\(sheet.allRows.count) bindings · live from AeroSpace",
            includeBasics: true,
            metrics: .menu,
            highlight: state.highlight,
            background: false
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        SearchField(text: $query, placeholder: "Search shortcuts")
            .frame(height: 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var results: some View {
        let hits = state.search(query)
        if hits.isEmpty {
            Text("No shortcut matches “\(query)”")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(20)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(hits) { hit in
                        SearchResultRow(hit: hit, showsMode: hit.mode != state.mode)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: min(CGFloat(hits.count) * 25 + 12, 420))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Peek on hold ⌥", isOn: $state.peekEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(state.autoReload ? "Auto-reload on" : "Auto-reload off")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Menu {
                    Button("Refresh now") { state.refresh(reason: "manual") }
                    Button("Reload AeroSpace config") { state.reloadAeroSpaceConfig() }
                    Divider()
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { state.launchAtLoginEnabled },
                            set: { state.setLaunchAtLogin($0) }
                        )
                    )
                    Button("Check ⌥ detection") { state.checkDetection() }
                    if state.detectionStatus == .failed {
                        Button("Open Input Monitoring settings") { state.openInputMonitoringSettings() }
                    }
                    Divider()
                    Button("Reveal log") { state.revealLog() }
                    Button("Quit HotkeyShow") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let note = state.statusNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(state.statusIsWarning ? Theme.warning : .secondary)
                    .lineLimit(2)
            } else if state.detectionStatus == .testing {
                Text("Hold ⌥ now… testing detection")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

private struct SearchResultRow: View {
    let hit: AppState.SearchHit
    let showsMode: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(hit.row.summary.label)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if showsMode {
                Text(hit.mode)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text(hit.row.chord.display)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hit.row.summary.isExit ? Theme.exitAccent : .secondary)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.07) : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}
