// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct AISpellCaptureRequest: Identifiable {
    let id = UUID()
    let content: String
}

/// Keeps one explicit capture waiting while an existing editor or file panel is open.
/// It owns no clipboard access and does not save until the user confirms the editor.
@MainActor
final class AISpellManagerState: ObservableObject {
    @Published var captureRequest: AISpellCaptureRequest?
    @Published var message: String?

    @discardableResult
    func requestCapture(_ content: String) -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "剪切板中没有可以收藏的文字。"
            return false
        }
        guard captureRequest == nil else {
            message = "已有一段文字等待收藏，请先完成当前编辑。"
            return false
        }
        captureRequest = AISpellCaptureRequest(content: content)
        message = nil
        return true
    }
}

/// The same library is used for quick retrieval and editing. Only prompt content
/// crosses the copy/paste callbacks; titles and categories stay in the library.
@MainActor
struct AISpellsView: View {
    @ObservedObject var store: AISpellStore
    @ObservedObject var state: AISpellManagerState
    let onCopy: (AISpell) -> Void
    let onPaste: (AISpell) -> Void
    let onClose: () -> Void
    var onCapture: (() -> Void)? = nil

    @State private var query = ""
    @State private var category: String?
    @State private var favoritesOnly = false
    @State private var kind: AISpellKind?
    @State private var selection: UUID?
    @State private var editingSpell: AISpell?
    @State private var deletingSpell: AISpell?
    @State private var statusMessage: String?
    @State private var focusRequest = UUID()
    @State private var isShowingFilePanel = false
    @State private var capturedDraftID: UUID?

