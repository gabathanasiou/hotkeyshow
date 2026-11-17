import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--dump") {
            Diagnostics.dump()
            return
        }

        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let path = arguments[index + 1]
            Task { @MainActor in
                Diagnostics.snapshot(to: path)
            }
            RunLoop.main.run()
            return
        }

        HotkeyShowApp.main()
    }
}

struct HotkeyShowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    init() {
        AppState.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: state.isServiceMode ? "keyboard" : "rectangle.split.2x1")
            Text(state.workspace)
                .monospacedDigit()
        }
    }
}

// MARK: - Command line diagnostics

enum Diagnostics {
    static func dump() {
        do {
            let sheets = try AeroSpaceClient.shared.loadSheets()
            for sheet in sheets {
                let base = sheet.baseModifiers.isEmpty
                    ? "(none)"
                    : sheet.baseModifiers.sorted { $0.sortOrder < $1.sortOrder }.map(\.symbol).joined()
                print("mode \(sheet.id)   base: \(base)   bindings: \(sheet.allRows.count)")
                for group in sheet.allGroups {
                    print("  \(group.category.title.uppercased())")
                    for row in group.rows {
                        let chord = (row.chord.contains(sheet.baseModifiers)
                            ? row.chord.stripped(of: sheet.baseModifiers)
                            : row.chord).display
                        let padded = chord.padding(toLength: 20, withPad: " ", startingAt: 0)
                        let exit = row.summary.isExit ? "   [exit]" : ""
                        print("    \(padded)\(row.summary.label)\(exit)")
                    }
                }
                if let basics = sheet.basicsLine {
                    print("  basics: \(basics)")
                }
                print("")
            }
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }

    @MainActor
    static func snapshot(to directoryPath: String) {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let sheets = try AeroSpaceClient.shared.loadSheets()
            for sheet in sheets {
                for includeBasics in [false, true] {
                    let card = SnapshotCard(sheet: sheet, includeBasics: includeBasics)
                    let renderer = ImageRenderer(content: card)
                    renderer.scale = 2
                    guard let image = renderer.nsImage,
                          let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        print("render failed: \(sheet.id) basics=\(includeBasics)")
                        continue
                    }
                    let name = "\(sheet.id)-\(includeBasics ? "full" : "peek").png"
                    try png.write(to: directory.appendingPathComponent(name))
                    print("wrote \(name) \(Int(image.size.width))x\(Int(image.size.height))")
                }
            }
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }
}

private struct SnapshotCard: View {
    let sheet: ModeSheet
    let includeBasics: Bool

    var body: some View {
        let isMain = sheet.id == "main"

        if includeBasics {
            // Menu presentation: no card, light appearance like a system popover.
            CheatSheetView(
                sheet: sheet,
                title: "\(sheet.id.capitalized) mode",
                subtitle: "\(sheet.allRows.count) bindings · live from AeroSpace",
                includeBasics: true,
                metrics: .menu,
                background: false,
                onNavigate: { _ in }
            )
            .padding(20)
            .background(Color(white: 0.97))
            .environment(\.colorScheme, .light)
        } else {
            CheatSheetView(
                sheet: sheet,
                title: isMain ? holdTitle : "\(sheet.id.capitalized) mode",
                subtitle: isMain ? "release to dismiss" : (sheet.returnHint ?? "modifier held"),
                includeBasics: false,
                metrics: isMain ? .peek : .service
            )
            .padding(34)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.32), Color(white: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .environment(\.colorScheme, .dark)
        }
    }

    private var holdTitle: String {
        guard !sheet.baseModifiers.isEmpty else { return "Shortcuts" }
        return "Hold " + sheet.baseModifiers.sorted { $0.sortOrder < $1.sortOrder }.map(\.symbol).joined()
    }
}
