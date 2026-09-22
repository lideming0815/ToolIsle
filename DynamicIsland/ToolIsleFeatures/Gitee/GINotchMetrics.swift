// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Shared by the SwiftUI surface, native window and mouse hit area. Points, not pixels.
struct GINotchMetrics: Equatable {
    static let defaultLimit = 8
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 4
    static let chromeHeight: CGFloat = 102
    static let hostInset: CGFloat = 60
    let count: Int
    let limit: Int
    let partialFailure: Bool
    init(count: Int, limit: Int, partialFailure: Bool = false) {
        self.count = max(0, count)
        self.limit = Self.clamp(limit)
        self.partialFailure = partialFailure
    }
    static func clamp(_ value: Int) -> Int { min(10, max(1, value)) }
    var visibleCount: Int { min(count, limit) }
    var preferredContentHeight: CGFloat {
        let rows = visibleCount == 0 ? 104 : CGFloat(visibleCount) * Self.rowHeight + CGFloat(visibleCount - 1) * Self.rowSpacing
        return Self.chromeHeight + rows + (partialFailure ? 24 : 0)
    }
    func notchHeight(availableHeight: CGFloat, minimumHeight: CGFloat = 200) -> CGFloat {
        let available = availableHeight.isFinite && availableHeight > 0 ? availableHeight : 720
        let cap = max(164, min(floor(available * 0.72), available - 32))
        return min(cap, max(minimumHeight, preferredContentHeight + Self.hostInset)).rounded()
    }
}
