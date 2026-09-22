from pathlib import Path

def replace_once(path, old, new):
    p=Path(path)
    s=p.read_text()
    assert s.count(old)==1, (path, s.count(old))
    p.write_text(s.replace(old,new,1))

replace_once('DynamicIsland/models/DynamicIslandViewModel.swift', '''    func refreshGiteeNotchSize() {
        guard coordinator.currentView == .giteeIssues, notchState == .open,
              !Defaults[.enableMinimalisticUI] else { return }
        let target = GINotchLayout.shared.size(base: openNotchSize, screenName: screen)
        if notchSize != target { notchSize = target }
    }''', '''    func refreshGiteeNotchSize(leavingGitee: Bool = false) {
        guard notchState == .open,
              leavingGitee || (coordinator.currentView == .giteeIssues && !Defaults[.enableMinimalisticUI]) else { return }
        // Leaving the optional page restores Atoll's existing sizing calculation;
        // otherwise a tall Gitee mouse region would linger over the Home page.
        let target = calculateDynamicNotchSize()
        if notchSize != target { notchSize = target }
    }''')
replace_once('DynamicIsland/ContentView.swift', '''            .onChange(of: coordinator.currentView) { _, newValue in
                if enableStatsFeature {''', '''            .onChange(of: coordinator.currentView) { oldValue, newValue in
                vm.refreshGiteeNotchSize(leavingGitee: oldValue == .giteeIssues)
                if enableStatsFeature {''')
replace_once('DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift',
             'if GIReaderSession.shared.isOpen { NSApp.setActivationPolicy(.regular) }',
             'if GIReaderSession.shared.isOpen && NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }')
replace_once('DynamicIsland/components/Settings/SettingsWindowController.swift',
             '        NSApp.setActivationPolicy(.regular)',
             '        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }')
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIUXProbe.swift')
s=p.read_text()
s=s.replace('func requestUserReactivation() async throws {', 'func requestUserReactivation(hidden: Bool = false) async throws {')
s=s.replace('driver.arguments = [String(ProcessInfo.processInfo.processIdentifier), path.path]',
            'driver.arguments = [String(ProcessInfo.processInfo.processIdentifier), path.path, hidden ? "hidden" : "roundtrip"]')
s=s.replace('''                        if NSApp.isActive { NSApp.yieldActivation(to: external) }
                        external.activate(options: [.activateAllWindows])''', '''                        if !hidden {
                            if NSApp.isActive { NSApp.yieldActivation(to: external) }
                            external.activate(options: [.activateAllWindows])
                        }''')
s=s.replace('NSApp.unhide(nil); try await requestUserReactivation()', 'try await requestUserReactivation(hidden: true)')
a=s.index('                try check(GIPasteboard.copy(')
b=s.index('\n                let layout =',a)
copy=s[a:b]
s=s[:a]+s[b:]
s=s.replace('                reader.show(); await pause(); capture(window, "ux-reader")',
            '                reader.show(); await pause(); capture(window, "ux-reader")\n'+copy)
old='''                capture(notch, "ux-notch-10")
                store.query = "fixture-no-match";'''
new='''                capture(notch, "ux-notch-10")
                let expandedGiteeHeight = notch.frame.height
                coordinator.currentView = .home; await pause(0.8)
                try check(notch.frame.height < expandedGiteeHeight, "leaving Gitee restores Home native height")
                for model in models where model.notchState == .open {
                    try check(model.notchSize.height < expandedGiteeHeight - 60, "leaving Gitee restores original mouse hit area")
                }
                coordinator.currentView = .giteeIssues; await pause(0.8)
                try check(abs(notch.frame.height - expandedGiteeHeight) < 1, "returning to Gitee restores adaptive height")
                store.query = "fixture-no-match";'''
assert s.count(old)==1
p.write_text(s.replace(old,new))
