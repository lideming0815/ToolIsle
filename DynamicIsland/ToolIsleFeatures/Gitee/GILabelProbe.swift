// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import WebKit

/// Opt-in synthetic native UI probe; no network, credentials or production preference writes.
@MainActor enum GILabelProbe {
    static var started = false
    static var trays: [[String: Any]] = []
    static var searches: [[String: Any]] = []
    static func recordSearch(_ query: String, names: [String]) {
        guard started, ProcessInfo.processInfo.arguments.contains("--gitee-label-probe") else { return }
        searches.append(["query": query, "names": names])
    }
    static func record(_ tags: [GITagSpec], width: CGFloat, rows: [[Int]], maximum: Int) {
        guard started, ProcessInfo.processInfo.arguments.contains("--gitee-label-probe") else { return }
        let kind = tags.first?.id == "unfinished" ? "status" : (tags.first?.id == "state" ? "issue" : "labels")
        trays.append(["kind": kind, "width": width, "row_count": rows.count, "max_rows": maximum,
                      "visible": rows.flatMap { $0 }.filter { $0 >= 0 }.map { tags[$0].id },
                      "has_overflow": rows.flatMap { $0 }.contains(-1)])
    }
    static func run() {
        guard !started, GIStore.shared.demoMode, ProcessInfo.processInfo.arguments.contains("--gitee-label-probe"),
              let path = ProcessInfo.processInfo.environment["TOOLISLE_LABEL_RESULT"] else { return }
        started = true
        Task { @MainActor in
            var passed: [String] = [], failed: [String] = []
            var htmlChecks: [[String: Any]] = []
            func check(_ value: Bool, _ name: String) { if value { passed.append(name) } else { failed.append(name) } }
            func pause() async { try? await Task.sleep(nanoseconds: 800_000_000) }
            let output = URL(fileURLWithPath: path)
            func capture(_ window: NSWindow, _ name: String) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.deletingLastPathComponent().appendingPathComponent(name + ".png").path]
                try? p.run(); p.waitUntilExit()
            }
            @MainActor func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap { descendants($0) }
            }
            @MainActor func waitForReading(_ window: NSWindow) async -> Bool {
                for _ in 0..<40 {
                    if let root = window.contentView,
                       let web = descendants(root).compactMap({ $0 as? WKWebView }).first,
                       let title = try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent || ''") as? String,
                       !title.isEmpty {
                        htmlChecks.append(["title": title, "bounds": NSStringFromRect(web.bounds)])
                        return true
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                return false
            }
            let store = GIStore.shared
            // Let the initial NSHostingView / WKWebView finish mounting before changing fixtures.
            await pause()
            if let window = GIReaderWindowController.shared.window {
                check(await waitForReading(window), "initial real WebKit body is visible")
            }
            store.installLabelFixtures(); store.clearFilters()
            let visit = store.visit?.id, selection = store.selectedListID
            let labels = store.labelFacets.map(\.name), allCount = store.filteredItems.count
            check(labels.count > 100, "over 100 actual model labels")
            store.repositoryFilter = "legacy/hidden-project"
            check(store.filteredItems.count == allCount, "legacy project filter cannot hide groups")
            store.toggleLabel("bug"); check(store.filteredItems.count == 6, "label matches expected rows")
            check(store.labelFacets.map(\.name) == labels, "label choices do not disappear after selecting label")
            store.toggleLabel("文档"); check(store.filteredItems.count == 12, "multiple labels combine with OR")
            store.clearFilters()
            let group = store.issueGroups[0]
            store.setProjectExpanded(group.id, expanded: false)
            check(store.filteredItems.count == allCount && store.labelFacets.map(\.name) == labels, "collapse is display-only")
            check(store.collapsedProjects.contains(group.id), "group collapsed")
            store.expandMatchingProjects(); check(store.collapsedProjects.isEmpty, "expand matching groups")
            store.toggleLabel("current-scope-missing")
            check(store.filteredItems.isEmpty && store.selectedLabels.contains("current-scope-missing"), "unavailable selection remains explicitly removable")
            store.clearFilters()
            check(store.visit?.id == visit && store.selectedListID == selection, "group and filter actions preserve reading history")
            if let window = GIReaderWindowController.shared.window {
                for dark in [false, true] {
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    store.stateFilter = "unfinished"
                    // Restore the normal reading window after all filters / groups have changed.
                    GIReaderWindowController.shared.show()
                    await pause()
                    check(await waitForReading(window), "reading body survives filter changes in \(dark ? "dark" : "light") appearance")
                    capture(window, dark ? "labels-reader-dark" : "labels-reader-light")
                    for sidebar in [260, 320, 380] {
                        let filterWindow = NSWindow(contentRect: NSRect(x: 150, y: 150, width: CGFloat(sidebar), height: 330), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                        filterWindow.isReleasedWhenClosed = false
                        filterWindow.contentView = NSHostingView(rootView: GIFilterBar().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
                        let start = trays.count
                        filterWindow.makeKeyAndOrderFront(nil); await pause()
                        let expected = Double(sidebar - 24) // GIFilterBar's horizontal padding, not a guessed screen width.
                        let status = Array(trays.dropFirst(start)).filter {
                            $0["kind"] as? String == "status" && abs(($0["width"] as? Double ?? 0) - expected) < 1
                        }
                        check(!status.isEmpty, "measured status geometry at \(sidebar)pt in \(dark ? "dark" : "light")")
                        check(!status.isEmpty && status.allSatisfy {
                            $0["row_count"] as? Int == 1 && Array(($0["visible"] as? [String] ?? []).prefix(3)) == Array(GIListPresentation.states.prefix(3))
                        }, "three priority states stay in one row at \(sidebar)pt in \(dark ? "dark" : "light")")
                        capture(filterWindow, "labels-filter-\(sidebar)-\(dark ? "dark" : "light")")
                        // Resize the very same hosting instance rather than only recreating it.
                        if sidebar == 260 {
                            let before = trays.count
                            filterWindow.setContentSize(NSSize(width: 380, height: 330)); await pause()
                            check(trays.dropFirst(before).contains { $0["kind"] as? String == "status" && abs(($0["width"] as? Double ?? 0) - 356) < 1 }, "live resize measures expanded width in \(dark ? "dark" : "light")")
                            filterWindow.setContentSize(NSSize(width: 260, height: 330)); await pause()
                        }
                        filterWindow.close()
                    }
                }
                let picker = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 338, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                picker.isReleasedWhenClosed = false
                picker.contentView = NSHostingView(rootView: GILabelPicker())
                picker.makeKeyAndOrderFront(nil); await pause(); capture(picker, "labels-picker")
                if let root = picker.contentView,
                   let input = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.placeholderString == "搜索当前范围的标签" }) {
                    input.selectText(nil)
                    if let editor = input.currentEditor() as? NSTextView {
                        editor.selectAll(nil)
                        editor.insertText("模块标签-120", replacementRange: NSRange(location: NSNotFound, length: 0))
                        await pause()
                        check(searches.contains { $0["query"] as? String == "模块标签-120" && $0["names"] as? [String] == ["模块标签-120"] }, "native label search narrows large candidate range")
                        check(store.query.isEmpty, "label picker search does not modify Issue search")
                        capture(picker, "labels-picker-search")
                    } else { failed.append("native label search editor exists") }
                } else { failed.append("native label search field exists") }
                picker.close()
                GIReaderWindowController.shared.show()
                store.setProjectExpanded(store.issueGroups[0].id, expanded: false); await pause()
                capture(window, "labels-project-collapsed")
                check(store.visit?.id == visit && store.selectedListID == selection, "rendered group collapse preserves current reading")
                store.expandMatchingProjects()

                store.stateFilter = "all"; await pause(); capture(window, "labels-state-from-overflow")
            } else { failed.append("reader exists") }
            let stateTrays = trays.filter { $0["kind"] as? String == "status" && ($0["width"] as? CGFloat ?? 0) >= 236 }
            check(!stateTrays.isEmpty, "actual native status geometry captured")
            check(!stateTrays.isEmpty && stateTrays.allSatisfy { $0["row_count"] as? Int == 1 && Array(($0["visible"] as? [String] ?? []).prefix(3)) == Array(GIListPresentation.states.prefix(3)) }, "actual one-row status keeps three priority states")
            let labelTrays = trays.filter { $0["kind"] as? String == "labels" }
            check(!labelTrays.isEmpty && labelTrays.allSatisfy { ($0["row_count"] as? Int ?? 3) <= 2 }, "native label trays never exceed two rows")
            check(trays.contains { $0["kind"] as? String == "labels" && $0["has_overflow"] as? Bool == true }, "large label range exposes overflow")
            let report: [String: Any] = ["passed": failed.isEmpty, "checks": passed, "failures": failed, "trays": trays, "searches": searches, "reading_checks": htmlChecks,
                "synthetic_data": true, "live_gitee_tested": false, "third_party_alttab_hotkey_tested": false]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
}
