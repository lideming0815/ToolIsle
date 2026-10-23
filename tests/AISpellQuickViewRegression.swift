// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Exercises the production SwiftUI view and its AppKit search editor in this process.
/// No system accessibility permission, clipboard write, or external-app paste is simulated.
@main
@MainActor
struct AISpellQuickViewRegression {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private final class Recorder {
        var pasted: [AISpell] = []
        var copied: [AISpell] = []
        var manageCount = 0
        var closeCount = 0
        var permissionCount = 0
    }

    private final class TestPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static var assertions = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        guard condition() else { throw Failure(description: message) }
    }

    static func main() {
        do {
            try run()
            print("PASS: \(assertions) native AI spell quick-view interaction assertions; external-app paste not tested")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolIsle-QuickViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AISpellStore(fileURL: directory.appendingPathComponent("library.json"))
        try expect(!store.isReadOnly, "The isolated fixture library must load")
        for spell in store.spells {
            try expect(store.delete(id: spell.id), "Remove only the isolated fixture samples")
        }
        let first = AISpell(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "发现最大的遗漏", content: "关于当前情况，最大的遗漏是什么？\n眼下你最没有把握的事情是什么？",
            category: "思考复盘", isFavorite: true
        )
        let second = AISpell(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "减少编程中的未知因素", content: "The best agentic coders have relatively few unknowns.",
            category: "编程"
        )
        let third = AISpell(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "补充身份与背景", content: "赋予它背景，说明你是谁以及你在做什么。", category: "上下文"
        )
        for spell in [first, second, third] {
            try expect(store.save(spell), "Create an isolated native-view fixture")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        let recorder = Recorder()
        let state = AISpellQuickState()
        state.targetName = "测试输入框"
        let view = AISpellQuickView(
            store: store, state: state,
            onPaste: { recorder.pasted.append($0) },
            onCopy: { recorder.copied.append($0) },
            onManage: { recorder.manageCount += 1 },
            onClose: { recorder.closeCount += 1 },
            onOpenPermissions: { recorder.permissionCount += 1 }
        )
        let hosting = NSHostingView(rootView: view)
        let panel = TestPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: 440, height: 500))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { panel.orderOut(nil) }
        pumpEvents(for: 0.8)
        hosting.layoutSubtreeIfNeeded()

        if let option = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(option + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[option + 1])
            try writeSnapshot(of: hosting, to: url)
            print("Native quick-view snapshot: \(url.path)")
        }

        try expect(hosting.bounds.width == 440 && hosting.bounds.height == 500,
                   "The quick view must fit the 440 by 500 panel")
        let firstRow = try accessibleElement("ai-spell-quick-row-\(first.id.uuidString)", in: hosting)
        try expect(firstRow.accessibilityRole() == .button, "Each quick row must be an actionable button")
        try expect(firstRow.accessibilityPerformPress(), "A single row press must be accepted")
        pumpEvents(for: 0.1)
        try expect(recorder.pasted.map(\.id) == [first.id], "One row press requests insertion exactly once")
        try expect(recorder.pasted.first?.content == first.content, "Insertion receives the complete original body")
        try expect(recorder.copied.isEmpty, "A row press must not invoke copy-only")

        guard let search = findSearchField(in: hosting) else {
            throw Failure(description: "The production quick-search NSSearchField was not found")
        }
        try expect(panel.makeFirstResponder(search), "Search can become first responder")
        pumpEvents(for: 0.1)
        guard let editor = search.currentEditor() as? NSTextView else {
            throw Failure(description: "Search has no live NSTextView field editor")
        }
        editor.insertText("unknowns", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        pumpEvents(for: 0.2)
        try expect(findAccessibleElement("ai-spell-quick-row-\(second.id.uuidString)", in: hosting) != nil,
                   "Typing in the actual search editor finds full English body text")
        try expect(findAccessibleElement("ai-spell-quick-row-\(first.id.uuidString)", in: hosting) == nil,
                   "Search removes nonmatching rows from the native accessibility tree")

        postKey(.keyDown, code: 36, characters: "\r", modifiers: [], window: panel)
        postKey(.keyUp, code: 36, characters: "\r", modifiers: [], window: panel)
        pumpEvents(for: 0.2)
        try expect(recorder.pasted.map(\.id) == [first.id, second.id],
                   "Return in search requests insertion of the filtered row exactly once")

        postKey(.keyDown, code: 36, characters: "\r", modifiers: .command, window: panel)
        postKey(.keyUp, code: 36, characters: "\r", modifiers: .command, window: panel)
        pumpEvents(for: 0.2)
        try expect(recorder.copied.map(\.id) == [second.id], "Command-Return requests copy-only exactly once")
        try expect(recorder.pasted.count == 2, "Command-Return must not request insertion")

        // A real field editor owns marked text, but no system input method is impersonated.
        // Call its production delegate to verify the guard before a Return command is handled.
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try expect(editor.hasMarkedText(), "The field editor must have an active composition")
        let handledCompositionReturn = search.delegate?.control?(
            search, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false
        try expect(!handledCompositionReturn, "Return during marked text must stay with the input method")
        let commandReturn = keyEvent(.keyDown, code: 36, characters: "\r", modifiers: .command, window: panel)
        _ = search.performKeyEquivalent(with: commandReturn)
        try expect(recorder.pasted.count == 2 && recorder.copied.count == 1,
                   "Neither Return handler may use a spell while the field editor has marked text")
        editor.unmarkText()

        editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        pumpEvents(for: 0.2)
        state.isBusy = true
        pumpEvents(for: 0.1)
        let busyRow = try accessibleElement("ai-spell-quick-row-\(first.id.uuidString)", in: hosting)
        _ = busyRow.accessibilityPerformPress()
        pumpEvents(for: 0.1)
        try expect(recorder.pasted.count == 2, "A pending insertion prevents a second row action")
        state.isBusy = false
        pumpEvents(for: 0.1)

        let manage = try accessibleElement("ai-spell-quick-manage", in: hosting)
        try expect(manage.accessibilityPerformPress(), "The manage button is actionable")
        pumpEvents(for: 0.1)
        try expect(recorder.manageCount == 1, "Manage opens the management flow once")
        try expect(recorder.pasted.count == 2, "Opening management does not insert a spell")

    }

    private static func findSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField, field.accessibilityIdentifier() == "ai-spell-quick-search" {
            return field
        }
        for child in view.subviews {
            if let found = findSearchField(in: child) { return found }
        }
        return nil
    }

    private static func accessibleElement(_ id: String, in root: NSView) throws -> NSAccessibilityProtocol {
        guard let element = findAccessibleElement(id, in: root) else {
            throw Failure(description: "Native accessibility element not found: \(id)")
        }
        return element
    }

    private static func findAccessibleElement(_ id: String, in root: NSView) -> NSAccessibilityProtocol? {
        var visited = Set<ObjectIdentifier>()
        func visit(_ value: Any) -> NSAccessibilityProtocol? {
            let object = value as AnyObject
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            if let element = value as? NSAccessibilityProtocol {
                if element.accessibilityIdentifier() == id { return element }
                for child in element.accessibilityChildren() ?? [] {
                    if let found = visit(child) { return found }
                }
            }
            if let view = value as? NSView {
                for child in view.subviews {
                    if let found = visit(child) { return found }
                }
            }
            return nil
        }
        return visit(root)
    }

    private static func keyEvent(_ type: NSEvent.EventType, code: UInt16, characters: String,
                                 modifiers: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    private static func postKey(_ type: NSEvent.EventType, code: UInt16, characters: String,
                                modifiers: NSEvent.ModifierFlags, window: NSWindow) {
        NSApp.postEvent(keyEvent(type, code: code, characters: characters, modifiers: modifiers, window: window),
                        atStart: false)
    }

    /// Drive AppKit's own event queue, so currentEvent contains the dispatched modifier flags.
    private static func pumpEvents(for duration: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: duration)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
    }

    private static func writeSnapshot(of view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(description: "AppKit could not allocate the native view snapshot")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(description: "AppKit could not encode the native view snapshot")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
