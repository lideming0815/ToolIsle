// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults

/// Explicit CI-only synthetic regression. Normal launches do not execute this code.
@MainActor
enum GIUXProbe {
    static func run(app: AppDelegate) {
        guard ProcessInfo.processInfo.arguments.contains("--gitee-ux-probe"), GIStore.shared.demoMode,
              let output = ProcessInfo.processInfo.environment["TOOLISLE_GITEE_UX_RESULT"] else { return }
        Task { @MainActor in
            var checks: [String] = []
            var sizes: [[String: Any]] = []
            let result = URL(fileURLWithPath: output)
            func check(_ condition: Bool, _ name: String) throws {
                guard condition else { throw NSError(domain: "GIUXProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
                checks.append(name)
            }
            func pause(_ seconds: Double = 0.5) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            func capture(_ window: NSWindow, _ name: String) {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), result.deletingLastPathComponent().appendingPathComponent(name + ".png").path]
                try? process.run(); process.waitUntilExit()
            }
            do {
                let reader = GIReaderWindowController.shared
                guard let window = reader.window else { throw NSError(domain: "missing-reader", code: 1) }
                // The ephemeral runner may show its first-run onboarding; hide only in this explicit probe.
                for other in NSApp.windows where other.identifier?.rawValue == "OnboardingWindow" { other.orderOut(nil) }
                let store = GIStore.shared
                let selected = store.selectedListID
                let visit = store.visit?.id
                reader.show(); await pause()
                try check(NSApp.activationPolicy() == .regular, "reader acquires regular activation policy")
                try check(window.isKeyWindow && window.canBecomeMain, "reader is key/main capable")
                try check(!(window is NSPanel) && window.level == .normal && !window.hidesOnDeactivate && !window.isExcludedFromWindowsMenu,
                          "normal, non-floating, switchable reader window")
                let subrole = String(describing: window.accessibilitySubrole())
                try check(subrole.contains("AXStandardWindow"), "accessibility subrole is AXStandardWindow")
                for round in 1...3 {
                    if round == 2 { SettingsWindowController.shared.showWindow() } else { GISettingsNavigation.shared.open() }
                    await pause()
                    let settings = SettingsWindowController.shared.window!
                    try check(settings.isKeyWindow, "settings becomes key round \(round)")
                    if round == 1 { capture(settings, "ux-settings") }
                    settings.performClose(nil); await pause()
                    try check(window.isKeyWindow && NSApp.activationPolicy() == .regular, "closing settings returns to reader round \(round)")
                }
                try check(store.selectedListID == selected && store.visit?.id == visit, "settings round trip preserves Issue/history selection")
                if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                    finder.activate(options: [.activateAllWindows]); await pause()
                    try check(!NSApp.isActive && window.isVisible, "external application activation does not hide reader")
                    NSRunningApplication.current.activate(options: [.activateAllWindows]); await pause()
                    try check(window.isKeyWindow && NSApp.activationPolicy() == .regular, "reactivation restores reader")
                }
                NSApp.hide(nil); await pause()
                try check(GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .regular, "Cmd-H lifetime remains switchable")
                NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true); await pause()
                window.miniaturize(nil); await pause(0.8)
                try check(window.isMiniaturized, "reader minimizes normally")
                GISettingsNavigation.shared.open(); await pause()
                SettingsWindowController.shared.window?.performClose(nil); await pause()
                try check(window.isMiniaturized && NSApp.activationPolicy() == .regular, "closing settings does not unminimize reader")
                try check(GIReaderSession.shared.reopen(), "explicit app reopen handles existing reader")
                await pause(0.8)
                try check(!window.isMiniaturized && window.isKeyWindow, "explicit reopen restores minimized reader")
                store.query = "fixture-no-match"; store.repositoryFilter = "missing/project"; store.stateFilter = "closed"
                store.clearFilters()
                try check(!store.hasActiveFilters && store.selectedListID == selected && store.visit?.id == visit,
                          "clear filters keeps reading history/selection")
                try check(GIPasteboard.copy(GIStore.demoB.url.absoluteString) && NSPasteboard.general.string(forType: .string) == GIStore.demoB.url.absoluteString,
                          "real pasteboard contains only selected Issue URL")
                try check(store.selectedListID == selected && store.visit?.id == visit, "copying a different row does not navigate")
                try check(!GIPasteboard.copy(String(repeating: "a", count: 2 * 1024 * 1024 + 1)), "copy failure is observable")

                let layout = GINotchLayout.shared
                Defaults[.giteeNotchMaximumItems] = 8
                let coordinator = DynamicIslandViewCoordinator.shared
                coordinator.firstLaunch = false; coordinator.alwaysShowTabs = true
                Defaults[.enableMinimalisticUI] = false
                coordinator.currentView = .giteeIssues
                let models = [app.vm] + Array(app.viewModels.values)
                for model in models { model.open(); model.setAutoCloseSuppression(true, token: UUID()) }
                await pause()
                guard let notch = app.window ?? app.windows.values.first else { throw NSError(domain: "missing-notch", code: 2) }
                for count in [0, 1, 3, 8, 15] {
                    store.setUXDemoCount(count); await pause(0.8)
                    let expected = layout.size(base: openNotchSize, screen: notch.screen).height
                    try check(layout.metrics.visibleCount == min(count, 8), "default cap with \(count) loaded Issues")
                    try check(notch.frame.height >= expected && notch.frame.height <= expected + 100, "native bounds match content with \(count) Issues")
                    for model in models where model.notchState == .open {
                        try check(abs(model.notchSize.height - layout.size(base: openNotchSize, screenName: model.screen).height) < 1,
                                  "mouse hit bounds match content with \(count) Issues")
                    }
                    sizes.append(["loaded": count, "limit": 8, "windowHeight": notch.frame.height, "contentHeight": layout.contentHeight(screenName: notch.screen?.localizedName)])
                    if count == 1 || count == 8 { capture(notch, "ux-notch-\(count)") }
                }
                try check((sizes[3]["windowHeight"] as! CGFloat) > (sizes[1]["windowHeight"] as! CGFloat), "native notch grows from 1 to 8 rows")
                try check(sizes[3]["windowHeight"] as! CGFloat == sizes[4]["windowHeight"] as! CGFloat, "more than 8 does not expand past preview cap")
                Defaults[.giteeNotchMaximumItems] = 10; await pause(0.8)
                try check(layout.metrics.limit == 10 && layout.metrics.visibleCount == 10, "settings limit changes immediately to ten")
                capture(notch, "ux-notch-10")
                store.query = "fixture-no-match"; await pause(0.8); capture(notch, "ux-notch-empty")
                store.clearFilters(); Defaults[.giteeNotchMaximumItems] = 8; await pause()
                NSApp.appearance = NSAppearance(named: .aqua); capture(notch, "ux-notch-light")
                NSApp.appearance = NSAppearance(named: .darkAqua); capture(notch, "ux-notch-dark")
                NSApp.appearance = nil
                reader.show(); await pause(); capture(window, "ux-reader")
                GISettingsNavigation.shared.open(); await pause()
                window.performClose(nil); await pause()
                try check(!GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .regular, "reader close preserves still-open settings")
                SettingsWindowController.shared.window?.performClose(nil); await pause()
                try check(!GIReaderSession.shared.isOpen && !window.isVisible && NSApp.activationPolicy() == .accessory,
                          "last document close returns to original accessory mode without resurrecting reader")
                SettingsWindowController.shared.showWindow(); await pause()
                SettingsWindowController.shared.window?.performClose(nil); await pause()
                try check(!window.isVisible && NSApp.activationPolicy() == .accessory, "settings-only use does not reopen reader")
                let info: [String: Any] = ["passed": true, "checks": checks, "sizes": sizes, "accessibilitySubrole": subrole,
                    "synthetic_data": true, "live_gitee_tested": false, "third_party_alttab_hotkey_tested": false]
                try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: result)
            } catch {
                let info: [String: Any] = ["passed": false, "error": error.localizedDescription, "checks": checks, "sizes": sizes]
                try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: result)
            }
        }
    }
}
