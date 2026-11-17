import XCTest
@testable import HotkeyShow

final class KeyChordTests: XCTestCase {
    func testParsesModifiersAndKey() throws {
        let chord = try XCTUnwrap(KeyChord(configValue: "alt-shift-semicolon"))
        XCTAssertEqual(chord.modifiers, [.alt, .shift])
        XCTAssertEqual(chord.key, "semicolon")
        XCTAssertEqual(chord.keyGlyph, ";")
        XCTAssertEqual(chord.display, "⌥⇧;")
    }

    func testModifierOrderIsMacStandard() throws {
        let chord = try XCTUnwrap(KeyChord(configValue: "shift-alt-cmd-ctrl-h"))
        XCTAssertEqual(chord.display, "⌃⌥⇧⌘H")
    }

    func testGlyphs() {
        XCTAssertEqual(KeyChord(configValue: "alt-esc")?.display, "⌥⎋")
        XCTAssertEqual(KeyChord(configValue: "alt-tab")?.display, "⌥⇥")
        XCTAssertEqual(KeyChord(configValue: "alt-shift-leftSquareBracket")?.display, "⌥⇧[")
        XCTAssertEqual(KeyChord(configValue: "alt-f5")?.display, "⌥F5")
        XCTAssertEqual(KeyChord(configValue: "alt-minus")?.display, "⌥−")
    }

    func testStripOnlyRemovesPresentModifiers() throws {
        let chord = try XCTUnwrap(KeyChord(configValue: "alt-shift-h"))
        XCTAssertEqual(chord.stripped(of: [.alt]).display, "⇧H")

        // Stripping a prefix the chord does not have must not change it.
        let shiftOnly = try XCTUnwrap(KeyChord(configValue: "shift-h"))
        XCTAssertEqual(shiftOnly.stripped(of: [.alt, .shift]).display, "⇧H")
    }

    func testRejectsUnknownModifier() {
        XCTAssertNil(KeyChord(configValue: "hyper-h"))
    }
}

final class CommandFormatterTests: XCTestCase {
    func testFocus() {
        let summary = CommandFormatter.summarize("focus left")
        XCTAssertEqual(summary.label, "Focus left")
        XCTAssertEqual(summary.category, .focus)
        XCTAssertFalse(summary.isExit)
    }

    func testResize() {
        XCTAssertEqual(CommandFormatter.summarize("resize smart -50").label, "Shrink")
        XCTAssertEqual(CommandFormatter.summarize("resize smart +50").label, "Grow")
    }

    func testLayouts() {
        XCTAssertEqual(CommandFormatter.summarize("layout tiles horizontal vertical").label, "Tiling")
        XCTAssertEqual(CommandFormatter.summarize("layout accordion horizontal vertical").label, "Accordion")
        XCTAssertEqual(CommandFormatter.summarize("layout floating tiling").label, "Toggle floating")
    }

    func testMultiCommandExit() {
        let summary = CommandFormatter.summarize("reload-config; mode main")
        XCTAssertEqual(summary.label, "Reload config")
        XCTAssertTrue(summary.isExit)
        XCTAssertEqual(summary.category, .system)
    }

    func testJoinWith() {
        let summary = CommandFormatter.summarize("join-with left")
        XCTAssertEqual(summary.label, "Join with ←")
        XCTAssertEqual(summary.category, .join)
        XCTAssertFalse(summary.isExit)
    }

    func testWorkspaceBackAndForthIsNavigationNotBasic() {
        XCTAssertEqual(CommandFormatter.summarize("workspace-back-and-forth").category, .navigation)
    }

    func testUnknownCommandFallsBackToRawWords() {
        let summary = CommandFormatter.summarize("do-something cool")
        XCTAssertEqual(summary.label, "Do something cool")
        XCTAssertEqual(summary.category, .other)
    }
}

final class ModeSheetTests: XCTestCase {
    func testServiceSheetHasNoBaseModifierAndEscAsExit() {
        let sheet = SheetBuilder.build(mode: "service", bindings: [
            "esc": "reload-config; mode main",
            "r": "flatten-workspace-tree; mode main",
            "backspace": "close-all-windows-but-current; mode main",
            "alt-shift-h": "join-with left; mode main",
        ])
        XCTAssertTrue(sheet.baseModifiers.isEmpty)
        XCTAssertEqual(sheet.primaryExit?.display, "⎋")
        XCTAssertEqual(sheet.allRows.count, 4)
    }

    func testMainBaseModifierIsAlt() {
        let sheet = SheetBuilder.build(mode: "main", bindings: [
            "alt-h": "focus left",
            "alt-j": "focus down",
            "alt-shift-h": "move left",
            "alt-1": "workspace 1",
        ])
        XCTAssertEqual(sheet.baseModifiers, [.alt])
        let basics = try? XCTUnwrap(sheet.basicsLine)
        XCTAssertTrue(basics?.contains("Focus: H J") == true)
    }

    func testBasicsLineIncludesCompressedWorkspaceRun() {
        var bindings: [String: String] = [:]
        for number in 1...9 {
            bindings["alt-shift-\(number)"] = "move-node-to-workspace \(number)"
        }
        let sheet = SheetBuilder.build(mode: "main", bindings: bindings)
        XCTAssertEqual(sheet.baseModifiers, [.alt, .shift])
        XCTAssertEqual(sheet.basicsLine, "Send to workspace: 1–9")
    }

    func testCompression() {
        XCTAssertEqual(ModeSheet.compressed(["H", "J", "K", "L"]), "H J K L")
        XCTAssertEqual(ModeSheet.compressed(["1", "2", "3"]), "1–3")
        XCTAssertEqual(ModeSheet.compressed(["1", "2", "4"]), "1 2 4")
        XCTAssertEqual(ModeSheet.compressed(["⇧1", "⇧2", "⇧3"]), "⇧1–3")
        XCTAssertEqual(ModeSheet.compressed(["⇧F", "⇧⇥"]), "⇧F ⇧⇥")
    }

    func testPeekHidesOnlyBasics() {
        let sheet = SheetBuilder.build(mode: "main", bindings: [
            "alt-h": "focus left",
            "alt-shift-f": "fullscreen",
            "alt-shift-semicolon": "mode service",
        ])
        let basicsHidden = sheet.visibleGroups(includingBasics: false).flatMap(\.rows).map(\.id)
        XCTAssertEqual(Set(basicsHidden), ["alt-shift-f", "alt-shift-semicolon"])
    }
}

final class ConfigFileTests: XCTestCase {
    func testAutoReloadDetection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("aerospace.toml")

        try "auto-reload-config = true\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(AeroSpaceConfigFile.autoReloadEnabled(at: url))

        try "# auto-reload-config = true\nauto-reload-config = false\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(AeroSpaceConfigFile.autoReloadEnabled(at: url))

        try "config-version = 2\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(AeroSpaceConfigFile.autoReloadEnabled(at: url))
    }
}
