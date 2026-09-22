from pathlib import Path
root=Path('.')
def edit(path, old, new, count=1):
    p=root/path;s=p.read_text();assert s.count(old)==count,(path,old[:80],s.count(old));p.write_text(s.replace(old,new))
V='DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift'
edit(V,'final class GIReaderWindowController: NSWindowController {','final class GIReaderWindowController: NSWindowController, NSWindowDelegate {')
edit(V,'        window.hidesOnDeactivate = false\n','        window.hidesOnDeactivate = false\n        window.isExcludedFromWindowsMenu = false\n        window.identifier = NSUserInterfaceItemIdentifier("ToolIsle.GiteeReader")\n        window.delegate = self\n')
edit(V,'        showWindow(nil)\n        window?.makeKeyAndOrderFront(nil)\n        NSApp.activate(ignoringOtherApps: true)','''        guard let window else { return }
        GIReaderSession.shared.opened(window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.unhide(nil)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeMain()
        window.makeKeyAndOrderFront(nil)''')
edit(V,'\n}\n\nstruct GINotchView: View {','''
    func windowWillClose(_ notification: Notification) {
        if let window { GIReaderSession.shared.closed(window) }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if GIReaderSession.shared.isOpen { NSApp.setActivationPolicy(.regular) }
    }
    func showFilters() {
        show()
        NotificationCenter.default.post(name: .giteeFocusFilters, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .giteeFocusFilters, object: nil)
        }
    }
}

struct GINotchView: View {
    var screenName: String? = nil
    @ObservedObject private var layout = GINotchLayout.shared''')
edit(V,'            .accessibilityIdentifier("gitee-notch-header")\n','''            .accessibilityIdentifier("gitee-notch-header")

            HStack(spacing: 8) {
                Text(store.filterSummary).font(.system(size: 10)).foregroundStyle(secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("调整筛选") { GIReaderWindowController.shared.showFilters() }
                    .buttonStyle(.plain).font(.system(size: 10))
            }.frame(height: 18)
''')
edit(V,'store.query = ""; store.repositoryFilter = ""; store.stateFilter = "all"','store.clearFilters()')
edit(V,'store.filteredItems.prefix(3)','store.filteredItems.prefix(layout.metrics.limit)')
edit(V,'.padding(.horizontal, 8).padding(.vertical, 3)','.padding(.horizontal, 8).padding(.vertical, 3)\n                                .frame(height: GINotchMetrics.rowHeight)')
edit(V,'"筛选后 \\(store.filteredItems.count) / 已加载 \\(store.items.count)"','"显示 \\(min(store.filteredItems.count, layout.metrics.limit)) / 匹配 \\(store.filteredItems.count) 条"')
edit(V,'        // Fit below the original header within the existing 250pt Gitee panel.\n        // A finite budget keeps controls visible and long/error content scrollable.\n        .frame(height: 190, alignment: .topLeading)','''        // Same bounded metrics as the native window and the mouse interaction area.
        .frame(height: layout.contentHeight(screenName: screenName), alignment: .topLeading)''')
edit(V,'        .accessibilityIdentifier("gitee-notch-surface")\n        .onAppear { store.activate() }','        .accessibilityIdentifier("gitee-notch-surface")\n        .onAppear { store.activate(); layout.refreshNow() }')
edit(V,'                    if showList { GIIssueListView().frame(minWidth: 240, idealWidth: 280, maxWidth: 320) }','                    if showList { GIIssueListView().frame(minWidth: 260, idealWidth: 320, maxWidth: 380) }')
edit(V,'        .frame(minWidth: 720, minHeight: 420)\n                .onAppear { store.activate() }','''        .frame(minWidth: 720, minHeight: 420)
        .onReceive(NotificationCenter.default.publisher(for: .giteeFocusFilters)) { _ in showList = true }
        .onAppear { store.activate() }''')
edit(V,'                    Divider()\n                    Button("复制 Issue 链接") { GIPasteboard.copy(visit.sourceURL.absoluteString) }','')
edit(V,'            if let visit = store.visit {\n                Menu {','''            if let visit = store.visit {
                GICopyIssueButton(url: visit.route.url)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Menu {''')
