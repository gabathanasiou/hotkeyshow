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
            divider
            bodyContent
            divider
            footer
        }
        .frame(width: 660)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("HotkeyShow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            chip("workspace \(state.workspace)")
            if state.isServiceMode {
                chip("\(state.mode) mode", tint: Theme.serviceAccent)
            }

            Spacer(minLength: 12)

            Button {
                state.refresh(reason: "manual")
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.dim)
            .help("Reload shortcuts from AeroSpace")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chip(_ text: String, tint: Color = Theme.dim) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        if state.loading && state.currentSheet == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading AeroSpace config…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
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
            title: "\(sheet.id.uppercased()) MODE",
            subtitle: "\(sheet.allRows.count) bindings · live from AeroSpace",
            accent: state.isServiceMode ? Theme.serviceAccent : Theme.peekAccent,
            includeBasics: true,
            metrics: .menu,
            highlight: state.highlight,
            background: false
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .frame(width: 13)
            TextField("Search shortcuts", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var results: some View {
        let hits = state.search(query)
        if hits.isEmpty {
            Text("No shortcut matches “\(query)”")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .padding(20)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(hits) { hit in
                        HStack(spacing: 10) {
                            HStack(spacing: 0) {
                                KeyCapView(
                                    text: hit.row.chord.display,
                                    isExit: hit.row.summary.isExit,
                                    fontSize: 11
                                )
                                Spacer(minLength: 0)
                            }
                            .frame(width: 76, alignment: .leading)

                            Text(hit.row.summary.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            if hit.mode != state.mode {
                                Text(hit.mode)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(height: min(CGFloat(hits.count) * 26 + 10, 420))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Peek on hold ⌥", isOn: $state.peekEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)

                Spacer(minLength: 8)

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

                Text(state.autoReload ? "auto-reload on" : "auto-reload off")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }

            if let note = state.statusNote {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(state.statusIsWarning ? Theme.warning : Theme.dim)
                    .lineLimit(2)
            } else if state.detectionStatus == .testing {
                Text("Hold ⌥ now… testing detection")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.peekAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}
