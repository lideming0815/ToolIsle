// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI

/// A normal settings sidebar destination. No account UI is embedded in General.
struct GIDedicatedSettingsView: View {
    @ObservedObject private var store = GIStore.shared
    @Default(.enableGiteeReader) private var enabled
    @Default(.giteeNotchMaximumItems) private var notchMaximumItems
    @State private var server = "https://gitlab.com"
    @State private var serverError: String?
    @State private var pendingHTTPRemote: GIReaderRemote?
    @State private var confirmHTTP = false
    @State private var source = "subscriptions"
    @State private var filter = ""
    @State private var changeToken = false
    @State private var confirmDisconnect = false
    private var filteredRepositories: [GIRepository] {
        store.repositories.filter { filter.isEmpty || $0.full_name.localizedCaseInsensitiveContains(filter) || $0.path.localizedCaseInsensitiveContains(filter) }
    }
    private var selectedIDs: Set<Int64> { Set(store.settingsSelectedRepositories.map(\.id)) }

    var body: some View {
        Form {
            Section("Git 连接") {
                ForEach(store.connections) { connection in
                    HStack(alignment: .top) {
                        Toggle(isOn: Binding(get: { store.isEnabled(connection.remote) }, set: { store.setEnabled(connection.remote, $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(connection.remote.name + " · " + connection.remote.webURL.absoluteString)
                                Text(store.connectionStatus(connection.remote)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button(store.remote == connection.remote ? "正在配置" : "配置") { store.useRemote(connection.remote) }
                            .disabled(store.remote == connection.remote)
                    }
                }
                HStack {
                    Button("配置 Gitee") { store.useRemote(.gitee) }
                    Button("配置 GitHub") { store.useRemote(.github) }
                }
                TextField("GitLab 站点地址", text: $server).textFieldStyle(.roundedBorder)
                    .onSubmit { applyServer(gitlab: true) }.accessibilityIdentifier("gitlab-server-url")
                HStack {
                    Text("填写网站首页地址，不含 /api/v4。可添加多个 GitLab 站点。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("添加 / 配置 GitLab") { applyServer(gitlab: true) }
                }
                if let serverError { Text(serverError).font(.caption).foregroundStyle(.red) }
                Text("所有启用连接中已勾选的仓库会同时显示，并按完整仓库 URL 分组。这里切换配置对象不会清空其他站点的阅读内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("启用 Issue 阅读", isOn: $enabled)
                    .accessibilityIdentifier("gitee-settings-enabled")
                Text("只读查看关注项目的 Issue 与评论，不更改 Atoll 原有的媒体、刘海、锁屏或文件暂存行为。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Git 仓库") }
            if enabled {
                Section("刘海预览") {
                    Stepper(value: Binding(get: { GINotchMetrics.clamp(notchMaximumItems) }, set: {
                        GINotchLayout.shared.setMaximumItems($0)
                    }), in: 1...10) {
                        LabeledContent("最多显示条数", value: "\(GINotchMetrics.clamp(notchMaximumItems)) 条")
                    }.accessibilityIdentifier("gitee-notch-maximum-items")
                    Text("默认 8 条，可设置 1–10 条。高度随筛选结果调整；屏幕空间不足时列表滚动。此限制不影响接口分页或阅读窗口。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("当前配置 · " + store.platformName) {
                    Text(store.remote.webURL.absoluteString).font(.caption).textSelection(.enabled)
                    if !store.isEnabled(store.remote) { Text("此连接已停用。请先在上方启用，再连接账户。").font(.caption).foregroundStyle(.secondary) }
                    if store.remote.usesHTTP { Text("当前使用 HTTP：令牌和 Issue 内容以明文传输。").font(.caption).foregroundStyle(.orange) }
                    if let account = store.account {
                        LabeledContent("当前账户", value: account.displayName)
                        if !store.demoMode { Text("@\(account.login)").font(.caption).foregroundStyle(.secondary) }
                        if store.demoMode {
                            Text("离线演示：非真实项目，不请求服务器。").font(.caption).foregroundStyle(.secondary)
                            Button("退出演示并连接账户") { store.deactivate() }
                        } else {
                            HStack {
                                Button(changeToken ? "取消更换" : "更换令牌…") { changeToken.toggle() }
                                Spacer()
                                Button("退出账户…", role: .destructive) { confirmDisconnect = true }
                            }
                            if changeToken { GIConnectionView().id(store.remote).disabled(!store.isEnabled(store.remote)) }
                            if let error = store.connectionError, !changeToken {
                                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    } else { GIConnectionView().id(store.remote).disabled(!store.isEnabled(store.remote)) }
                }
                if store.account != nil {
                    selectedSection
                    repositorySection
                    Section("阅读") {
                        Toggle("加载当前 Issue 所属站点的远程图片", isOn: $store.loadRemoteImages)
                        Text("图片默认关闭。开启后只加载允许来源的图片，不向图片地址附加账户令牌。需要额外鉴权的图片请在平台网页打开。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("正文字号")
                            Slider(value: $store.textScale, in: 0.85...1.6, step: 0.05)
                            Text("\(Int((store.textScale * 100).rounded()))%")
                                .monospacedDigit().frame(width: 45, alignment: .trailing)
                        }
                        Button("打开 Issue 阅读窗口") { GIReaderWindowController.shared.show() }
                    }
                }
            } else {
                Section {
                    Text("功能关闭时不请求服务器，并清除内存中的正文与评论。账户令牌仍保留在本机钥匙串中。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("移除已保存的账户令牌…", role: .destructive) { confirmDisconnect = true }
                    if let error = store.connectionError { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("关于与隐私") {
                Text("令牌仅保存在本机钥匙串；此模块不向 AI 或锁屏传递 Issue 内容。查看项目选择只影响本机，不修改平台 Watch / Star。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Markdown 组件许可证…") {
                    if let url = Bundle.main.url(forResource: "gitee-markdown-licenses", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Git 仓库")
        .onAppear { server = store.remote.gitLabURL?.absoluteString ?? store.savedGitLabServer; store.activate() }
        .onChange(of: enabled) { _, value in if value { store.activate() } }
        .onChange(of: store.remote) { _, _ in
            changeToken = false; source = "subscriptions"; filter = ""; confirmDisconnect = false; server = store.remote.gitLabURL?.absoluteString ?? store.savedGitLabServer
        }
        .onChange(of: store.account?.id) { _, _ in changeToken = false; source = "subscriptions" }
        .onChange(of: source) { _, value in store.refreshRepositories(source: value, reset: true) }
        .confirmationDialog("使用未加密的 HTTP 连接？", isPresented: $confirmHTTP) {
            Button("仍然使用 HTTP") {
                if let remote = pendingHTTPRemote { store.useRemote(remote); serverError = nil }
                pendingHTTPRemote = nil
            }
            Button("取消", role: .cancel) { pendingHTTPRemote = nil }
        } message: {
            Text("连接到 \(pendingHTTPRemote?.webURL.absoluteString ?? "") 时，访问令牌和私有 Issue 内容将明文传输。请仅在你信任的网络中使用。")
        }
        .confirmationDialog("移除此站点保存的令牌及其阅读内容？", isPresented: $confirmDisconnect) {
            Button("退出账户并移除令牌", role: .destructive) { store.disconnect() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("其他 Git 连接不受影响。不会修改平台上的项目、Issue 或收藏。之后可重新连接。")
        }
    }
    private var selectedSection: some View {
        Section("已选查看项目 · \(store.settingsSelectedRepositories.count)") {
            if store.settingsSelectedRepositories.isEmpty {
                Text("从下方\(store.projectSourceTitle)列表选择需要查看的项目。").foregroundStyle(.secondary)
            } else {
                ForEach(store.settingsSelectedRepositories) { repo in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repo.full_name).lineLimit(2)
                            Text(repo.path.isEmpty ? "无法解析仓库路径，请刷新项目列表" : repo.canonicalURL)
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        Button { setSelected(repo, false) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("仅从本机查看列表移除")
                    }
                }
                Button(store.loadingList ? "正在验证读取…" : "刷新当前连接的已选仓库") { store.refreshIssues(reset: true, only: Set(store.settingsSelectedRepositories.map(\.canonicalURL))) }
                    .disabled(store.loadingList || store.demoMode)
                if !store.listFailures.isEmpty {
                    ForEach(store.listFailures) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.repository).font(.caption.weight(.medium)).textSelection(.enabled)
                            Text(failure.message + (failure.status.map { "（HTTP \($0)）" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Button("重试失败项目") { store.retryFailedRepositories() }.disabled(store.loadingList)
                } else if let time = store.lastSync {
                    LabeledContent("最近成功读取") { Text(time, style: .time) }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var repositorySection: some View {
        Section("添加查看项目") {
            Picker("项目来源", selection: $source) {
                Text(store.remote.isGitLab ? "参与项目" : "Watch 关注").tag("subscriptions")
                Text("Star 收藏").tag("starred")
            }.pickerStyle(.segmented).disabled(store.demoMode)
            HStack {
                TextField("搜索已加载项目", text: $filter).textFieldStyle(.roundedBorder)
                Button { store.refreshRepositories(source: source, reset: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(store.loadingRepositories || store.demoMode).help("刷新项目来源")
            }
            if store.loadingRepositories && store.repositories.isEmpty {
                ProgressView("正在加载项目…").controlSize(.small)
            } else if filteredRepositories.isEmpty && store.repositoryError == nil {
                Text(filter.isEmpty ? "这个来源暂未返回项目。可切换项目来源或刷新。" : "已加载范围内没有匹配项目。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredRepositories) { repo in
                        Toggle(isOn: Binding(get: { selectedIDs.contains(repo.id) }, set: { setSelected(repo, $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(repo.full_name).lineLimit(2)
                                Text(repo.path.isEmpty ? "仓库地址无效" : repo.canonicalURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.toggleStyle(.checkbox).disabled(repo.path.isEmpty)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }.frame(height: min(240, max(60, CGFloat(filteredRepositories.count) * 54)))
            HStack {
                Text("已加载 \(store.repositories.count) 个 · 勾选后立即保存").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.moreRepositories {
                    Button("加载更多") { store.refreshRepositories(source: source, reset: false) }.disabled(store.loadingRepositories)
                }
            }
            if let error = store.repositoryError {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    private func applyServer(gitlab: Bool) {
        do {
            let remote = gitlab ? try GIReaderRemote.gitLab(server) : .gitee
            if remote.usesHTTP && remote != store.remote {
                pendingHTTPRemote = remote
                confirmHTTP = true
                return
            }
            store.useRemote(remote)
            if !gitlab { server = store.savedGitLabServer }
            serverError = nil
        } catch { serverError = error.localizedDescription }
    }
    private func setSelected(_ repo: GIRepository, _ selected: Bool) {
        var values = store.settingsSelectedRepositories.filter { $0.id != repo.id }
        if selected { values.append(repo) }
        store.applySelection(values)
    }
}
