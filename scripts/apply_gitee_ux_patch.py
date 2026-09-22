from pathlib import Path
p=Path('DynamicIsland/ContentView.swift');s=p.read_text()
old='''            .onChange(of: coordinator.currentView) { _, newValue in
                if enableStatsFeature {'''
new='''            .onChange(of: coordinator.currentView) { oldValue, newValue in
                // Restore the original page's interaction bounds when leaving Gitee.
                // Do not let an eight-row preview leave a tall invisible hover region.
                if vm.notchState == .open && (oldValue == .giteeIssues || newValue == .giteeIssues) {
                    vm.notchSize = dynamicNotchSize
                }
                if enableStatsFeature {'''
assert old in s;s=s.replace(old,new);p.write_text(s)
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIUXProbe.swift');s=p.read_text()
old='''                NSApp.appearance = nil
                reader.show(); await pause(); capture(window, "ux-reader")'''
new='''                NSApp.appearance = nil
                let giteeHeight = notch.frame.height
                coordinator.currentView = .home; await pause(0.8)
                try check(notch.frame.height < giteeHeight, "returning to Home restores original native height")
                for model in models where model.notchState == .open {
                    try check(model.notchSize.height < layout.size(base: openNotchSize, screenName: model.screen).height,
                              "returning to Home removes oversized Gitee mouse region")
                }
                coordinator.currentView = .giteeIssues; await pause(0.8)
                try check(abs(notch.frame.height - giteeHeight) < 1, "returning to Gitee restores content-derived height")
                reader.show(); await pause(); capture(window, "ux-reader")'''
assert old in s;s=s.replace(old,new);p.write_text(s)
print('Added scoped tab-transition bounds reset and its actual-window regression.')
