// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import Defaults

extension Defaults.Keys {
    static let giteeNotchMaximumItems = Key<Int>("toolisle.gitee.notchMaximumItems", default: GINotchMetrics.defaultLimit)
}

@MainActor
final class GINotchLayout: ObservableObject {
    static let shared = GINotchLayout()
    @Published private(set) var metrics = GINotchMetrics(count: 0, limit: GINotchMetrics.defaultLimit)
    private var subscriptions = Set<AnyCancellable>()
    private var pending: DispatchWorkItem?
    private init() {
        // Coalesce @Published's willSet notifications; never start authentication or network work.
        GIStore.shared.objectWillChange.sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        Defaults.publisher(.giteeNotchMaximumItems).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        refreshNow()
    }
    /// The Settings binding and native regression exercise the same action.
    /// Do not rely on a delayed UserDefaults observation to resize an open notch.
    func setMaximumItems(_ value: Int) {
        Defaults[.giteeNotchMaximumItems] = GINotchMetrics.clamp(value)
        pending?.cancel()
        refreshNow()
    }
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshNow() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }
    func refreshNow() {
        let store = GIStore.shared
        let value = GINotchMetrics(count: store.filteredItems.count,
                                  limit: Defaults[.giteeNotchMaximumItems],
                                  partialFailure: !store.items.isEmpty && !store.listFailures.isEmpty)
        if value != metrics { metrics = value }
    }
    func size(base: CGSize, screenName: String?) -> CGSize {
        // Do not use the reader's focused screen to position/size the physical notch.
        let screen = NSScreen.screens.first { $0.localizedName == screenName } ?? NSScreen.screens.first
        return size(base: base, screen: screen)
    }
    func size(base: CGSize, screen: NSScreen?) -> CGSize {
        CGSize(width: base.width, height: metrics.notchHeight(availableHeight: screen?.visibleFrame.height ?? 720,
                                                            minimumHeight: base.height))
    }
    func contentHeight(screenName: String?) -> CGFloat {
        size(base: CGSize(width: 0, height: 200), screenName: screenName).height - GINotchMetrics.hostInset
    }
}
