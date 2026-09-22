from pathlib import Path
p=Path('tests/render_gitee_notch.py');s=p.read_text()
s=s.replace("views = 'import AppKit\\nimport SwiftUI\\n' +", "views = (ROOT/'DynamicIsland/ToolIsleFeatures/Gitee/GINotchMetrics.swift').read_text() + '\\nimport AppKit\\nimport SwiftUI\\n' +")
s=s.replace('    func retryFailedRepositories() {}','''    var filterSummary: String { "全部已选项目 · 全部状态" }
    func clearFilters() { query = ""; repositoryFilter = ""; stateFilter = "all" }
    func retryFailedRepositories() {}''')
s=s.replace('@MainActor final class GIReaderWindowController {','''@MainActor final class GINotchLayout: ObservableObject {
    static let shared = GINotchLayout()
    var metrics: GINotchMetrics { GINotchMetrics(count: GIStore.shared.filteredItems.count, limit: 8) }
    func refreshNow() {}
    func contentHeight(screenName: String?) -> CGFloat { metrics.notchHeight(availableHeight: 900) - GINotchMetrics.hostInset }
}
@MainActor final class GIReaderWindowController {''')
s=s.replace('    func show(route:GIIssueRoute?=nil) {}','    func show(route:GIIssueRoute?=nil) {}\n    func showFilters() {}')
s=s.replace('                        let root=AnyView(Group {','''                        let height: CGFloat = legacy ? 190 : GINotchLayout.shared.contentHeight(screenName: nil)
                        let root=AnyView(Group {''')
s=s.replace('height:190','height:height')
s=s.replace('body=bright(10,40,width-12,155), footer=bright(width-170,158,width-12,187)','body=bright(10,legacy ? 40 : 70,width-12,Int(height)-35), footer=bright(width-170,Int(height)-32,width-12,Int(height)-3)')
s=s.replace('Double(rep.pixelsHigh)/scale-190','Double(rep.pixelsHigh)/scale-Double(height)')
p.write_text(s)
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIUXProbe.swift');s=p.read_text()
s=s.replace('            var checks: [String] = []','            var checks: [String] = []\n            var failures: [String] = []')
s=s.replace('                guard condition else { throw NSError(domain: "GIUXProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }','                guard condition else { failures.append(name); return }')
s=s.replace('            func capture(_ window: NSWindow, _ name: String) {','''            func requestUserReactivation() async throws {
                // Exercise LaunchServices activation, not forbidden background focus stealing.
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.createsNewApplicationInstance = false
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                await pause(0.8)
            }
            func capture(_ window: NSWindow, _ name: String) {''')
s=s.replace('                    NSRunningApplication.current.activate(options: [.activateAllWindows]); await pause()','                    try await requestUserReactivation()')
s=s.replace('                NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true); await pause()','                NSApp.unhide(nil); try await requestUserReactivation()')
s=s.replace('["passed": true, "checks": checks, "sizes": sizes, "accessibilitySubrole": subrole,','["passed": failures.isEmpty, "checks": checks, "failures": failures, "sizes": sizes, "accessibilitySubrole": subrole,')
s=s.replace('["passed": false, "error": error.localizedDescription, "checks": checks, "sizes": sizes]','["passed": false, "error": error.localizedDescription, "checks": checks, "failures": failures, "sizes": sizes]')
p.write_text(s)
print('Updated native rendering and lifecycle probes without changing production behavior.')