    private var matches: [AISpell] {
        store.results(query: query, category: category, favoritesOnly: favoritesOnly)
            .filter { kind == nil || $0.kind == kind }
    }
    private var visibleIDs: [UUID] { matches.map(\.id) }
    private var selectedSpell: AISpell? { matches.first { $0.id == selection } }
    private var categories: [String] {
        (store.spells.contains { $0.category.isEmpty } ? [""] : []) + store.categories
    }
    private var acceptsQuickActions: Bool {
        editingSpell == nil && deletingSpell == nil && !isShowingFilePanel
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            searchAndFilters
            if let error = store.errorMessage { errorBanner(error) }
            HStack(spacing: 0) {
                spellList.frame(minWidth: 210, idealWidth: 260, maxWidth: 290)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { reconcileSelection(); consumeCaptureRequest() }
        .onChange(of: state.captureRequest?.id) { _, _ in consumeCaptureRequest() }
        .onChange(of: isShowingFilePanel) { _, showing in
            if !showing { consumeCaptureRequest() }
        }
        .onChange(of: deletingSpell?.id) { _, id in
            if id == nil {
                DispatchQueue.main.async { consumeCaptureRequest() }
            }
        }
        .onChange(of: visibleIDs) { _, _ in reconcileSelection() }
        .onChange(of: categories) { _, categories in
            if let category, !categories.contains(category) { self.category = nil }
        }
        .onChange(of: editingSpell?.id) { _, id in
            if id == nil { focusRequest = UUID() }
        }
        .sheet(item: $editingSpell, onDismiss: consumeCaptureRequest) { spell in
            AISpellEditor(spell: spell, store: store) { editingSpell = nil } onSave: { draft in
                if capturedDraftID == draft.id,
                   let existing = store.matchingContent(draft.content), existing.id != draft.id {
                    reveal(existing)
                    statusMessage = "已存在相同正文：“\(existing.title)”，没有重复保存。"
                    editingSpell = nil
                    capturedDraftID = nil
                    return
                }
                if store.save(draft) {
                    reveal(draft)
                    editingSpell = nil
                    capturedDraftID = nil
                    statusMessage = "已保存"
                }
            }
        }
        .confirmationDialog("删除这条咒语？", isPresented: Binding(
            get: { deletingSpell != nil },
            set: { if !$0 { deletingSpell = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let spell = deletingSpell, store.delete(id: spell.id) {
                    statusMessage = "已删除"
                }
                deletingSpell = nil
            }
            Button("取消", role: .cancel) { deletingSpell = nil }
        } message: {
            Text("“\(deletingSpell?.title ?? "")”将从本机咒语库中移除。已保存组合中的正文仍会保留。删除前可先导出备份。")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars").font(.title3).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 咒语").font(.headline)
                Text("咒语、项目背景与预设组合").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { edit(AISpell(title: "", content: "")) } label: {
                Label("新建", systemImage: "plus")
            }
            .disabled(store.isReadOnly || editingSpell != nil)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityIdentifier("ai-spells-new")
            Button {
                edit(AISpell(title: "", content: "", kind: .context))
            } label: {
                Label("背景卡", systemImage: AISpellKind.context.systemImage)
            }
            .disabled(store.isReadOnly || editingSpell != nil)
            .accessibilityIdentifier("ai-spells-new-context")
            Button {
                edit(AISpell(title: "", content: "", kind: .combination))
            } label: {
                Label("组合", systemImage: AISpellKind.combination.systemImage)
            }
            .disabled(store.isReadOnly || editingSpell != nil)
            .accessibilityIdentifier("ai-spells-new-combination")
            if let onCapture {
                Button(action: onCapture) { Image(systemName: "doc.badge.plus") }
                    .disabled(store.isReadOnly)
                    .help("收藏当前剪切板中的文字")
                    .accessibilityLabel("收藏剪切板")
                    .accessibilityIdentifier("ai-spells-capture")
            }
            Menu {
                Button("导入备份…", action: importLibrary).disabled(store.isReadOnly)
                Button("导出备份…", action: exportLibrary).disabled(store.isReadOnly)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("导入或导出咒语备份")
            .accessibilityLabel("咒语备份")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchAndFilters: some View {
        VStack(spacing: 9) {
            AISpellSearchField(
                text: $query, focusRequest: focusRequest, isActive: acceptsQuickActions,
                accessibilityIdentifier: "ai-spells-search",
                onMove: moveSelection, onSubmit: copySelection,
                onCommandSubmit: pasteSelection, onClose: onClose
            )
            .frame(height: 28)
            HStack(spacing: 12) {
                Picker("类型", selection: $kind) {
                    Text("全部类型").tag(nil as AISpellKind?)
                    ForEach(AISpellKind.allCases) { value in
                        Text(value.title).tag(Optional(value))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
                .accessibilityLabel("按类型筛选")
                Picker("分类", selection: $category) {
                    Text("全部分类").tag(nil as String?)
                    ForEach(categories, id: \.self) { category in
                        Text(category.isEmpty ? "未分类" : category).tag(Optional(category))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 210)
                .accessibilityLabel("按分类筛选")
                Toggle("仅收藏", isOn: $favoritesOnly).toggleStyle(.checkbox)
                Spacer()
                Text("\(matches.count) 条").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var spellList: some View {
        if matches.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass").font(.title2).foregroundStyle(.secondary)
                Text(store.isReadOnly ? "咒语库暂不可用" : (store.spells.isEmpty ? "还没有咒语" : "没有匹配的咒语"))
                    .font(.headline)
                Text(store.isReadOnly ? "请查看上方提示并重新读取，原文件仍保留。" :
                     (store.spells.isEmpty ? "点击“新建”保存第一条常用提示词。" : "试试其他关键词、分类或取消收藏筛选。"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(matches) { spell in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(spell.title).font(.body.weight(.medium)).lineLimit(2)
                                Text(spell.content.replacingOccurrences(of: "\n", with: " "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Label(spell.kind.title + (spell.category.isEmpty ? "" : " · " + spell.category),
                                      systemImage: spell.kind.systemImage)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if spell.isFavorite {
                                Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange)
                                    .accessibilityLabel("已收藏")
                            }
                        }
                        .padding(.vertical, 5)
                        .tag(spell.id)
                        .id(spell.id)
                        .contextMenu {
                            Button("复制咒语") { onCopy(spell) }
                            Button("插入原应用") { onPaste(spell) }
                            Divider()
                            Button("编辑…") { edit(spell) }.disabled(store.isReadOnly)
                            Button(spell.isFavorite ? "取消收藏" : "收藏") {
                                _ = store.toggleFavorite(id: spell.id)
                            }.disabled(store.isReadOnly)
                            Button("删除…", role: .destructive) { deletingSpell = spell }
                                .disabled(store.isReadOnly)
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("ai-spells-list")
                .onChange(of: selection) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard acceptsQuickActions, selectedSpell != nil else { return .ignored }
                    if press.modifiers == .command { pasteSelection(); return .handled }
                    if press.modifiers.isEmpty { copySelection(); return .handled }
                    return .ignored
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let spell = selectedSpell {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(spell.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Label(spell.kind.title + (spell.category.isEmpty ? "" : " · " + spell.category),
                              systemImage: spell.kind.systemImage)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        _ = store.toggleFavorite(id: spell.id)
                    } label: {
                        Image(systemName: spell.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(spell.isFavorite ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isReadOnly)
                    .help(spell.isFavorite ? "取消收藏" : "收藏")
                    .accessibilityLabel(spell.isFavorite ? "取消收藏" : "收藏")
                    Button { edit(spell) } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.borderless).disabled(store.isReadOnly).help("编辑咒语")
                        .accessibilityLabel("编辑咒语")
                    Button { deletingSpell = spell } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).disabled(store.isReadOnly).help("删除咒语")
                        .accessibilityLabel("删除咒语")
                }
                Divider()
                if spell.kind == .combination {
                    Text("由 \(spell.components.count) 个片段组成 · 按保存时的正文插入")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(spell.content)
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }
                .accessibilityIdentifier("ai-spells-content")
                Text("\(spell.content.count) 字符 · \(spell.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(18)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "wand.and.stars").font(.system(size: 32)).foregroundStyle(.tertiary)
                Text("选中一条咒语查看全文").foregroundStyle(.secondary)
                Text("仅复制正文，保留原有文字和换行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("↑↓ 选择 · ↩ 复制 · ⌘↩ 插入").font(.caption).foregroundStyle(.secondary)
                if let message = state.message ?? statusMessage {
                    Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button("复制", action: copySelection).disabled(selectedSpell == nil)
                .help("复制正文并收起面板")
                .accessibilityIdentifier("ai-spells-copy")
            Button("插入原应用", action: pasteSelection).disabled(selectedSpell == nil)
                .buttonStyle(.borderedProminent)
                .help("返回呼出面板前的应用并粘贴，不自动发送")
                .accessibilityIdentifier("ai-spells-paste")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if store.isReadOnly {
                Button("重新读取") { store.reload() }
            } else {
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("关闭提示")
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
    }

    private func reconcileSelection() {
        if !visibleIDs.contains(where: { $0 == selection }) { selection = visibleIDs.first }
    }

    private func moveSelection(_ offset: Int) {
        let ids = visibleIDs
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
        selection = ids[min(max(current + offset, 0), ids.count - 1)]
    }

    private func copySelection() {
        if let spell = selectedSpell { onCopy(spell) }
    }

    private func pasteSelection() {
        if let spell = selectedSpell { onPaste(spell) }
    }

    private func edit(_ spell: AISpell) {
        guard !store.isReadOnly else { return }
        store.errorMessage = nil
        capturedDraftID = nil
        editingSpell = spell
    }

    private func reveal(_ spell: AISpell) {
        query = ""
        category = nil
        kind = nil
        favoritesOnly = false
        selection = spell.id
    }

    private func consumeCaptureRequest() {
        guard acceptsQuickActions, let request = state.captureRequest else { return }
        state.captureRequest = nil
        guard !store.isReadOnly else {
            state.message = "咒语库暂不可写，请先处理读取错误。剪切板内容未改变。"
            return
        }
        state.message = nil
        if let existing = store.matchingContent(request.content) {
            reveal(existing)
            statusMessage = "已存在相同正文：“\(existing.title)”，没有重复保存。"
        } else {
            let draft = AISpell(title: AISpellLibrary.suggestedTitle(for: request.content), content: request.content)
            capturedDraftID = draft.id
            store.errorMessage = nil
            editingSpell = draft
        }
    }

    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "导入咒语备份"
        panel.message = "合并备份中的咒语，保留本机已有记录。"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        isShowingFilePanel = true
        present(panel) { response in
            defer { isShowingFilePanel = false; focusRequest = UUID() }
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                if let count = store.importData(data) {
                    statusMessage = "已导入 \(count) 条咒语，已有记录保持不变。"
                    query = ""; category = nil; kind = nil; favoritesOnly = false
                }
            } catch {
                store.errorMessage = "无法读取备份：\(error.localizedDescription)"
            }
        }
    }

    private func exportLibrary() {
        guard let data = store.exportData() else { return }
        let panel = NSSavePanel()
        panel.title = "导出咒语备份"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AI咒语备份.json"
        panel.canCreateDirectories = true
        isShowingFilePanel = true
        present(panel) { response in
            defer { isShowingFilePanel = false; focusRequest = UUID() }
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                statusMessage = "备份已导出"
            } catch {
                store.errorMessage = "无法导出备份：\(error.localizedDescription)"
            }
        }
    }

    private func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

/// Handle navigation only while the search editor has focus. In particular,
/// Return used to confirm a Chinese input candidate must not use a prompt.
/// The quick panel and manager choose their own Return / Command-Return actions.
@MainActor
struct AISpellSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID
    let isActive: Bool
    let accessibilityIdentifier: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCommandSubmit: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SpellSearchField {
        let field = SpellSearchField()
        field.placeholderString = "搜索标题、正文或分类"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.maximumRecents = 0
        field.delegate = context.coordinator
        field.setAccessibilityLabel("搜索咒语")
        field.setAccessibilityIdentifier(accessibilityIdentifier)
        return field
    }

    func updateNSView(_ field: SpellSearchField, context: Context) {
        context.coordinator.parent = self
        field.commandSubmitAction = isActive ? onCommandSubmit : nil
        if field.stringValue != text { field.stringValue = text }
        if isActive, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window, window.attachedSheet == nil else { return }
                window.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: AISpellSearchField
        var lastFocusRequest: UUID?
        init(_ parent: AISpellSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard parent.isActive, !textView.hasMarkedText(), control.window?.attachedSheet == nil else { return false }
            let modifiers = (NSApp.currentEvent?.modifierFlags ?? [])
                .intersection([.command, .control, .option, .shift])
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)) where modifiers.isEmpty:
                parent.onMove(1); return true
            case #selector(NSResponder.moveUp(_:)) where modifiers.isEmpty:
                parent.onMove(-1); return true
            case #selector(NSResponder.insertNewline(_:)):
                if modifiers == .command { parent.onCommandSubmit(); return true }
                if modifiers.isEmpty { parent.onSubmit(); return true }
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onClose(); return true
            default:
                return false
            }
        }
    }

    final class SpellSearchField: NSSearchField {
        var commandSubmitAction: (() -> Void)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if (event.keyCode == 36 || event.keyCode == 76), modifiers == .command,
               let editor = currentEditor() as? NSTextView,
               window?.firstResponder === editor, window?.attachedSheet == nil, !editor.hasMarkedText(),
               let commandSubmitAction {
                commandSubmitAction()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
