// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

extension Notification.Name {
    static let giteeFocusFilters = Notification.Name("ToolIsle.Gitee.FocusFilters")
}

/// Ordinary text copying keeps Cmd-C; only the dedicated share action uses Shift-Cmd-C.
struct GICopyIssueButton: View {
    let url: URL
    @State private var copied = false
    @State private var failed = false
    @State private var reset: Task<Void, Never>?
    var body: some View {
        Button {
            reset?.cancel()
            copied = GIPasteboard.copy(url.absoluteString)
            failed = !copied
            reset = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                copied = false; failed = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : (failed ? "exclamationmark.circle" : "link"))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(copied ? "已复制链接" : (failed ? "复制失败，请重试" : "复制 Issue 链接"))
        .accessibilityLabel("复制 Issue 链接")
        .accessibilityValue(copied ? "已复制" : (failed ? "复制失败" : ""))
        .accessibilityIdentifier("gitee-copy-issue-link")
        .onChange(of: url) { _, _ in reset?.cancel(); copied = false; failed = false }
        .onDisappear { reset?.cancel() }
    }
}

struct GIIssueRow: View {
    let item: GIListItem
    let selected: Bool
    @State private var hover = false
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 7) {
                Text(item.issue.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                HStack(spacing: 5) {
                    Text(item.route.repository).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(item.issue.stateTitle)
                }.font(.caption2).foregroundStyle(.secondary)
                Text("#\(item.issue.number) · \(String((item.issue.updated_at ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "))")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            GICopyIssueButton(url: item.route.url).opacity(hover || selected ? 1 : 0.45)
        }
        .padding(.vertical, 6).contentShape(Rectangle()).onHover { hover = $0 }
    }
}

struct GIFilterBar: View {
    @ObservedObject private var store = GIStore.shared
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Issues").font(.headline)
                Spacer()
                Button { store.refreshIssues(reset: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(store.loadingList || store.demoMode)
                    .help("刷新已选项目，不改变筛选条件")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索标题或编号", text: $store.query).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityLabel("搜索已加载的标题或编号")
                Button { store.query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).opacity(store.query.isEmpty ? 0 : 1)
                    .disabled(store.query.isEmpty).help("清空搜索")
            }.padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { project.frame(width: 170); state.frame(width: 150) }
                VStack(spacing: 8) { project; state }
            }
            HStack {
                Text("匹配 \(store.filteredItems.count) / 已加载 \(store.items.count)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if store.hasActiveFilters {
                    Button("清除筛选") { store.clearFilters() }.buttonStyle(.borderless).font(.caption)
                        .help("全部已选项目、全部状态，并清空搜索；不修改查看项目")
                }
            }
        }.padding(12)
        .accessibilityIdentifier("gitee-filter-bar")
        .onReceive(NotificationCenter.default.publisher(for: .giteeFocusFilters)) { _ in searchFocused = true }
    }
    private var project: some View {
        HStack {
            Text("项目").font(.caption).foregroundStyle(.secondary)
            Picker("项目", selection: $store.repositoryFilter) {
                Text("全部已选项目").tag("")
                ForEach(store.selectedRepositories) { Text($0.full_name).tag($0.path) }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
                .help(store.repositoryFilter.isEmpty ? "仅筛选本机已选项目，不改变 Watch / Star" : store.repositoryFilter)
        }
    }
    private var state: some View {
        HStack {
            Text("状态").font(.caption).foregroundStyle(.secondary)
            Picker("状态", selection: $store.stateFilter) {
                Text("未完成").tag("unfinished"); Text("全部状态").tag("all")
                Text("开启").tag("open"); Text("进行中").tag("progressing")
                Text("已关闭").tag("closed"); Text("已拒绝").tag("rejected")
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
                .help("仅筛选已加载的结果；未完成包含开启与进行中")
        }
    }
}
