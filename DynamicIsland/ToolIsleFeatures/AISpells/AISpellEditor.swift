// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Editing a combination is deliberately separate from using it: the quick panel
/// receives the saved body, with no parameter form or source lookup on insertion.
@MainActor
struct AISpellEditor: View {
    let spell: AISpell
    @ObservedObject var store: AISpellStore
    let onCancel: () -> Void
    let onSave: (AISpell) -> Void

    @State private var title: String
    @State private var content: String
    @State private var category: String
    @State private var kind: AISpellKind
    @State private var components: [AISpellComponent]
    @State private var componentQuery = ""
    @FocusState private var titleFocused: Bool

    init(spell: AISpell, store: AISpellStore, onCancel: @escaping () -> Void, onSave: @escaping (AISpell) -> Void) {
        self.spell = spell
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: spell.title)
        _content = State(initialValue: spell.content)
        _category = State(initialValue: spell.category)
        _kind = State(initialValue: spell.kind)
        _components = State(initialValue: spell.components)
    }

    private var preview: String { AISpellComponent.combinedContent(of: components) }
    private var canSave: Bool {
        !store.isReadOnly && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !(kind == .combination ? preview : content).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var availableSources: [AISpell] {
        let selected = Set(components.map(\.sourceID))
        return store.results(query: componentQuery).filter {
            $0.kind != .combination && $0.id != spell.id && !selected.contains($0.id)
        }
    }
    private var duplicate: AISpell? {
        guard kind != .combination,
              let existing = store.matchingContent(content), existing.id != spell.id else { return nil }
        return existing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label((store.spells.contains { $0.id == spell.id } ? "编辑" : "新建") + kind.title,
                      systemImage: kind.systemImage)
                    .font(.title3.weight(.semibold))
                Spacer()
                if kind != .combination {
                    Picker("用途", selection: $kind) {
                        Text(AISpellKind.prompt.title).tag(AISpellKind.prompt)
                        Text(AISpellKind.context.title).tag(AISpellKind.context)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .accessibilityIdentifier("ai-spells-editor-kind")
                }
            }
            TextField(kind == .context ? "标题，例如：热线分析项目背景" : "标题，例如：检查最大的遗漏", text: $title)
                .textFieldStyle(.roundedBorder).focused($titleFocused)
                .accessibilityLabel("咒语标题")
                .accessibilityIdentifier("ai-spells-editor-title")
            categoryField
            if kind == .combination {
                combinationEditor
            } else {
                bodyEditor
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(3)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ai-spells-editor-cancel")
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .accessibilityIdentifier("ai-spells-save")
            }
        }
        .padding(22)
        .frame(width: kind == .combination ? 760 : 560, height: kind == .combination ? 620 : 510)
        .onAppear { titleFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private var categoryField: some View {
        HStack {
            TextField("分类（选填）", text: $category).textFieldStyle(.roundedBorder)
                .accessibilityLabel("咒语分类")
            if !store.categories.isEmpty {
                Menu("已有分类") {
                    ForEach(store.categories, id: \.self) { value in
                        Button(value.isEmpty ? "未分类" : value) { category = value }
                    }
                }.fixedSize()
            }
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .context ? "项目背景、技术栈、约束与输出要求" : "正文")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $content)
                .font(.body)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                .accessibilityLabel("咒语正文")
                .accessibilityIdentifier("ai-spells-editor-content")
            Text(kind == .context ? "背景卡可单独插入，也可作为预设组合的片段。" : "保留原文和换行；复制、插入时只使用这里的正文。")
                .font(.caption).foregroundStyle(.secondary)
            if let duplicate {
                Text("已有相同正文：“\(duplicate.title)”")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var combinationEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                sourcePicker.frame(width: 240)
                Divider()
                componentList.frame(maxWidth: .infinity)
            }
            .frame(height: 220)
            Divider()
            HStack {
                Text("插入正文预览").font(.caption.weight(.medium))
                Spacer()
                Text("\(preview.count) 字符").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(preview.isEmpty ? "从左侧添加背景卡和咒语，在右侧调整顺序。" : preview)
                    .font(.body).lineSpacing(3)
                    .foregroundStyle(preview.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("ai-spells-combination-preview")
            Text("保存后，点击组合即可插入。源条目修改或删除不会自动改变组合；需要时主动刷新片段并保存。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添加片段").font(.caption.weight(.medium))
            TextField("查找背景卡或咒语", text: $componentQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ai-spells-component-search")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if availableSources.isEmpty {
                        Text("没有可添加的片段；可先保存背景卡或咒语。")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                    }
                    ForEach(availableSources) { source in
                        Button {
                            components.append(AISpellComponent(spell: source))
                        } label: {
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: source.kind.systemImage).foregroundStyle(Color.accentColor)
                                Text(source.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                            }
                            .font(.caption).padding(8)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添加片段：" + source.title)
                        .accessibilityIdentifier("ai-spells-add-component-\(source.id.uuidString)")
                    }
                }
            }
        }
    }

    private var componentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("组合顺序 · \(components.count) 个片段").font(.caption.weight(.medium))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if components.isEmpty {
                        Text("点击左侧片段加入组合。")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    ForEach(components) { component in
                        componentRow(component)
                    }
                }
            }
            .accessibilityIdentifier("ai-spells-component-list")
        }
    }

    private func componentRow(_ component: AISpellComponent) -> some View {
        let index = components.firstIndex { $0.sourceID == component.sourceID } ?? 0
        let source = store.spells.first { $0.id == component.sourceID && $0.kind != .combination }
        let hasUpdate = source.map { $0.title != component.title || $0.content != component.content } ?? false
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("\(index + 1). \(component.title)").font(.caption.weight(.medium))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button { move(component.sourceID, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0).help("上移")
                    .accessibilityLabel("上移：" + component.title)
                    .accessibilityIdentifier("ai-spells-component-up-\(component.sourceID.uuidString)")
                Button { move(component.sourceID, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index >= components.count - 1).help("下移")
                    .accessibilityLabel("下移：" + component.title)
                    .accessibilityIdentifier("ai-spells-component-down-\(component.sourceID.uuidString)")
                Button { components.removeAll { $0.sourceID == component.sourceID } } label: {
                    Image(systemName: "minus.circle")
                }
                .help("移除片段").accessibilityLabel("移除片段：" + component.title)
            }
            Text(component.content).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if hasUpdate, let source {
                Button("源条目已更新 · 刷新此片段") {
                    if let position = components.firstIndex(where: { $0.sourceID == source.id }) {
                        components[position] = AISpellComponent(spell: source)
                    }
                }
                .font(.caption2)
                .accessibilityIdentifier("ai-spells-refresh-component-\(component.sourceID.uuidString)")
            } else if source == nil {
                Text("源条目不可用，保留已保存的正文。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = components.firstIndex(where: { $0.sourceID == id }),
              components.indices.contains(index + offset) else { return }
        components.swapAt(index, index + offset)
    }

    private func save() {
        guard canSave else { return }
        var draft = spell
        draft.title = title
        draft.category = category
        draft.kind = kind
        draft.components = kind == .combination ? components : []
        draft.content = kind == .combination ? preview : content
        onSave(draft)
    }
}
