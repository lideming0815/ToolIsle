// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// A scoped foreground lifetime for the optional reader. Never constructs a reader
/// window when Settings alone is used, and never changes the notch's panel class.
@MainActor
final class GIReaderSession {
    static let shared = GIReaderSession()
    private(set) weak var reader: NSWindow?
    private(set) var isOpen = false
    private var restoreGeneration = 0
    private var restoringWindow = false
    private var reopenPending = false

    func opened(_ window: NSWindow) {
        reader = window
        isOpen = true
        restoreGeneration += 1
        applyPolicy(.regular)
    }
    func closed(_ window: NSWindow) {
        guard reader === window else { return }
        isOpen = false
        restoreGeneration += 1
        reopenPending = false
        restorePolicy(excluding: window)
        let generation = restoreGeneration
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, generation == self.restoreGeneration, !self.isOpen else { return }
            self.restorePolicy(excluding: window)
        }
    }
    /// Settings/onboarding/modal helpers must not hide a still-open reading session
    /// from Cmd-Tab. Minimized or app-hidden readers still own this lifetime.
    func restorePolicy(excluding closing: NSWindow? = nil) {
        let otherDocument = NSApp.windows.contains { window in
            window !== closing && window !== reader && Self.isDocument(window) &&
            (window.isVisible || window.isMiniaturized)
        }
        let requiresForeground = isOpen || otherDocument
        applyPolicy(requiresForeground ? .regular : .accessory)
        // Preserve Atoll's original last-window handoff without deactivating
        // an open (including minimized or hidden) reader or another document.
        if !requiresForeground && NSApp.isActive { NSApp.deactivate() }
    }
    func settingsClosed(_ settings: NSWindow?) {
        restorePolicy(excluding: settings)
        restoreGeneration += 1
        let generation = restoreGeneration
        let userIsInApplication = NSApp.isActive
        // willClose fires before AppKit finishes ordering. Revalidate on the next turn.
        DispatchQueue.main.async { [weak self, weak settings] in
            guard let self, generation == self.restoreGeneration else { return }
            // Reconcile after willClose and any final key-window callbacks finish.
            self.restorePolicy(excluding: settings)
            guard userIsInApplication, NSApp.isActive, self.isOpen, let window = self.reader,
                  window.isVisible, !window.isMiniaturized else { return }
            if let key = NSApp.keyWindow, key !== settings, key !== window, Self.isDocument(key) { return }
            self.focus(window, restoreMinimized: false)
        }
    }
    func applicationBecameActive() {
        guard !restoringWindow, !reopenPending, isOpen, let window = reader,
              window.isVisible, !window.isMiniaturized else { return }
        // Let another document (including Settings) retain focus. No activation loop.
        if let key = NSApp.keyWindow, key !== window, Self.isDocument(key) { return }
        focus(window, restoreMinimized: false)
    }
    @discardableResult func reopen() -> Bool {
        guard isOpen, let window = reader else { return false }
        guard !restoringWindow, !reopenPending else { return true }
        applyPolicy(.regular)
        reopenPending = true
        let generation = restoreGeneration
        // AppKit may request reopen while completing a minimize/activation event.
        // Complete that event before changing native window state again.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else { return }
            self.reopenPending = false
            guard generation == self.restoreGeneration, self.isOpen,
                  let window, self.reader === window else { return }
            self.focus(window, restoreMinimized: true)
        }
        return true
    }
    private func focus(_ window: NSWindow, restoreMinimized: Bool) {
        guard !restoringWindow else { return }
        restoringWindow = true
        defer { restoringWindow = false }
        if restoreMinimized {
            if NSApp.isHidden { NSApp.unhide(nil) }
            if window.isMiniaturized { window.deminiaturize(nil) }
        }
        guard !window.isMiniaturized else { return }
        if !window.isMainWindow { window.makeMain() }
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
    }
    private func applyPolicy(_ policy: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
    /// A titled AppKit helper is not necessarily a user-facing document. In
    /// particular, invisible/zero-content helper windows must not keep the Dock
    /// lifetime alive after Settings and the reader have both closed. Do not
    /// identify helpers by private class names, identifiers or an empty title:
    /// a real untitled window and a minimized document still count.
    static func isDocument(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled), !(window is NSPanel),
              window.level == .normal, window.canBecomeMain,
              !window.isExcludedFromWindowsMenu, !window.ignoresMouseEvents else { return false }
        if window.isMiniaturized { return true }
        guard let content = window.contentView else { return false }
        let frame = window.frame.size
        let body = content.bounds.size
        let layout = window.contentLayoutRect.size
        return layout.width > 1 && layout.height > 1 && window.alphaValue > 0 && frame.width.isFinite && frame.height.isFinite &&
            frame.width > 1 && frame.height > 1 && body.width.isFinite && body.height.isFinite &&
            body.width > 1 && body.height > 1
    }
}
