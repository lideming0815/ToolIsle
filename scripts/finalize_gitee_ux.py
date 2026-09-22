from pathlib import Path

def once(path,old,new):
    p=Path(path);s=p.read_text();assert s.count(old)==1,(path,s.count(old),old[:100]);p.write_text(s.replace(old,new))
base='DynamicIsland/ToolIsleFeatures/Gitee/'
once(base+'GISettingsView.swift', 'notchMaximumItems = GINotchMetrics.clamp($0); GINotchLayout.shared.refreshNow()', 'GINotchLayout.shared.setMaximumItems($0)')
p='DynamicIsland/components/Settings/SettingsWindowController.swift'
once(p, '    private var updaterController: SPUStandardUpdaterController?', '    private var updaterController: SPUStandardUpdaterController?\n    private var isClosing = false')
once(p, '    func showWindow() {\n        // Ensure window exists', '    func showWindow() {\n        isClosing = false\n        // Ensure window exists')
once(p, '        DispatchQueue.main.async { [weak self] in\n            self?.window?.makeKeyAndOrderFront(nil)\n        }', '        DispatchQueue.main.async { [weak self] in\n            guard let self, !self.isClosing else { return }\n            self.window?.makeKeyAndOrderFront(nil)\n        }')
once(p, '    private func relinquishFocus() {\n        window?.orderOut(nil)', '    private func relinquishFocus() {\n        isClosing = true\n        window?.orderOut(nil)')
once(p, '        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }', '        if !isClosing && NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }')
p=base+'GIReaderSession.swift'
once(p, '        restorePolicy(excluding: window)\n    }', '''        restorePolicy(excluding: window)
        let generation = restoreGeneration
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, generation == self.restoreGeneration, !self.isOpen else { return }
            self.restorePolicy(excluding: window)
        }
    }''')
once(p, '''            guard let self, generation == self.restoreGeneration, userIsInApplication,
                  NSApp.isActive, self.isOpen, let window = self.reader,''', '''            guard let self, generation == self.restoreGeneration else { return }
            // Reconcile after willClose and any final key-window callbacks finish.
            self.restorePolicy(excluding: settings)
            guard userIsInApplication, NSApp.isActive, self.isOpen, let window = self.reader,''')
p=base+'GIUXProbe.swift';s=Path(p).read_text()
s=s.replace('Defaults[.giteeNotchMaximumItems] = 8','GINotchLayout.shared.setMaximumItems(8)').replace('Defaults[.giteeNotchMaximumItems] = 10','GINotchLayout.shared.setMaximumItems(10)')
s=s.replace('for other in NSApp.windows where other.identifier?.rawValue == "OnboardingWindow" { other.orderOut(nil) }', 'DynamicIslandViewCoordinator.shared.firstLaunch = false\n                for other in NSApp.windows where other.identifier?.rawValue == "OnboardingWindow" { other.close() }')
s=s.replace('            var activations: [[String: Any]] = []', '            var activations: [[String: Any]] = []\n            var windowSnapshots: [[String: Any]] = []')
anchor='            func capture(_ window: NSWindow, _ name: String) {'
assert s.count(anchor)==1
s=s.replace(anchor, '''            func snapshot(_ stage: String) {
                let windows: [[String: Any]] = NSApp.windows.map { window in
                    ["class": String(describing: type(of: window)), "title": window.title,
                     "identifier": window.identifier?.rawValue ?? "", "visible": window.isVisible,
                     "minimized": window.isMiniaturized, "key": window.isKeyWindow,
                     "normal_document": window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal]
                }
                windowSnapshots.append(["stage": stage, "reader_open": GIReaderSession.shared.isOpen,
                                        "activation_policy": NSApp.activationPolicy().rawValue, "windows": windows,
                                        "stored_limit": Defaults[.giteeNotchMaximumItems], "layout_limit": GINotchLayout.shared.metrics.limit])
            }
''' + anchor)
s=s.replace('                try check(layout.metrics.limit == 10 && layout.metrics.visibleCount == 10, "settings limit changes immediately to ten")', '''                snapshot("setting-ten")
                try check(Defaults[.giteeNotchMaximumItems] == 10 && layout.metrics.limit == 10 && layout.metrics.visibleCount == 10, "settings limit changes immediately to ten")''')
s=s.replace('                try check(!GIReaderSession.shared.isOpen && !window.isVisible && NSApp.activationPolicy() == .accessory,', '                snapshot("last-document-closed")\n                try check(!GIReaderSession.shared.isOpen && !window.isVisible && NSApp.activationPolicy() == .accessory,')
s=s.replace('                try check(!window.isVisible && NSApp.activationPolicy() == .accessory, "settings-only use does not reopen reader")','                snapshot("settings-only-closed")\n                try check(!window.isVisible && NSApp.activationPolicy() == .accessory, "settings-only use does not reopen reader")')
s=s.replace('"activation_runs": activations', '"activation_runs": activations, "window_snapshots": windowSnapshots')
Path(p).write_text(s)
