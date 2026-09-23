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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.issue.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
            GIIssueTags(issue: item.issue)
            if let timestamp = item.issue.updated_at {
                Text(String(timestamp.prefix(16)).replacingOccurrences(of: "T", with: " "))
                    .font(.system(size: 10)).foregroundStyle(.secondary).help(timestamp)
            }
        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

struct GIFilterBar: View {
    @ObservedObject private var store = GIStore.shared
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Issues").font(.headline)
                Spacer()
                if store.issueGroups.contains(where: { store.collapsedProjects.contains($0.id) }) {
                    Button { store.expandMatchingProjects() } label: { Image(systemName: "rectangle.expand.vertical") }
                        .help("展开匹配项目").buttonStyle(.borderless)
                }
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
            GIStatusFilters()
            GILabelFilters()
            HStack {
                Text("匹配 \(store.filteredItems.count) / 已加载 \(store.items.count)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if store.hasActiveFilters {
                    Button("清除筛选") { store.clearFilters() }.buttonStyle(.borderless).font(.caption)
                        .help("全部状态，清空搜索和标签；不修改查看项目、分组折叠或当前阅读")
                }
            }
        }.padding(12)
        .accessibilityIdentifier("gitee-filter-bar")
        .onReceive(NotificationCenter.default.publisher(for: .giteeFocusFilters)) { _ in searchFocused = true }
    }
}
