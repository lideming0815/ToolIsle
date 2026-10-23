// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Exercises the production SwiftUI buttons and AppKit search editor through this
/// process's actual event queue. No system accessibility permission, clipboard
/// write, or external-app paste is simulated.
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
            print("PASS: \(assertions) native AI spell quick-view and management interaction assertions; external-app paste not tested")
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
        clickFirstPrompt(in: hosting, window: panel)
        pumpEvents(for: 0.1)
        try expect(recorder.pasted.map(\.id) == [first.id], "One native mouse click requests insertion exactly once")
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
        try expect(search.stringValue == "unknowns", "Typing updates the actual native search field")
        try expect(recorder.pasted.count == 1 && recorder.copied.isEmpty,
                   "Typing a query does not use a spell")

        postKey(.keyDown, code: 36, characters: "\r", modifiers: [], window: panel)
        postKey(.keyUp, code: 36, characters: "\r", modifiers: [], window: panel)
        pumpEvents(for: 0.2)
        try expect(recorder.pasted.map(\.id) == [first.id, second.id],
                   "Return finds full English body text and inserts only the matching row exactly once")

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
        clickFirstPrompt(in: hosting, window: panel)
        pumpEvents(for: 0.1)
        try expect(recorder.pasted.count == 2, "A pending insertion prevents a second row action")
        state.isBusy = false
        pumpEvents(for: 0.1)

        // The 440 x 500 fixture's header places Manage at (397, 22) from
        // the top left. Dispatch a real one-click mouse pair to that button.
        let managePoint = NSPoint(x: hosting.bounds.minX + 397,
                                  y: hosting.isFlipped ? hosting.bounds.minY + 22 : hosting.bounds.maxY - 22)
        click(at: hosting.convert(managePoint, to: nil), window: panel)
        pumpEvents(for: 0.1)
        try expect(recorder.manageCount == 1, "Manage opens the management flow once")
        try expect(recorder.pasted.count == 2, "Opening management does not insert a spell")

        panel.orderOut(nil)
        let combination = try runManagement(store: store, prompt: first, duplicate: second)
        panel.makeKeyAndOrderFront(nil)
        pumpEvents(for: 0.2)
        try enterQuery(combination.title, in: search, window: panel)
        let previousPastes = recorder.pasted.count
        clickFirstPrompt(in: hosting, window: panel)
        pumpEvents(for: 0.2)
        try expect(recorder.pasted.count == previousPastes + 1 && recorder.pasted.last?.id == combination.id,
                   "One click on a saved combination requests insertion exactly once")
        try expect(recorder.pasted.last?.content == combination.content,
                   "Clicking a combination passes its complete ordered body to insertion")
        try expect(panel.makeFirstResponder(search), "Combination search can regain focus")
        pumpEvents(for: 0.1)
        postKey(.keyDown, code: 36, characters: "\r", modifiers: [], window: panel)
        postKey(.keyUp, code: 36, characters: "\r", modifiers: [], window: panel)
        pumpEvents(for: 0.2)
        try expect(recorder.pasted.count == previousPastes + 2 && recorder.pasted.last?.id == combination.id,
                   "Return on a saved combination requests insertion exactly once")
        try expect(recorder.pasted.last?.content == combination.content && recorder.copied.count == 1,
                   "Combination Return inserts the full body without also requesting copy-only")
    }

    private static func runManagement(store: AISpellStore, prompt: AISpell, duplicate: AISpell) throws -> AISpell {
        let state = AISpellManagerState()
        let recorder = Recorder()
        let hosting = NSHostingView(rootView: AISpellsView(
            store: store, state: state,
            onCopy: { recorder.copied.append($0) }, onPaste: { recorder.pasted.append($0) },
            onClose: { recorder.closeCount += 1 }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "AI 咒语 · 管理"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        pumpEvents(for: 0.6)
        try snapshotIfRequested(hosting, name: "ai-spells-manager.png")

        let originalData = try Data(contentsOf: store.fileURL)
        let originalCount = store.spells.count
        let captured = "  收藏：检查遗漏🙂\n保留第二行与空格。  \n"
        try expect(state.requestCapture(captured), "A nonempty clipboard snapshot is accepted")
        pumpEvents(for: 0.6)
        let captureSheet = try editorSheet(of: window)
        let captureBody = try bodyEditor(in: captureSheet)
        try expect(captureBody.string.utf8.elementsEqual(captured.utf8),
                   "Capture prefills the production editor with the exact multiline Unicode body")
        try expect(nativeTextValues(in: captureSheet.contentView!).contains(AISpellLibrary.suggestedTitle(for: captured)),
                   "Capture prefills a useful title from the first nonempty line")
        try expect(store.spells.count == originalCount, "Opening capture does not save a spell")
        try expect(tryRead(store.fileURL) == originalData, "Opening capture leaves the library bytes unchanged")
        clickEditorFooter(in: captureSheet, save: false)
        pumpEvents(for: 0.6)
        try expect(window.attachedSheet == nil && store.spells.count == originalCount,
                   "Cancel closes capture without adding a spell")
        try expect(tryRead(store.fileURL) == originalData, "Cancel leaves the original library bytes unchanged")

        try expect(state.requestCapture(duplicate.content), "An exact duplicate can be routed to its existing entry")
        // The real capture controller activates the app and presents its manager
        // on every request. A bare state request after closing a sheet leaves the
        // headless fixture with no key window, so AppKit cannot dispatch Return.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pumpEvents(for: 0.3)
        try expect(NSApp.keyWindow === window,
                   "The capture presenter makes the management window key before keyboard interaction")
        try expect(window.attachedSheet == nil && store.spells.count == originalCount,
                   "An exact duplicate reveals the existing spell without opening a new draft")
        try expect(tryRead(store.fileURL) == originalData, "Duplicate capture does not rewrite the library")
        guard let search = findSearchField(in: hosting, identifier: "ai-spells-search") else {
            throw Failure(description: "The production management search field was not found")
        }
        try expect(window.makeFirstResponder(search), "Management search can become first responder")
        pumpEvents(for: 0.1)
        let duplicateFocusBefore = focusDescription(search: search, window: window)
        try snapshotIfRequested(hosting, name: "ai-spells-duplicate-before.png")
        postKey(.keyDown, code: 36, characters: "\r", modifiers: [], window: window)
        postKey(.keyUp, code: 36, characters: "\r", modifiers: [], window: window)
        pumpEvents(for: 0.2)
        try snapshotIfRequested(hosting, name: "ai-spells-duplicate.png")
        let duplicateDiagnostics = "expected=\(duplicate.id.uuidString); " +
            "copied(\(recorder.copied.count))=\(recorder.copied.map { $0.id.uuidString }); " +
            "pasted(\(recorder.pasted.count))=\(recorder.pasted.map { $0.id.uuidString }); " +
            "before={\(duplicateFocusBefore)}; after={\(focusDescription(search: search, window: window))}"
        print("Duplicate capture Enter: \(duplicateDiagnostics)")
        try expect(recorder.copied.map(\.id) == [duplicate.id],
                   "Duplicate capture selects the existing entry, verified through its public copy action. " + duplicateDiagnostics)

        let initialDraft = "正在编辑的草稿\n这段内容尚未保存。"
        let editedDraft = "用户已经修改的草稿🙂\n新捕获不能覆盖这里。"
        let queuedCapture = "排队收藏的提示词\n请先列出当前问题中的未知条件。\n"
        try expect(state.requestCapture(initialDraft), "Start a new capture draft")
        pumpEvents(for: 0.6)
        let currentSheet = try editorSheet(of: window)
        let currentBody = try bodyEditor(in: currentSheet)
        NSApp.activate(ignoringOtherApps: true)
        currentSheet.makeKeyAndOrderFront(nil)
        pumpEvents(for: 0.1)
        try expect(NSApp.keyWindow === currentSheet, "The active draft sheet owns keyboard focus before editing")
        try expect(currentSheet.makeFirstResponder(currentBody), "The real draft body can receive editing")
        currentBody.insertText(editedDraft, replacementRange: NSRange(location: 0, length: currentBody.string.utf16.count))
        pumpEvents(for: 0.2)
        try expect(state.requestCapture(queuedCapture), "One additional capture can wait behind an open editor")
        pumpEvents(for: 0.2)
        try expect(window.attachedSheet === currentSheet && currentBody.string == editedDraft,
                   "A new capture never replaces the already-open, user-edited draft")
        try expect(state.captureRequest?.content == queuedCapture,
                   "The second capture retains its own text while waiting")
        try expect(!state.requestCapture("不能挤掉前一个待收藏内容"), "A full pending slot rejects another capture")
        try expect(state.captureRequest?.content == queuedCapture && currentBody.string == editedDraft,
                   "Rejecting a third request preserves both the editor and the pending snapshot")
        try expect(tryRead(store.fileURL) == originalData, "Editing and queueing have not saved either draft")
        clickEditorFooter(in: currentSheet, save: false)
        pumpEvents(for: 0.8)
        let queuedSheet = try editorSheet(of: window)
        let queuedBody = try bodyEditor(in: queuedSheet)
        try expect(queuedBody.string == queuedCapture,
                   "Closing the current editor presents the waiting capture intact")
        try expect(store.spells.count == originalCount && tryRead(store.fileURL) == originalData,
                   "Presenting the waiting capture still requires explicit Save")
        clickEditorFooter(in: queuedSheet, save: true)
        pumpEvents(for: 0.6)
        try expect(window.attachedSheet == nil && store.spells.count == originalCount + 1,
                   "One native Save click adds the captured spell exactly once and dismisses the editor")
        try expect(store.matchingContent(queuedCapture)?.title == AISpellLibrary.suggestedTitle(for: queuedCapture),
                   "Confirmed capture saves the displayed title and complete body")
        try expect(store.matchingContent(captured) == nil && store.matchingContent(editedDraft) == nil,
                   "Previously cancelled capture bodies were never saved")
        try expect(recorder.pasted.isEmpty && recorder.copied.count == 1,
                   "Opening, editing, cancelling, and saving capture never insert or copy a prompt")

        window.orderOut(nil)
        let combination = try runCombinationEditor(store: store, prompt: prompt)
        window.makeKeyAndOrderFront(nil)
        // Use the same duplicate-reveal route to display the newly saved combination.
        _ = state.requestCapture(combination.content)
        pumpEvents(for: 0.3)
        try snapshotIfRequested(hosting, name: "ai-spells-manager.png")
        return combination
    }

    private static func runCombinationEditor(store: AISpellStore, prompt: AISpell) throws -> AISpell {
        let context = AISpell(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "热线分析项目背景", content: "项目：陕西热线分析。\n技术栈：Java 8、StarRocks。",
            category: "项目背景", kind: .context
        )
        try expect(store.save(context), "Create an isolated project context card")
        let draft = AISpell(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            title: "热线分析 · 完整提问", content: "", category: "预设组合", kind: .combination,
            components: [AISpellComponent(spell: context), AISpellComponent(spell: prompt)]
        )
        var saved: [AISpell] = []
        var saveSucceeded = false
        // Host the production editor directly with two chosen components. Keeping
        // it visible after Save lets both direction buttons exercise real state.
        let hosting = NSHostingView(rootView: AISpellEditor(spell: draft, store: store, onCancel: {}) { value in
            saved.append(value)
            saveSucceeded = store.save(value)
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "AI 咒语 · 预设组合"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        pumpEvents(for: 0.5)
        try snapshotIfRequested(hosting, name: "ai-spells-combination.png")
        try expect(!store.spells.contains { $0.id == draft.id }, "Opening a combination editor does not persist its draft")

        // The editor has a fixed 760 x 620 layout: its component list begins at
        // x = 291, y = 140. Arrow buttons are at the right edge of each row.
        // Saved component order/body, not the coordinates, are the oracle.
        clickFromTop(x: 705, y: 154, in: hosting, window: window) // context down
        pumpEvents(for: 0.2)
        clickEditorFooter(in: window, save: true)
        pumpEvents(for: 0.2)
        try expect(saveSucceeded && saved.count == 1, "One real Save click saves the combination once")
        try expect(saved.last?.components.map(\.sourceID) == [prompt.id, context.id],
                   "The down arrow changes the saved component order")
        try expect(saved.last?.content == prompt.content + "\n\n" + context.content,
                   "Combination Save passes the complete reordered bodies, separated by two newlines")

        clickFromTop(x: 686, y: 219, in: hosting, window: window) // context up from second row
        pumpEvents(for: 0.2)
        clickEditorFooter(in: window, save: true)
        pumpEvents(for: 0.2)
        try expect(saveSucceeded && saved.count == 2, "A second explicit Save produces one additional save callback")
        guard let combination = store.spells.first(where: { $0.id == draft.id }) else {
            throw Failure(description: "The combination was not persisted through the production Save action")
        }
        try expect(combination.components.map(\.sourceID) == [context.id, prompt.id],
                   "The up arrow puts the project context before the prompt")
        try expect(combination.content == context.content + "\n\n" + prompt.content,
                   "The persisted combination contains exactly the displayed ordered body")
        try snapshotIfRequested(hosting, name: "ai-spells-combination.png")
        return combination
    }

    private static func findSearchField(in view: NSView, identifier: String = "ai-spell-quick-search") -> NSSearchField? {
        if let field = view as? NSSearchField, field.accessibilityIdentifier() == identifier {
            return field
        }
        for child in view.subviews {
            if let found = findSearchField(in: child, identifier: identifier) { return found }
        }
        return nil
    }

    private static func enterQuery(_ query: String, in search: NSSearchField, window: NSWindow) throws {
        try expect(window.makeFirstResponder(search), "The native search field can receive a query")
        pumpEvents(for: 0.1)
        guard let editor = search.currentEditor() as? NSTextView else {
            throw Failure(description: "Search has no native field editor for typing")
        }
        editor.insertText(query, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        pumpEvents(for: 0.2)
    }

    private static func focusDescription(search: NSSearchField, window: NSWindow) -> String {
        let editor = search.currentEditor() as? NSTextView
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let keyResponder = NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        return "window=\(window.title)#\(window.windowNumber), " +
            "keyWindow=\(NSApp.keyWindow?.title ?? "nil")#\(NSApp.keyWindow?.windowNumber ?? -1), " +
            "firstResponder=\(responder), keyFirstResponder=\(keyResponder), " +
            "searchEditor=\(editor.map { String(describing: type(of: $0)) } ?? "nil"), " +
            "editorIsFirstResponder=\(editor != nil && window.firstResponder === editor), " +
            "markedText=\(editor?.hasMarkedText() ?? false), " +
            "query=\(String(reflecting: search.stringValue)), " +
            "attachedSheet=\(window.attachedSheet != nil)"
    }

    private static func editorSheet(of window: NSWindow) throws -> NSWindow {
        guard let sheet = window.attachedSheet, sheet.contentView != nil else {
            throw Failure(description: "The manager did not present the production spell editor sheet")
        }
        return sheet
    }

    private static func bodyEditor(in window: NSWindow) throws -> NSTextView {
        func find(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, !text.isFieldEditor, text.isEditable { return text }
            for child in view.subviews {
                if let found = find(in: child) { return found }
            }
            return nil
        }
        guard let root = window.contentView, let editor = find(in: root) else {
            throw Failure(description: "The spell editor's real NSTextView body was not found")
        }
        return editor
    }

    private static func nativeTextValues(in view: NSView) -> [String] {
        var values: [String] = []
        if let text = view as? NSTextView { values.append(text.string) }
        if let field = view as? NSTextField { values.append(field.stringValue) }
        for child in view.subviews { values.append(contentsOf: nativeTextValues(in: child)) }
        return values
    }

    private static func tryRead(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    private static func clickEditorFooter(in window: NSWindow, save: Bool) {
        guard let root = window.contentView else { return }
        // Both editor sizes use the same 22-point padding and trailing footer.
        // These clicks go through NSApp; no SwiftUI callback is invoked by a test.
        clickFromTop(x: root.bounds.width - (save ? 47 : 111), y: root.bounds.height - 33,
                     in: root, window: window)
    }

    private static func clickFromTop(x: CGFloat, y: CGFloat, in root: NSView, window: NSWindow) {
        let point = NSPoint(x: root.bounds.minX + x,
                            y: root.isFlipped ? root.bounds.minY + y : root.bounds.maxY - y)
        click(at: root.convert(point, to: nil), window: window)
    }

    private static func snapshotIfRequested(_ view: NSView, name: String) throws {
        guard let option = CommandLine.arguments.firstIndex(of: "--snapshot"),
              CommandLine.arguments.indices.contains(option + 1) else { return }
        let url = URL(fileURLWithPath: CommandLine.arguments[option + 1])
            .deletingLastPathComponent().appendingPathComponent(name)
        try writeSnapshot(of: view, to: url)
        print("Native interaction snapshot: \(url.path)")
    }

    private static func clickFirstPrompt(in root: NSView, window: NSWindow) {
        // The native screenshot of this fixed 440 x 500 fixture places the
        // first row at y = 127...203 from the top. Its center is (220, 165).
        // The actual callback identity/count, not the coordinate, is the oracle.
        let point = NSPoint(x: root.bounds.minX + 220,
                            y: root.isFlipped ? root.bounds.minY + 165 : root.bounds.maxY - 165)
        click(at: root.convert(point, to: nil), window: window)
    }

    private static func click(at point: NSPoint, window: NSWindow) {
        // Queue both events before pumping: AppKit button tracking may consume
        // the mouse-up synchronously. These events stay within this test app.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            )!
            NSApp.postEvent(event, atStart: false)
        }
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