s=Path(V).read_text();start=s.index('            VStack(spacing: 10) {',s.index('private struct GIIssueListView:'));end=s.index('            Divider()',start)
s=s[:start]+'            GIFilterBar()\n'+s[end:];Path(V).write_text(s)
s=Path(V).read_text();start=s.index('                        VStack(alignment: .leading, spacing: 7)',s.index('private struct GIIssueListView:'));end=s.index('                            .contextMenu',start)
s=s[:start]+'''                        GIIssueRow(item: item, selected: store.selectedListID == item.route).tag(item.route)
'''+s[end:];Path(V).write_text(s)
edit(V,'                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)\n                }.padding(20)', '''                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !store.items.isEmpty && store.hasActiveFilters {
                        Button("清除筛选") { store.clearFilters() }.buttonStyle(.bordered)
                    }
                }.padding(20)''')
edit(V,'''    static func copy(_ string: String) {
        guard string.utf8.count <= 2 * 1024 * 1024 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }''','''    @discardableResult static func copy(_ string: String) -> Bool {
        guard string.utf8.count <= 2 * 1024 * 1024 else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(string, forType: .string)
    }''')
S='DynamicIsland/ToolIsleFeatures/Gitee/GIStore.swift'
edit(S,'    private var selectionKey: String?', '''    var hasActiveFilters: Bool { !query.isEmpty || !repositoryFilter.isEmpty || stateFilter != "all" }
    var filterSummary: String {
        let states = ["all":"全部状态", "unfinished":"未完成", "open":"开启", "progressing":"进行中", "closed":"已关闭", "rejected":"已拒绝"]
        return (repositoryFilter.isEmpty ? "全部已选项目" : repositoryFilter) + " · " + (states[stateFilter] ?? stateFilter) + (query.isEmpty ? "" : " · 搜索：" + query)
    }
    func clearFilters() { query = ""; repositoryFilter = ""; stateFilter = "all" }
    private var selectionKey: String?''')
edit(S,'    static let demoA = GIIssueRoute', '''    func setUXDemoCount(_ count: Int) {
        guard demoMode, ProcessInfo.processInfo.arguments.contains("--gitee-ux-probe") else { return }
        items = (0..<max(0, min(count, 20))).map { n in
            let route = n == 0 ? Self.demoA : GIIssueRoute(repository: Self.demoA.repository, number: "IDEMO\\(n)")
            let issue = GIIssue(id: Int64(n + 1), number: route.number,
                title: n == 0 ? Self.demoIssue(Self.demoA).title : "离线演示 \\(n + 1)：验证列表、筛选与窗口交互",
                state: "progressing", body: nil, html_url: route.url.absoluteString,
                user: account, updated_at: "2026-09-22T08:30:00+08:00", comments: 0)
            return GIListItem(route: route, issue: issue)
        }
    }
    static let demoA = GIIssueRoute''')
S='DynamicIsland/ToolIsleFeatures/Gitee/GISettingsView.swift'
edit(S,'    @State private var source', '    @Default(.giteeNotchMaximumItems) private var notchMaximumItems\n    @State private var source')
edit(S,'            if enabled {\n                Section("账户") {','''            if enabled {
                Section("刘海预览") {
                    Stepper(value: Binding(get: { GINotchMetrics.clamp(notchMaximumItems) }, set: {
                        notchMaximumItems = GINotchMetrics.clamp($0); GINotchLayout.shared.refreshNow()
                    }), in: 1...10) {
                        LabeledContent("最多显示条数", value: "\\(GINotchMetrics.clamp(notchMaximumItems)) 条")
                    }.accessibilityIdentifier("gitee-notch-maximum-items")
                    Text("默认 8 条，可设置 1–10 条。高度随筛选结果调整；屏幕空间不足时列表滚动。此限制不影响接口分页或阅读窗口。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("账户") {''')
