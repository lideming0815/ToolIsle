// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

struct GITagSpec: Identifiable {
    let id: String
    let title: String
    var color: String? = nil
    var selected = false
    var state = false
}
enum GITagPalette {
    static func state(_ value: String) -> String? {
        ["open":"238636", "unfinished":"237A57", "progressing":"2479C9", "closed":"8957BE", "rejected":"B75A26"][value]
    }
    static func color(_ hex: String?, dark: Bool, text: Bool = false) -> Color {
        let rgb = UInt32(hex ?? "7B8490", radix: 16) ?? 0x7B8490
        let values = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
        let adjusted = values.map { text ? (dark ? 0.64 + $0 * 0.36 : $0 * 0.55) : $0 }
        return Color(.sRGB, red: adjusted[0], green: adjusted[1], blue: adjusted[2], opacity: 1)
    }
}

private struct GITrayWidth: PreferenceKey {
    static let defaultValue: CGFloat = 220
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Only visible chips are constructed: hidden labels have no accidental hit targets or AX elements.
/// The size calculation reserves the same font/padding/checkmark used by GITagFace.
struct GIChipTray<Overflow: View>: View {
    let tags: [GITagSpec]
    var maxRows = 1
    var selectable = true
    var menuOverflow = false
    var compactOverflow = false
    var select: (String) -> Void = { _ in }
    @ViewBuilder var overflow: () -> Overflow
    @State private var width: CGFloat = 220
    @State private var showMore = false
    static var height: CGFloat { 24 }
    private func chipWidth(_ tag: GITagSpec) -> Double {
        let text = (tag.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        return min(Double(width), min(158, ceil(text) + (selectable ? 29 : (tag.state ? 27 : 16))))
    }
    private var overflowWidth: Double {
        if menuOverflow { return 28 }
        let title = compactOverflow ? "+\(tags.count)" : "… +\(tags.count)"
        return min(Double(width), Double((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width) + 16)
    }
    var body: some View {
        let widths = tags.map(chipWidth)
        let plan = GIChipPacking.pack(widths: widths, available: Double(width), maxRows: maxRows, overflow: overflowWidth)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(plan.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { index in
                        if index == -1 {
                            if menuOverflow {
                                Menu { overflow() } label: { Image(systemName: "ellipsis").frame(width: 20, height: Self.height) }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                                    .frame(width: overflowWidth, height: Self.height)
                                    .help("更多状态，当前选中：\(tags.first(where: { $0.selected })?.title ?? "")")
                                    .accessibilityIdentifier("gitee-status-overflow")
                            } else {
                                Button { showMore.toggle() } label: {
                                    Text(compactOverflow ? "+\(plan.hidden)" : "… +\(plan.hidden)")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: overflowWidth, height: Self.height)
                                        .background(.quaternary.opacity(0.5), in: Capsule())
                                }.buttonStyle(.plain).help("查看其余 \(plan.hidden) 个标签")
                                    .popover(isPresented: $showMore, arrowEdge: .bottom) { overflow() }
                            }
                        } else {
                            let tag = tags[index]
                            if selectable {
                                Button { select(tag.id) } label: {
                                    GITagFace(tag: tag, selectable: true).frame(width: widths[index], height: Self.height)
                                }.buttonStyle(.plain).help(tag.title)
                                    .accessibilityLabel(tag.title).accessibilityValue(tag.selected ? "已选中" : "未选中")
                                    .accessibilityIdentifier("gitee-filter-\(tag.id)")
                            } else {
                                GITagFace(tag: tag, selectable: false).frame(width: widths[index], height: Self.height)
                                    .help(tag.title)
                            }
                        }
                    }
                }.frame(height: Self.height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in Color.clear.preference(key: GITrayWidth.self, value: proxy.size.width) })
        .onPreferenceChange(GITrayWidth.self) { value in
            if value.isFinite && value > 0 && abs(value - width) > 0.5 { width = value }
        }
        .onAppear { GILabelProbe.record(tags, width: width, rows: plan.rows, maximum: maxRows) }
        .onChange(of: width) { _, _ in GILabelProbe.record(tags, width: width, rows: plan.rows, maximum: maxRows) }
        .onChange(of: tags.map(\.id)) { _, _ in GILabelProbe.record(tags, width: width, rows: plan.rows, maximum: maxRows) }
    }
}

struct GITagFace: View {
    let tag: GITagSpec
    var selectable = false
    @Environment(\.colorScheme) private var appearance
    var body: some View {
        let dark = appearance == .dark
        let tint = GITagPalette.color(tag.color, dark: dark)
        HStack(spacing: 3) {
            if selectable {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 10).opacity(tag.selected ? 1 : 0)
            } else if tag.state {
                Circle().fill(tint).frame(width: 5, height: 5)
            }
            Text(tag.title).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(GITagPalette.color(tag.color, dark: dark, text: true))
        .background(tint.opacity(tag.selected ? (dark ? 0.26 : 0.18) : (dark ? 0.16 : 0.09)), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(tag.selected ? 0.80 : 0.20), lineWidth: tag.selected ? 1.2 : 0.5))
    }
}

