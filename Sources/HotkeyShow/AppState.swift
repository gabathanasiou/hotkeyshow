import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum DetectionStatus: Equatable {
        case unknown
        case testing
        case works
        case failed
    }

    struct SearchHit: Identifiable {
        let id: String
        let mode: String
        let row: BindingRow
    }

    // MARK: - Published state

    @Published var mode: String = "main"
    @Published var sheets: [String: ModeSheet] = [:]
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var highlight: String?
    @Published var detectionStatus: DetectionStatus = .unknown
    @Published var connected = false
    @Published var configDirty = false
    @Published var autoReload = false
    @Published var peekEnabled: Bool = UserDefaults.standard.object(forKey: "peekEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(peekEnabled, forKey: "peekEnabled") }
    }

    // MARK: - Collaborators

    private let client = AeroSpaceClient.shared
    private let events = EventStream()
    private let hud = HUDController()
    private let modifierWatcher = ModifierWatcher()
    private var configWatcher: ConfigFileWatcher?
    private var refreshTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    private var started = false

    private init() {}

    var currentSheet: ModeSheet? { sheets[mode] }
    var isServiceMode: Bool { mode != "main" }

    func shutdown() {
        Log.write("shutting down")
        modifierWatcher.stop()
        configWatcher?.stop()
        events.stop()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        Log.write("starting HotkeyShow (aerospace: \(client.binary?.path ?? "not found"))")

        if client.binary == nil {
            errorMessage = "AeroSpace CLI not found"
        }

        events.onEvent = { [weak self] event in self?.handle(event) }
        events.onStatusChange = { [weak self] isConnected in
            guard let self else { return }
            self.connected = isConnected
            if isConnected {
                self.refresh(reason: "connected")
            }
        }
        events.start()

        modifierWatcher.onBegin = { [weak self] in self?.showPeek() }
        modifierWatcher.onEnd = { [weak self] in self?.hidePeek() }
        modifierWatcher.start()

        refresh(reason: "launch")
        startConfigWatcher()
    }

    // MARK: - Loading

    func refresh(reason: String) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let result: Result<[ModeSheet], Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try AeroSpaceClient.shared.loadSheets())
                } catch {
                    return .failure(error)
                }
            }.value
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let sheets):
                var map: [String: ModeSheet] = [:]
                for sheet in sheets { map[sheet.id] = sheet }
                self.sheets = map
                self.loading = false
                self.errorMessage = nil
                self.configDirty = false
                let summary = sheets.map { "\($0.id):\($0.allRows.count)" }.joined(separator: " ")
                Log.write("loaded shortcuts [\(reason)] \(summary)")
                self.refreshVisiblePanel()
            case .failure(let error):
                self.loading = false
                self.errorMessage = error.localizedDescription
                Log.write("loading shortcuts failed: \(error.localizedDescription)")
            }
        }
    }

    private func refreshVisiblePanel() {
        if isServiceMode {
            showServicePanel()
        } else if hud.isVisible, hud.style == .peek {
            showPeek()
        }
    }

    // MARK: - AeroSpace events

    private func handle(_ event: EventStream.Event) {
        switch event.name {
        case "mode-changed":
            guard let newMode = event.mode else { return }
            if newMode != mode {
                mode = newMode
                Log.write("mode -> \(newMode)")
            }
            if newMode == "main" {
                hidePeek()
                hud.hide()
            } else {
                showServicePanel()
            }

        case "binding-triggered":
            guard let binding = event.binding else { return }
            flash(binding)
            if !isServiceMode {
                // The user committed to a binding: get out of the way.
                modifierWatcher.suppressUntilRelease()
                hidePeek()
            }

        default:
            break
        }
    }

    private func flash(_ binding: String) {
        highlight = binding
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.highlight = nil
        }
    }

    // MARK: - Panel presentation

    private func present(modeID: String, style: HUDStyle, includeBasics: Bool, metrics: SheetMetrics) {
        let content = AnyView(HUDContentView(
            state: self,
            modeID: modeID,
            includeBasics: includeBasics,
            metrics: metrics
        ))
        hud.show(style: style, content: content)
    }

    private func showPeek() {
        guard peekEnabled, !isServiceMode else { return }
        guard let sheet = sheets["main"] else {
            refresh(reason: "peek without data")
            return
        }
        guard !sheet.allRows.isEmpty else { return }
        present(modeID: "main", style: .peek, includeBasics: false, metrics: .peek)
    }

    private func hidePeek() {
        if hud.isVisible, hud.style == .peek {
            hud.hide()
        }
    }

    private func showServicePanel() {
        guard isServiceMode else { return }
        guard sheets[mode] != nil else {
            refresh(reason: "missing mode \(mode)")
            return
        }
        present(modeID: mode, style: .service, includeBasics: true, metrics: .service)
    }

    // MARK: - Config file

    private func startConfigWatcher() {
        Task { [weak self] in
            let path = await Task.detached { try? AeroSpaceClient.shared.configPath() }.value
            let url: URL
            if let path, !path.isEmpty {
                url = URL(fileURLWithPath: path)
            } else {
                url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".aerospace.toml")
            }
            let autoReloadValue = AeroSpaceConfigFile.autoReloadEnabled(at: url)
            self?.autoReload = autoReloadValue
            Log.write("config: \(url.path) auto-reload=\(autoReloadValue)")

            let watcher = ConfigFileWatcher(url: url)
            watcher.onChange = { [weak self] in
                guard let self else { return }
                self.autoReload = AeroSpaceConfigFile.autoReloadEnabled(at: url)
                if !self.autoReload { self.configDirty = true }
                // auto-reload-config reloads ~200 ms after a save; give it a beat.
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.refresh(reason: "config file changed")
                }
            }
            self?.configWatcher = watcher
        }
    }

    func reloadAeroSpaceConfig() {
        Task {
            do {
                try await Task.detached { try AeroSpaceClient.shared.reloadConfig() }.value
                configDirty = false
                Log.write("reload-config sent")
                try? await Task.sleep(nanoseconds: 300_000_000)
                refresh(reason: "reload-config")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Diagnostics

    func checkDetection() {
        detectionStatus = .testing
        Task {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if ModifierWatcher.isOptionDown() {
                    detectionStatus = .works
                    Log.write("option detection works")
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            detectionStatus = .failed
            Log.write("option detection failed")
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.url])
    }

    // MARK: - Login item

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Login item: \(error.localizedDescription)"
            Log.write("login item failed: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    // MARK: - Derived UI state

    var statusNote: String? {
        if let errorMessage { return errorMessage }
        if configDirty { return "config saved · not reloaded yet — run reload-config" }
        if detectionStatus == .failed { return "⌥ not detected — Input Monitoring may be needed" }
        if !connected { return "waiting for AeroSpace…" }
        return nil
    }

    var statusIsWarning: Bool {
        errorMessage != nil || configDirty || detectionStatus == .failed || !connected
    }

    func search(_ query: String) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let order = [mode] + sheets.keys.filter { $0 != mode }.sorted()
        var hits: [SearchHit] = []
        for modeID in order {
            guard let sheet = sheets[modeID] else { continue }
            for row in sheet.allRows {
                let haystack = "\(row.summary.label) \(row.chord.display) \(row.chord.configValue) \(row.summary.raw)".lowercased()
                if haystack.contains(needle) {
                    hits.append(SearchHit(id: "\(modeID)-\(row.id)", mode: modeID, row: row))
                }
            }
        }
        return hits
    }
}
