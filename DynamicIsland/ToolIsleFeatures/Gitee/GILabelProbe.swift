// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Opt-in synthetic native UI probe; no network, credentials or production preference writes.
@MainActor enum GILabelProbe {
    static var started = false
    static var trays: [[String: Any]] = []
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
            func check(_ value: Bool, _ name: String) { if value { passed.append(name) } else { failed.append(name) } }
            func pause() async { try? await Task.sleep(nanoseconds: 800_000_000) }
            let output = URL(fileURLWithPath: path)
            func capture(_ window: NSWindow, _ name: String) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.deletingLastPathComponent().appendingPathComponent(name + ".png").path]
                try? p.run(); p.waitUntilExit()
            }
            let store = GIStore.shared
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
                    window.setContentSize(NSSize(width: 960, height: 740)); await pause()
                    capture(window, dark ? "labels-reader-dark" : "labels-reader-light")
                    let filterWindow = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 260, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    filterWindow.isReleasedWhenClosed = false
                    filterWindow.contentView = NSHostingView(rootView: GIFilterBar().frame(width: 260).frame(maxHeight: .infinity, alignment: .top))
                    filterWindow.makeKeyAndOrderFront(nil); await pause()
                    capture(filterWindow, dark ? "labels-filter-260-dark" : "labels-filter-260-light")
                    filterWindow.close()
                }
                let picker = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 338, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                picker.isReleasedWhenClosed = false
                picker.contentView = NSHostingView(rootView: GILabelPicker())
                picker.makeKeyAndOrderFront(nil); await pause(); capture(picker, "labels-picker"); picker.close()
                store.stateFilter = "all"; await pause(); capture(window, "labels-state-from-overflow")
            } else { failed.append("reader exists") }
            let stateTrays = trays.filter { $0["kind"] as? String == "status" && ($0["width"] as? CGFloat ?? 0) >= 236 }
            check(!stateTrays.isEmpty, "actual native status geometry captured")
            check(stateTrays.allSatisfy { $0["row_count"] as? Int == 1 && Array(($0["visible"] as? [String] ?? []).prefix(3)) == Array(GIListPresentation.states.prefix(3)) }, "actual one-row status keeps three priority states")
            check(trays.filter { $0["kind"] as? String == "labels" }.allSatisfy { ($0["row_count"] as? Int ?? 3) <= 2 }, "native label trays never exceed two rows")
            check(trays.contains { $0["kind"] as? String == "labels" && $0["has_overflow"] as? Bool == true }, "large label range exposes overflow")
            let report: [String: Any] = ["passed": failed.isEmpty, "checks": passed, "failures": failed, "trays": trays,
                "synthetic_data": true, "live_gitee_tested": false, "third_party_alttab_hotkey_tested": false]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }
    }
}
