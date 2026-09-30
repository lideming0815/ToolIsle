// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct GILabelFacet: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
    let color: String?
    let repositories: Set<String>
}
struct GIProjectGroup: Identifiable {
    let id: String
    let title: String
    let path: String
    let items: [GIListItem]
}

enum GIListPresentation {
    // Show All first, followed by the three common states. Selection defaults are independent of display order.
    static let states = GIStateProjection.standard
    static func stateTitle(_ state: String) -> String { GIStateProjection.title(state) }
    static func candidates(_ items: [GIListItem], state: String, query: String) -> [GIListItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter {
            GIStateProjection.matches($0.issue, filter: state) &&
            (q.isEmpty || $0.issue.title.localizedCaseInsensitiveContains(q) || $0.route.label.localizedCaseInsensitiveContains(q) || $0.route.repositoryURL.localizedCaseInsensitiveContains(q))
        }
    }
    static func filter(_ candidates: [GIListItem], labels: Set<String>) -> [GIListItem] {
        guard !labels.isEmpty else { return candidates }
        return candidates.filter { item in item.issue.visibleLabels.contains { labels.contains($0.key) } }
    }
    static func facets(_ candidates: [GIListItem]) -> [GILabelFacet] {
        var occurrences: [String: Set<GIIssueRoute>] = [:]
        var repos: [String: Set<String>] = [:]
        var colors: [String: Set<String>] = [:]
        for item in candidates {
            for label in item.issue.visibleLabels {
                occurrences[label.key, default: []].insert(item.route)
                repos[label.key, default: []].insert(item.route.repositoryURL)
                colors[label.key, default: []].insert(label.hexColor ?? "")
            }
        }
        return occurrences.map { name, routes in
            let palette = colors[name] ?? []
            return GILabelFacet(name: name, count: routes.count,
                                color: palette.count == 1 ? palette.first.flatMap { $0.isEmpty ? nil : $0 } : nil,
                                repositories: repos[name] ?? [])
        }.sorted { a, b in a.count != b.count ? a.count > b.count : a.name < b.name }
    }
    static func groups(_ items: [GIListItem], repositories: [GIRepository]) -> [GIProjectGroup] {
        let bucket = Dictionary(grouping: items, by: { $0.route.repositoryURL })
        let metadata = Dictionary(repositories.map { ($0.canonicalURL, $0) }, uniquingKeysWith: { first, _ in first })
        let keys = Set(metadata.keys).union(bucket.keys).sorted()
        return keys.map { url in
            GIProjectGroup(id: url, title: url, path: metadata[url]?.path ?? bucket[url]?.first?.route.repository ?? url,
                           items: (bucket[url] ?? []).sorted(by: newer))
        }
    }
    static func newer(_ a: GIListItem, _ b: GIListItem) -> Bool {
        let left = timestamp(a.issue.updated_at), right = timestamp(b.issue.updated_at)
        if left != right { return left > right }
        if a.route.repositoryURL != b.route.repositoryURL { return a.route.repositoryURL < b.route.repositoryURL }
        return a.route.number < b.route.number
    }
    static func timestamp(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) { return date }
        parser.formatOptions.insert(.withFractionalSeconds)
        return parser.date(from: value) ?? .distantPast
    }

}

/// Shared deterministic packing rules for the actual SwiftUI trays and tests.
/// Reserves an overflow button BEFORE packing: no clipped '...' and never a third row.
enum GIChipPacking {
    struct Plan {
        let rows: [[Int]]
        let hidden: Int
    }
    static func pack(widths: [Double], available: Double, maxRows: Int, spacing: Double = 5, overflow: Double = 32) -> Plan {
        let width = available.isFinite ? max(1, available) : 220
        let limit = max(1, maxRows)
        func rows(for count: Int, withOverflow: Bool) -> [[Int]]? {
            var rows: [[Int]] = [[]], used = 0.0
            let all = Array(0..<count) + (withOverflow ? [-1] : [])
            for index in all {
                let size = min(width, max(1, index == -1 ? overflow : widths[index]))
                if !rows[rows.count - 1].isEmpty && used + spacing + size > width + 0.01 {
                    guard rows.count < limit else { return nil }
                    rows.append([]); used = 0
                }
                used += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size
                rows[rows.count - 1].append(index)
            }
            return rows
        }
        if let result = rows(for: widths.count, withOverflow: false) { return Plan(rows: result, hidden: 0) }
        // At most a few dozen chips fit two rows; stop at first overflow instead of quadratic backtracking.
        var visible = 0
        while visible < widths.count, rows(for: visible + 1, withOverflow: true) != nil { visible += 1 }
        return Plan(rows: rows(for: visible, withOverflow: true) ?? [[-1]], hidden: widths.count - visible)
    }
}


/// Text measurement and horizontal padding only; selected and unselected filters
/// use identical geometry, with no invisible checkbox or checkmark reservation.
enum GIChipFaceMetrics {
    static func width(textWidth: Double, available: Double, selectable: Bool,
                      compact: Bool, state: Bool) -> Double {
        let extra: Double = selectable ? (compact ? 12 : 16) : (state ? 27 : 16)
        return min(max(0, available), min(158, ceil(max(0, textWidth)) + extra))
    }
}