struct GIStatusFilters: View {
    @ObservedObject private var store = GIStore.shared
    private var states: [String] {
        GIListPresentation.states + Set(store.items.map { $0.issue.state }).subtracting(GIListPresentation.states).sorted()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("状态").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if !GIListPresentation.states.prefix(3).contains(store.stateFilter) {
                    Text("当前：\(GIListPresentation.stateTitle(store.stateFilter))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            GIChipTray(tags: states.map { GITagSpec(id: $0, title: GIListPresentation.stateTitle($0), color: GITagPalette.state($0), selected: store.stateFilter == $0) },
                       maxRows: 1, menuOverflow: true, select: { store.stateFilter = $0 }) {
                ForEach(states, id: \.self) { state in
                    Button { store.stateFilter = state } label: {
                        HStack { Text(GIListPresentation.stateTitle(state)); if state == store.stateFilter { Image(systemName: "checkmark") } }
                    }
                }
            }
        }.accessibilityIdentifier("gitee-status-one-line")
    }
}

struct GILabelFilters: View {
    @ObservedObject private var store = GIStore.shared
    @State private var showSelection = false
    var body: some View {
        let facets = store.labelFacets
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("标签 · 匹配任意一个").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 3)
                if !store.selectedLabels.isEmpty {
                    Button("已选 \(store.selectedLabels.count) 项") { showSelection = true }
                        .font(.caption2).buttonStyle(.plain)
                        .popover(isPresented: $showSelection) { GILabelPicker() }
                }
            }
            if facets.isEmpty {
                Text("当前候选范围没有可选标签").font(.caption2).foregroundStyle(.secondary)
            } else {
                GIChipTray(tags: facets.map { GITagSpec(id: $0.name, title: "\($0.name) \($0.count)", color: $0.color, selected: store.selectedLabels.contains($0.name)) },
                           maxRows: 2, select: { store.toggleLabel($0) }) { GILabelPicker() }
            }
            if store.candidateItems.contains(where: { $0.issue.labels == nil }) {
                Text("部分记录未提供标签；仅筛选已知标签").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("gitee-labels-two-lines")
    }
}

struct GILabelPicker: View {
    @ObservedObject private var store = GIStore.shared
    @State private var query = ""
    @FocusState private var focused: Bool
    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) }
    var body: some View {
        let facets = store.labelFacets
        let missing = store.selectedLabels.subtracting(Set(facets.map(\.name))).sorted()
        VStack(alignment: .leading, spacing: 10) {
            Text("筛选标签").font(.headline)
            TextField("搜索当前范围的标签", text: $query).textFieldStyle(.roundedBorder).focused($focused)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(missing.filter(matches), id: \.self) { name in
                        choice(name, detail: "当前范围无匹配 · 点击取消", color: nil)
                    }
                    ForEach(facets.filter { matches($0.name) }) { facet in
                        choice(facet.name, detail: "\(facet.count) 条 · \(facet.repositories.count) 个项目", color: facet.color)
                    }
                    if !facets.contains(where: { matches($0.name) }) && !missing.contains(where: matches) {
                        Text("没有匹配的标签").foregroundStyle(.secondary).padding(12)
                    }
                }
            }.frame(height: min(280, CGFloat(max(1, facets.count + missing.count)) * 45))
            Divider()
            HStack {
                Text("已选 \(store.selectedLabels.count) 项 · 匹配任意一个").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清除标签") { store.selectedLabels = [] }.disabled(store.selectedLabels.isEmpty)
            }
        }.padding(14).frame(width: 310).onAppear { focused = true }
        .accessibilityIdentifier("gitee-label-picker")
    }
    private func choice(_ name: String, detail: String, color: String?) -> some View {
        Button { store.toggleLabel(name) } label: {
            HStack(spacing: 8) {
                Image(systemName: store.selectedLabels.contains(name) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(store.selectedLabels.contains(name) ? Color.accentColor : .secondary)
                Circle().fill(GITagPalette.color(color, dark: false)).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout).lineLimit(2)
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).help(name).accessibilityValue(store.selectedLabels.contains(name) ? "已选中" : "未选中")
    }
}

struct GIIssueTags: View {
    let issue: GIIssue
    var body: some View {
        let labels = issue.visibleLabels
        let tags = [GITagSpec(id: "state", title: issue.stateTitle, color: GITagPalette.state(issue.state), state: true)] +
            labels.map { GITagSpec(id: "label:" + $0.key, title: $0.key, color: $0.hexColor) }
        GIChipTray(tags: tags, maxRows: 1, selectable: false, compactOverflow: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("此 Issue 的标签").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                            HStack { Circle().fill(GITagPalette.color(label.hexColor, dark: false)).frame(width: 7, height: 7)
                                Text(label.key).textSelection(.enabled).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0) }
                        }
                    }
                }.frame(maxHeight: 240)
            }.padding(14).frame(width: 260)
        }
    }
}
