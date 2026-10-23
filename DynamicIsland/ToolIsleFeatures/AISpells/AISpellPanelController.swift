/*
 * ToolIsle — AI Spells
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import AppKit
import ApplicationServices
import Carbon
import Defaults
import SwiftUI

/// Owns the quick-use window and the application captured before it takes focus.
/// Clipboard history is deliberately not involved in the library's lifecycle.
@MainActor
final class AISpellPanelController: NSObject, NSWindowDelegate {
    static let shared = AISpellPanelController()

    private var panel: AISpellPanel?
    private var returnApplication: NSRunningApplication?
    private var pendingAction: Task<Void, Never>?

    func show() {
        guard Defaults[.enableAISpells] else { return }
        pendingAction?.cancel()
        pendingAction = nil

        if panel?.isVisible != true {
            let frontmost = NSWorkspace.shared.frontmostApplication
            returnApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? nil : frontmost
        }

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.attachedSheet?.makeKeyAndOrderFront(nil)
            return
        }

        let panel = AISpellPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI 咒语"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 660, height: 440)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss(returnFocus: true) }
        panel.contentView = NSHostingView(rootView: AISpellsView(
            store: AISpellStore.shared,
            onCopy: { [weak self] in self?.copy($0) },
            onPaste: { [weak self] in self?.paste($0) },
            onClose: { [weak self] in self?.dismiss(returnFocus: true) }
        ))

        // Open on the display the user is currently working on, including a
        // secondary/full-screen Space, without changing the notch's geometry.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            let size = NSSize(width: min(820, bounds.width), height: min(560, bounds.height))
            panel.setFrame(NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            ), display: false)
        }

        ScreenCaptureVisibilityManager.shared.register(panel, scope: .panelsOnly)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            // A shortcut while editing must not discard an unsaved sheet.
            guard panel?.attachedSheet == nil else { return }
            dismiss(returnFocus: true)
        } else {
            show()
        }
    }

    /// Used on feature disable and screen lock; never reactivate another app.
    func hide() {
        pendingAction?.cancel()
        pendingAction = nil
        panel?.attachedSheet?.orderOut(nil)
        panel?.orderOut(nil)
        returnApplication = nil
        // Keep the view alive: locking the screen must not discard an editor draft.
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.attachedSheet == nil else { return false }
        dismiss(returnFocus: true)
        return false
    }

    private func dismiss(returnFocus: Bool, cancelAction: Bool = true) {
        if cancelAction {
            pendingAction?.cancel()
            pendingAction = nil
        }
        if let panel {
            ScreenCaptureVisibilityManager.shared.unregister(panel)
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
        if returnFocus, let application = returnApplication, !application.isTerminated {
            application.activate(options: .activateIgnoringOtherApps)
        }
        returnApplication = nil
    }

    private func copy(_ spell: AISpell) {
        use(spell, insertIntoApplication: false)
    }

    private func paste(_ spell: AISpell) {
        use(spell, insertIntoApplication: true)
    }

    private func use(_ spell: AISpell, insertIntoApplication: Bool) {
        // Ignore autorepeat while this action is already waiting for key release.
        guard pendingAction == nil, let actionPanel = panel,
              writeClipboard(spell.content) else { return }
        let application = returnApplication
        let pasteboardChange = NSPasteboard.general.changeCount
        var triggerKeys: Set<CGKeyCode> = [CGKeyCode(kVK_Return), CGKeyCode(kVK_ANSI_KeypadEnter)]
        if let event = NSApp.currentEvent, event.type == .keyDown || event.type == .keyUp {
            triggerKeys.insert(event.keyCode)
        }

        pendingAction = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // A cancelled task must not clear the reference to a newer action.
                if !Task.isCancelled { self.pendingAction = nil }
            }

            // Keep focus here until physical keys are released: closing on keyDown
            // can otherwise send a repeated Return into the original chat window.
            var keysReleased = false
            for _ in 0..<100 {
                guard !Task.isCancelled, Defaults[.enableAISpells],
                      NSPasteboard.general.changeCount == pasteboardChange,
                      self.panel === actionPanel, actionPanel.isVisible,
                      actionPanel.attachedSheet == nil, actionPanel.isKeyWindow,
                      NSApp.isActive else { return }
                if self.triggerKeysAreReleased(triggerKeys) {
                    keysReleased = true
                    break
                }
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { return }
            }
            // The final sleep may have coincided with a lock, sheet or app switch.
            guard !Task.isCancelled, Defaults[.enableAISpells],
                  NSPasteboard.general.changeCount == pasteboardChange,
                  self.panel === actionPanel, actionPanel.isVisible,
                  actionPanel.attachedSheet == nil, actionPanel.isKeyWindow,
                  NSApp.isActive else { return }
            guard keysReleased else {
                self.explain("内容已复制", detail: "快捷键尚未完全释放，未切换应用。请松开按键后重试，或手动粘贴。")
                return
            }
            guard insertIntoApplication else {
                self.dismiss(returnFocus: true, cancelAction: false)
                return
            }
            guard let application, !application.isTerminated else {
                self.explain("内容已复制", detail: "没有可返回的原应用。请切换到目标输入框后粘贴，或从目标应用中使用全局快捷键呼出 AI 咒语。")
                return
            }
            guard AXIsProcessTrusted() else {
                let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "BangsBuddy"
                self.explain(
                    "内容已复制；自动粘贴需要辅助功能权限",
                    detail: "请在系统设置 → 隐私与安全性 → 辅助功能中允许 \(appName)。你也可以直接切回目标应用按 ⌘V。",
                    offerAccessibilitySettings: true
                )
                return
            }

            self.dismiss(returnFocus: true, cancelAction: false)
            // Wait for activation before sending the paste to the captured app.
            // Never overwrite a newer clipboard value or paste into a different app.
            for _ in 0..<20 {
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                guard Defaults[.enableAISpells],
                      NSPasteboard.general.changeCount == pasteboardChange else { return }
                guard !application.isTerminated else {
                    self.explain("内容已复制", detail: "原应用已经退出，未执行自动粘贴。你可以在其他输入框按 ⌘V。")
                    return
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
                      self.triggerKeysAreReleased(triggerKeys) else { continue }

                guard AXIsProcessTrusted(),
                      let source = CGEventSource(stateID: .combinedSessionState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                    self.explain("内容已复制", detail: "未能执行自动粘贴，请在目标输入框按 ⌘V。")
                    return
                }
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(application.processIdentifier)
                up.postToPid(application.processIdentifier)
                // No Return event: inserting a spell must never submit a message.
                return
            }
            guard !Task.isCancelled else { return }
            self.explain("内容已复制", detail: "原应用未能获得焦点，或快捷键仍未释放。请在目标输入框按 ⌘V。")
        }
    }

    private func triggerKeysAreReleased(_ keyCodes: Set<CGKeyCode>) -> Bool {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .control, .option, .shift])
        return modifiers.isEmpty && keyCodes.allSatisfy {
            !CGEventSource.keyState(.combinedSessionState, key: $0)
        }
    }

    private func writeClipboard(_ content: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(content, forType: .string) else {
            explain("无法复制咒语", detail: "系统剪切板暂时不可用，请重试。咒语库中的内容未改变。")
            return false
        }
        return true
    }

    private func explain(_ title: String, detail: String, offerAccessibilitySettings: Bool = false) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if offerAccessibilitySettings { alert.addButton(withTitle: "打开辅助功能设置") }
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if offerAccessibilitySettings, response == .alertSecondButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        if let panel, panel.isVisible, panel.attachedSheet == nil {
            alert.beginSheetModal(for: panel, completionHandler: completion)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            completion(alert.runModal())
        }
    }
}

private final class AISpellPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        onCancel?()
    }
}