S='DynamicIsland/components/Settings/SettingsWindowController.swift'
edit(S,'        // Set app back to accessory mode immediately\n        NSApp.setActivationPolicy(.accessory)','''        // A still-open Gitee reader remains a normal switchable application window.
        GIReaderSession.shared.settingsClosed(window)''')
S='DynamicIsland/ContentView.swift'
edit(S,'    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared','    @ObservedObject private var giteeNotchLayout = GINotchLayout.shared\n    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared')
edit(S,'return CGSize(width: baseSize.width, height: max(baseSize.height, 250))','return giteeNotchLayout.size(base: baseSize, screenName: vm.screen)')
edit(S,'                                GINotchView()','                                GINotchView(screenName: vm.screen)')
S='DynamicIsland/models/DynamicIslandViewModel.swift'
edit(S,'    private func calculateDynamicNotchSize() -> CGSize {','''    func refreshGiteeNotchSize() {
        guard coordinator.currentView == .giteeIssues, notchState == .open,
              !Defaults[.enableMinimalisticUI] else { return }
        let target = GINotchLayout.shared.size(base: openNotchSize, screenName: screen)
        if notchSize != target { notchSize = target }
    }

    private func calculateDynamicNotchSize() -> CGSize {''')
edit(S,'        var adjustedSize = baseSize\n','''        var adjustedSize = baseSize
        if coordinator.currentView == .giteeIssues && !Defaults[.enableMinimalisticUI] {
            return GINotchLayout.shared.size(base: baseSize, screenName: screen)
        }
''')
edit(S,'                NSApp.setActivationPolicy(.accessory)\n                NSApp.deactivate()','''                GIReaderSession.shared.restorePolicy()
                if !GIReaderSession.shared.isOpen { NSApp.deactivate() }''')
S='DynamicIsland/DynamicIslandApp.swift'
edit(S,'        installTopMenuItemsIfNeeded()\n    }\n\n    func application(_ application:', '''        installTopMenuItemsIfNeeded()
        GIReaderSession.shared.applicationBecameActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !GIReaderSession.shared.reopen()
    }

    func application(_ application:''')
edit(S,'            baseSize.height = max(baseSize.height, 250)\n        } else if coordinator.currentView == .terminal {','            baseSize = GINotchLayout.shared.size(base: baseSize, screenName: vm.screen)\n        } else if coordinator.currentView == .terminal {')
edit(S,'        var adjusted = baseSize\n        if shouldUseDynamicIslandMode', '''        var adjusted = baseSize
        if coordinator.currentView == .giteeIssues && !Defaults[.enableMinimalisticUI] {
            let model = viewModels[screen] ?? vm
            if model.notchState == .open {
                model.refreshGiteeNotchSize()
                adjusted = addShadowPadding(to: GINotchLayout.shared.size(base: openNotchSize, screen: screen), isMinimalistic: false)
            }
        }
        if shouldUseDynamicIslandMode''')
edit(S,'        networkConnectivityManager.$hudState\n','''        GINotchLayout.shared.$metrics.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.coordinator.currentView == .giteeIssues else { return }
                self.vm.refreshGiteeNotchSize()
                self.viewModels.values.forEach { $0.refreshGiteeNotchSize() }
                self.updateWindowSizeIfNeeded()
            }.store(in: &cancellables)

        networkConnectivityManager.$hudState
''')
edit(S,'                    NSApp.setActivationPolicy(.accessory)\n                    window.close()\n                    NSApp.deactivate()','''                    GIReaderSession.shared.restorePolicy(excluding: window)
                    window.close()
                    if !GIReaderSession.shared.isOpen { NSApp.deactivate() }''')
edit(S,'                GINotchPreviewProbe.run(app: self)','                GINotchPreviewProbe.run(app: self)\n                GIUXProbe.run(app: self)')
S='DynamicIsland.xcodeproj/project.pbxproj'
edit(S,'CURRENT_PROJECT_VERSION = 1641;', 'CURRENT_PROJECT_VERSION = 1642;',2)
print('Applied scoped Gitee UX / reader lifetime changes; original Atoll services retained.')
