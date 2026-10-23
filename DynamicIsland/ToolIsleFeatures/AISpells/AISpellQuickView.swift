// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import SwiftUI

/// Presentation feedback is separate from the saved prompt library. The window
/// controller owns target capture, insertion, and permission handling.
@MainActor
final class AISpellQuickState: ObservableObject {
    @Published var targetName: String? = nil
    @Published var message: String? = nil
    @Published var isBusy = false
    @Published var offersPermissionSettings = false
}

/// A compact retrieval surface: one click or Return inserts the selected prompt.
/// Editing, deletion, and backup remain in the full manager.
@MainActor
struct AISpellQuickView: View {
    @ObservedObject var store: AISpellStore
    @ObservedObject var state: AISpellQuickState
    let onPaste: (AISpell) -> Void
    let onCopy: (AISpell) -> Void
    let onManage: () -> Void
    let onClose: () -> Void
    let onOpenPermissions: () -> Void

    @State private var query = ""
    @State private var filter = Filter.all
    @State private var selection: UUID?
    @State private var focusRequest = UUID()

    private enum Filter: Hashable {
        case all
        case favorites
        case category(String)
    }

    private var categories: [String] {
        (store.spells.contains { $0.category.isEmpty } ? [""] : []) + store.categories
    }

    private var matches: [AISpell] {
        switch filter {
        case .all: return store.results(query: query)
        case .favorites: return store.results(query: query, favoritesOnly: true)
        case .category(let category): return store.results(query: query, category: category)
        }
    }

    private var visibleIDs: [UUID] { matches.map(\.id) }
    private var selectedSpell: AISpell? { matches.first { $0.id == selection } }
    private var feedback: String? { state.message ?? store.errorMessage }

    var body: some View {
        VStack(spacing: 0) {
            header
            AISpellSearchField(
                text: $query, focusRequest: focusRequest, isActive: !state.isBusy,
                accessibilityIdentifier: "ai-spell-quick-search",
                onMove: moveSelection, onSubmit: pasteSelection,
                onCommandSubmit: copySelection, onClose: onClose
            )
            .frame(height: 28)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            filters
            Divider()
            if let feedback { feedbackView(feedback) }
            promptList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 360, idealWidth: 440, minHeight: 340, idealHeight: 500)
        .accessibilityIdentifier("ai-spell-quick-panel")
        .onAppear { reconcileSelection() }
        .onChange(of: visibleIDs) { _, _ in reconcileSelection() }
        .onChange(of: categories) { _, values in
            if case .category(let category) = filter, !values.contains(category) {
                filter = .all
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accentColor)
            Text("AI 咒语").font(.headline)
            Text("\(matches.count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action: onManage) {
                Label("管理", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .disabled(state.isBusy)
            .help("管理咒语、分类与备份")
            .accessibilityIdentifier("ai-spell-quick-manage")
        }
        .padding(.horizontal, 15)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterButton("全部", filter: .all)
                filterButton("收藏", filter: .favorites, icon: "star")
                ForEach(categories, id: \.self) { category in
                    filterButton(category.isEmpty ? "未分类" : category, filter: .category(category))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .accessibilityIdentifier("ai-spell-quick-filters")
    }

    private func filterButton(_ title: String, filter value: Filter, icon: String? = nil) -> some View {
        Button {
            filter = value
            focusRequest = UUID()
        } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.caption.weight(filter == value ? .semibold : .regular))
            .foregroundStyle(filter == value ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(filter == value ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(state.isBusy)
        .accessibilityLabel(title)
        .accessibilityValue(filter == value ? "已选择" : "未选择")
    }

    @ViewBuilder private var promptList: some View {
        if matches.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 28)).foregroundStyle(.tertiary)
                Text(store.isReadOnly ? "暂时无法读取咒语" : (store.spells.isEmpty ? "保存第一条常用提示词" : "没有匹配的咒语"))
                    .font(.callout.weight(.medium))
                Text(store.isReadOnly ? "请查看上方提示后重新读取。已有咒语文件保持不变。" :
                     (store.spells.isEmpty ? "在管理窗口中添加咒语，之后就能随时呼出使用。" : "试试其他关键词或分类。"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if store.isReadOnly {
                    Button("重新读取") { store.reload() }.disabled(state.isBusy)
                } else if store.spells.isEmpty {
                    Button("管理咒语…", action: onManage).disabled(state.isBusy)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { spell in
                            promptRow(spell).id(spell.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: selection) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            .accessibilityIdentifier("ai-spell-quick-list")
        }
    }

    private func promptRow(_ spell: AISpell) -> some View {
        Button {
            guard !state.isBusy else { return }
            selection = spell.id
            onPaste(spell)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(spell.title).font(.callout.weight(.semibold)).lineLimit(1)
                    if spell.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    if !spell.category.isEmpty {
                        Text(spell.category).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).frame(maxWidth: 100, alignment: .trailing)
                    }
                }
                Text(spell.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selection == spell.id ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selection == spell.id ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.10))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(state.isBusy)
        .onHover { hovered in
            if hovered, !state.isBusy { selection = spell.id }
        }
        .accessibilityIdentifier("ai-spell-quick-row-\(spell.id.uuidString)")
        .accessibilityLabel(spell.title + "，" + spell.content)
        .accessibilityHint("插入到原应用")
        .contextMenu {
            Button("仅复制") { onCopy(spell) }.disabled(state.isBusy)
            Button("管理咒语…", action: onManage).disabled(state.isBusy)
        }
    }

    private func feedbackView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: state.offersPermissionSettings ? "lock.shield" : "info.circle")
                    .foregroundStyle(.secondary)
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.offersPermissionSettings {
                Button("打开辅助功能设置", action: onOpenPermissions)
                    .controlSize(.small)
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("ai-spell-quick-permissions")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06))
        .accessibilityIdentifier("ai-spell-quick-feedback")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if state.isBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                }
                Text(state.targetName.map { "插入到 \($0)" } ?? "从目标输入框呼出即可插入")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text("单击即插入").font(.caption2).foregroundStyle(.tertiary)
            }
            Text("↑↓ 选择    ↩ 插入    ⌘↩ 仅复制    Esc 收起")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }

    private func reconcileSelection() {
        if !visibleIDs.contains(where: { $0 == selection }) { selection = visibleIDs.first }
    }

    private func moveSelection(_ offset: Int) {
        guard !state.isBusy else { return }
        let ids = visibleIDs
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
        selection = ids[min(max(current + offset, 0), ids.count - 1)]
    }

    private func pasteSelection() {
        guard !state.isBusy, let spell = selectedSpell else { return }
        onPaste(spell)
    }

    private func copySelection() {
        guard !state.isBusy, let spell = selectedSpell else { return }
        onCopy(spell)
    }
}
