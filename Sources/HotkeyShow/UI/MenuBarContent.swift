import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    /// Browsing a mode's shortcuts from the menu without being in that mode.
    @State private var previewMode: String?

    private var displayedModeID: String { previewMode ?? state.mode }
    private var isPreviewing: Bool { previewMode != nil && previewMode != state.mode }
    private var displayedSheet: ModeSheet? {
        state.sheets[displayedModeID] ?? state.sheets[state.mode]
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
        .onChange(of: state.mode) { _ in
            // AeroSpace changed mode for real; stop previewing the old one.
            previewMode = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if isPreviewing {
                Button {
                    previewMode = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Back to \(state.mode) mode")
            }

            Text("HotkeyShow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if isPreviewing, let previewMode {
                Text("\(previewMode) mode preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.exitAccent)
            } else if state.isServiceMode {
                Text("\(state.mode) mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.exitAccent)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        if state.loading && state.sheets[displayedModeID] == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading AeroSpace config…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        } else if let sheet = displayedSheet {
            searchField
            if query.isEmpty {
                sheetBody(sheet)
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

    /// Tall sheets scroll inside a fixed window; short ones let the window size
    /// to the content. Deriving this from the sheet avoids a stale measured
    /// height making a short mode open inside a tall panel.
    @ViewBuilder
    private func sheetBody(_ sheet: ModeSheet) -> some View {
        let height = CheatSheetView.estimatedHeight(sheet: sheet, includeBasics: true, metrics: .menu)
        if height <= 640 {
            cheatSheet(sheet)
        } else {
            ScrollView {
                cheatSheet(sheet)
            }
            .frame(height: 640)
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
            background: false,
            onNavigate: { target in
                previewMode = (target == state.mode) ? nil : target
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        SearchField(text: $query, placeholder: "Search shortcuts")
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
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
