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
            var failures: [String] = []
            var sizes: [[String: Any]] = []
            var activations: [[String: Any]] = []
            var windowSnapshots: [[String: Any]] = []
            let result = URL(fileURLWithPath: output)
            func check(_ condition: Bool, _ name: String) throws {
                FileHandle.standardError.write(Data(("GIUX: " + (condition ? "PASS " : "FAIL ") + name + "\n").utf8))
                guard condition else { failures.append(name); return }
                checks.append(name)
            }
            func pause(_ seconds: Double = 0.5) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            func requestUserReactivation(hidden: Bool = false) async throws {
                guard let executable = ProcessInfo.processInfo.environment["TOOLISLE_GITEE_FOCUS_DRIVER"] else {
                    throw NSError(domain: "missing-focus-driver", code: 3)
                }
                let path = result.deletingLastPathComponent().appendingPathComponent("ux-activation-\(activations.count).json")
                let ready = path.appendingPathExtension("ready")
                let driver = Process()
                driver.executableURL = URL(fileURLWithPath: executable)
                driver.arguments = [String(ProcessInfo.processInfo.processIdentifier), path.path, hidden ? "hidden" : "roundtrip"]
                try driver.run()
                defer { if driver.isRunning { driver.terminate() } }
                for _ in 0..<40 {
                    if let text = try? String(contentsOf: ready, encoding: .utf8), let pid = Int32(text),
                       let external = NSRunningApplication(processIdentifier: pid) {
                        if !hidden {
                            if NSApp.isActive { NSApp.yieldActivation(to: external) }
                            external.activate(options: [.activateAllWindows])
                        }
                        break
                    }
                    await pause(0.1)
                }
                for _ in 0..<140 {
                    if FileManager.default.fileExists(atPath: path.path) { break }
                    await pause(0.1)
                }
                guard let data = try? Data(contentsOf: path),
                      let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NSError(domain: "focus-driver-timeout", code: 4)
                }
                activations.append(info)
                try check(info["external_application_active"] as? Bool == true, "external driver actually becomes foreground")
                try check(info["target_active"] as? Bool == true && NSApp.isActive, "cross-process activation returns to application")
                await pause(0.4)
            }
            @MainActor func snapshot(_ stage: String) {
                let windows: [[String: Any]] = NSApp.windows.map { window in
                    var info: [String: Any] = ["class": String(describing: type(of: window)), "title": window.title,
                                              "identifier": window.identifier?.rawValue ?? "", "visible": window.isVisible,
                                              "minimized": window.isMiniaturized, "key": window.isKeyWindow]
                    info["normal_document"] = window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal
                    info["foreground_document"] = GIReaderSession.isDocument(window)
                    info["can_become_main"] = window.canBecomeMain
                    info["excluded_from_menu"] = window.isExcludedFromWindowsMenu
                    info["ignores_mouse"] = window.ignoresMouseEvents
                    info["alpha"] = window.alphaValue
                    info["frame"] = NSStringFromRect(window.frame)
                    info["content_rect"] = NSStringFromRect(window.contentLayoutRect)
                    info["content_bounds"] = window.contentView.map { NSStringFromRect($0.bounds) } ?? "nil"
                    info["content_view"] = window.contentView.map { String(describing: type(of: $0)) } ?? "nil"
                    info["accessibility_subrole"] = String(describing: window.accessibilitySubrole())
                    return info
                }
                windowSnapshots.append(["stage": stage, "reader_open": GIReaderSession.shared.isOpen,
                                        "activation_policy": NSApp.activationPolicy().rawValue, "windows": windows,
                                        "stored_limit": Defaults[.giteeNotchMaximumItems], "layout_limit": GINotchLayout.shared.metrics.limit])
            }
            func capture(_ window: NSWindow, _ name: String) {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), result.deletingLastPathComponent().appendingPathComponent(name + ".png").path]
                try? process.run(); process.waitUntilExit()
            }
            do {
                let reader = GIReaderWindowController.shared
                guard let window = reader.window else { throw NSError(domain: "missing-reader", code: 1) }
                // The ephemeral runner may show its first-run onboarding; hide only in this explicit probe.
                DynamicIslandViewCoordinator.shared.firstLaunch = false
                for other in NSApp.windows where other.identifier?.rawValue == "OnboardingWindow" { other.close() }
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
                try await requestUserReactivation()
                try check(window.isVisible && window.isKeyWindow && NSApp.activationPolicy() == .regular,
                          "return from external application restores reader")
                NSApp.hide(nil); await pause()
                try check(GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .regular, "Cmd-H lifetime remains switchable")
                try await requestUserReactivation(hidden: true)
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

                let layout = GINotchLayout.shared
                GINotchLayout.shared.setMaximumItems(8)
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
                GINotchLayout.shared.setMaximumItems(10)
                try check(layout.metrics.limit == 10 && layout.metrics.visibleCount == 10,
                          "preview limit updates synchronously before another event-loop turn")
                await pause(0.8)
                snapshot("setting-ten")
                try check(Defaults[.giteeNotchMaximumItems] == 10 && layout.metrics.limit == 10 && layout.metrics.visibleCount == 10, "settings limit changes immediately to ten")
                capture(notch, "ux-notch-10")
                let expandedGiteeHeight = notch.frame.height
                coordinator.currentView = .home; await pause(0.8)
                try check(notch.frame.height < expandedGiteeHeight, "leaving Gitee restores Home native height")
                for model in models where model.notchState == .open {
                    try check(model.notchSize.height < expandedGiteeHeight - 60, "leaving Gitee restores original mouse hit area")
                }
                coordinator.currentView = .giteeIssues; await pause(0.8)
                try check(abs(notch.frame.height - expandedGiteeHeight) < 1, "returning to Gitee restores adaptive height")
                store.query = "fixture-no-match"; await pause(0.8); capture(notch, "ux-notch-empty")
                store.clearFilters(); GINotchLayout.shared.setMaximumItems(8); await pause()
                NSApp.appearance = NSAppearance(named: .aqua); capture(notch, "ux-notch-light")
                NSApp.appearance = NSAppearance(named: .darkAqua); capture(notch, "ux-notch-dark")
                NSApp.appearance = nil
                reader.show(); await pause(); capture(window, "ux-reader")
                try check(GIPasteboard.copy(GIStore.demoB.url.absoluteString) && NSPasteboard.general.string(forType: .string) == GIStore.demoB.url.absoluteString,
                          "real pasteboard contains only selected Issue URL")
                try check(store.selectedListID == selected && store.visit?.id == visit, "copying a different row does not navigate")
                try check(!GIPasteboard.copy(String(repeating: "a", count: 2 * 1024 * 1024 + 1)), "copy failure is observable")

                GISettingsNavigation.shared.open(); await pause()
                window.performClose(nil); await pause()
                try check(!GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .regular, "reader close preserves still-open settings")
                SettingsWindowController.shared.window?.performClose(nil); await pause()
                snapshot("last-document-closed")
                try check(!GIReaderSession.shared.isOpen && !window.isVisible && NSApp.activationPolicy() == .accessory,
                          "last document close returns to original accessory mode without resurrecting reader")
                SettingsWindowController.shared.showWindow(); await pause()
                SettingsWindowController.shared.window?.performClose(nil); await pause()
                snapshot("settings-only-closed")
                try check(!window.isVisible && NSApp.activationPolicy() == .accessory, "settings-only use does not reopen reader")
                // Exercise the classifier using real native windows, including an
                // untitled document. A private AppKit identifier or empty title is
                // deliberately not used as the distinction.
                let other = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 180),
                                     styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                other.isReleasedWhenClosed = false
                other.identifier = NSUserInterfaceItemIdentifier("ToolIsle.SyntheticOtherDocument")
                other.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
                other.title = ""
                other.makeKeyAndOrderFront(nil)
                GIReaderSession.shared.restorePolicy(); await pause()
                try check(GIReaderSession.isDocument(other) && NSApp.activationPolicy() == .regular,
                          "a real untitled document retains foreground lifetime")
                other.miniaturize(nil); await pause(0.8)
                GIReaderSession.shared.restorePolicy()
                try check(other.isMiniaturized && NSApp.activationPolicy() == .regular,
                          "a minimized non-reader document retains foreground lifetime")
                other.deminiaturize(nil); await pause()
                other.orderOut(nil); other.close()
                await pause()
                try check(NSApp.activationPolicy() == .accessory,
                          "native close notification restores accessory mode after the last real document")

                let helper = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
                helper.isReleasedWhenClosed = false
                helper.alphaValue = 0
                helper.orderFrontRegardless()
                GIReaderSession.shared.restorePolicy(); await pause()
                try check(!GIReaderSession.isDocument(helper) && NSApp.activationPolicy() == .accessory,
                          "an invisible zero-content helper does not retain foreground lifetime")
                helper.orderOut(nil); helper.close()

                for round in 1...3 {
                    SettingsWindowController.shared.showWindow()
                    SettingsWindowController.shared.window?.performClose(nil)
                    await pause()
                    try check(SettingsWindowController.shared.window?.isVisible == false &&
                              !window.isVisible && !GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .accessory,
                              "same-turn settings open-close cancels delayed focus round \(round)")
                }
                for round in 1...3 {
                    SettingsWindowController.shared.showWindow(); await pause()
                    SettingsWindowController.shared.window?.performClose(nil)
                    SettingsWindowController.shared.showWindow()
                    await pause()
                    try check(SettingsWindowController.shared.window?.isVisible == true &&
                              SettingsWindowController.shared.window?.isKeyWindow == true &&
                              !window.isVisible && !GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .regular,
                              "same-turn settings close-reopen cancels the previous close callback round \(round)")
                    SettingsWindowController.shared.window?.performClose(nil); await pause()
                    try check(NSApp.activationPolicy() == .accessory && !window.isVisible,
                              "rapidly reopened settings still closes to accessory mode round \(round)")
                }
                reader.show(); await pause()
                GISettingsNavigation.shared.open(); await pause()
                SettingsWindowController.shared.window?.performClose(nil)
                window.performClose(nil); await pause()
                try check(!window.isVisible && !GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .accessory,
                          "settings-then-reader close invalidates deferred focus restoration")
                reader.show(); await pause()
                window.miniaturize(nil); await pause(0.8)
                try check(GIReaderSession.shared.reopen(), "queue an explicit reader reopen before close")
                window.close(); await pause(0.8)
                try check(!window.isVisible && !GIReaderSession.shared.isOpen && NSApp.activationPolicy() == .accessory,
                          "reader close cancels a pending minimized-window reopen")
                snapshot("all-negative-lifecycles-complete")
                let info: [String: Any] = ["passed": failures.isEmpty, "checks": checks, "failures": failures, "sizes": sizes, "activation_runs": activations, "window_snapshots": windowSnapshots, "accessibilitySubrole": subrole,
                    "synthetic_data": true, "live_gitee_tested": false, "third_party_alttab_hotkey_tested": false,
                    "updater_testing_argument": ProcessInfo.processInfo.arguments.contains("-SUEnableAutomaticChecks"),
                    "automatic_update_checks_effective": UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks")]
                try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: result)
            } catch {
                let info: [String: Any] = ["passed": false, "error": error.localizedDescription, "checks": checks, "failures": failures, "sizes": sizes, "activation_runs": activations, "window_snapshots": windowSnapshots]
                try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: result)
            }
        }
    }
}
