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

    func opened(_ window: NSWindow) {
        reader = window
        isOpen = true
        restoreGeneration += 1
        NSApp.setActivationPolicy(.regular)
    }
    func closed(_ window: NSWindow) {
        guard reader === window else { return }
        isOpen = false
        restoreGeneration += 1
        restorePolicy(excluding: window)
    }
    /// Settings/onboarding/modal helpers must not hide a still-open reading session
    /// from Cmd-Tab. Minimized or app-hidden readers still own this lifetime.
    func restorePolicy(excluding closing: NSWindow? = nil) {
        let otherDocument = NSApp.windows.contains { window in
            window !== closing && window !== reader && Self.isDocument(window) &&
            (window.isVisible || window.isMiniaturized)
        }
        NSApp.setActivationPolicy(isOpen || otherDocument ? .regular : .accessory)
    }
    func settingsClosed(_ settings: NSWindow?) {
        restorePolicy(excluding: settings)
        restoreGeneration += 1
        let generation = restoreGeneration
        let userIsInApplication = NSApp.isActive
        // willClose fires before AppKit finishes ordering. Revalidate on the next turn.
        DispatchQueue.main.async { [weak self, weak settings] in
            guard let self, generation == self.restoreGeneration, userIsInApplication,
                  NSApp.isActive, self.isOpen, let window = self.reader,
                  window.isVisible, !window.isMiniaturized else { return }
            if let key = NSApp.keyWindow, key !== settings, key !== window, Self.isDocument(key) { return }
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
        }
    }
    func applicationBecameActive() {
        guard isOpen, let window = reader, window.isVisible, !window.isMiniaturized else { return }
        // Let another document (including Settings) retain focus. No activation loop.
        if let key = NSApp.keyWindow, key !== window, Self.isDocument(key) { return }
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
    }
    @discardableResult func reopen() -> Bool {
        guard isOpen, let window = reader else { return false }
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        return true
    }
    private static func isDocument(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal
    }
}
