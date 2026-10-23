/*
 * ToolIsle — AI Spells
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import AppKit
import ApplicationServices
import Carbon
import Combine
import Defaults
import SwiftUI

/// Keeps retrieval nonactivating, and isolates editing from the original input's focus.
@MainActor
final class AISpellPanelController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AISpellPanelController()

    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var lastInsertionStatus = "尚未使用插入"

    private struct Target {
        let application: NSRunningApplication
        let focusedElement: AXUIElement?
    }

    private let quickState = AISpellQuickState()
    private var quickPanel: AISpellPanel?
    private var managerPanel: AISpellPanel?
    private var quickTarget: Target?
    private var managerTarget: Target?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var pendingAction: Task<Void, Never>?
    private var actionID: UUID?
    private var lastTargetName: String?

    /// Install at launch, so a menu/settings entry can return to the last external app.
    func startTrackingApplications() {
        guard activationObserver == nil else { return }
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rememberExternalApplication(application)
                if application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                   let panel = self.quickPanel, panel.isVisible,
                   application.processIdentifier != self.quickTarget?.application.processIdentifier {
                    self.dismiss(panel, returnFocus: false)
                }
            }
        }
    }

    func show() {
        guard Defaults[.enableAISpells] else { return }
        startTrackingApplications()
        // Preserve an unsaved editor even if the global shortcut is pressed.
        if let managerPanel, managerPanel.attachedSheet != nil {
            showManager()
            return
        }
        if let quickPanel, quickPanel.isVisible {
            quickPanel.makeKeyAndOrderFront(nil)
            return
        }
        cancelPendingAction()
        refreshAccessibilityStatus()
        quickTarget = captureTarget()
        showQuickPanel(resetFeedback: true)
    }

    func showManager() {
        guard Defaults[.enableAISpells] else { return }
        startTrackingApplications()
        let target = quickTarget ?? captureTarget()
        if let quickPanel { dismiss(quickPanel, returnFocus: false) }
        cancelPendingAction()
        if let managerPanel {
            // Reusing the view preserves drafts, but its insertion target belongs
            // to this invocation (the user may have switched to another app).
            managerTarget = target
            NSApp.activate(ignoringOtherApps: true)
            managerPanel.makeKeyAndOrderFront(nil)
            managerPanel.attachedSheet?.makeKeyAndOrderFront(nil)
            return
        }
        managerTarget = target
        let panel = AISpellPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        configure(panel, title: "管理 AI 咒语")
        panel.titlebarAppearsTransparent = true
        panel.minSize = NSSize(width: 660, height: 440)
        panel.contentView = FirstMouseHostingView(rootView: AISpellsView(
            store: AISpellStore.shared,
            onCopy: { [weak self, weak panel] in self?.use($0, insert: false, from: panel) },
            onPaste: { [weak self, weak panel] in self?.use($0, insert: true, from: panel) },
            onClose: { [weak self, weak panel] in
                if let panel { self?.dismiss(panel, returnFocus: true) }
            }
        ))
        position(panel, size: NSSize(width: 820, height: 560))
        managerPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if let quickPanel, quickPanel.isVisible {
            dismiss(quickPanel, returnFocus: true)
        } else {
            show()
        }
    }

    /// Feature disable / screen lock must not reactivate another application or lose drafts.
    func hide() {
        cancelPendingAction()
        if let quickPanel { dismiss(quickPanel, returnFocus: false) }
        managerPanel?.attachedSheet?.orderOut(nil)
        managerPanel?.orderOut(nil)
        quickTarget = nil
        managerTarget = nil
    }

    func refreshAccessibilityStatus() {
        // Read the running process's actual grant, not the UI-test permission fixture.
        accessibilityGranted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func copyDiagnosticInformation() {
        refreshAccessibilityStatus()
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        // Deliberately exclude prompt bodies, clipboard values, and input field contents.
        let information = """
        BangsBuddy AI Spells / clipboard-panel-v2
        Version: \(version) (\(build))
        Bundle: \(bundle.bundleIdentifier ?? "?")
        Application: \(bundle.bundleURL.path)
        Accessibility: \(accessibilityGranted)
        Last target: \(lastTargetName ?? "none")
        Last action: \(lastInsertionStatus)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(information, forType: .string)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.attachedSheet == nil else { return false }
        dismiss(sender, returnFocus: true)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === quickPanel else { return }
        // Clicking elsewhere dismisses without bringing an old app back to the front.
        dismiss(window, returnFocus: false)
    }

    private func showQuickPanel(resetFeedback: Bool) {
        if resetFeedback {
            quickState.message = nil
            quickState.offersPermissionSettings = false
        }
        quickState.isBusy = false
        quickState.targetName = quickTarget?.application.localizedName
        let panel = AISpellPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configure(panel, title: "AI 咒语")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = FirstMouseHostingView(rootView: AISpellQuickView(
            store: AISpellStore.shared, state: quickState,
            onPaste: { [weak self, weak panel] in self?.use($0, insert: true, from: panel) },
            onCopy: { [weak self, weak panel] in self?.use($0, insert: false, from: panel) },
            onManage: { [weak self] in self?.showManager() },
            onClose: { [weak self, weak panel] in
                if let panel { self?.dismiss(panel, returnFocus: true) }
            },
            onOpenPermissions: { [weak self] in self?.openAccessibilitySettings() }
        ).clipShape(RoundedRectangle(cornerRadius: 14)))
        position(panel, size: NSSize(width: 440, height: 500))
        quickPanel = panel
        // A nonactivating key panel borrows keyboard focus without activating BangsBuddy.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func configure(_ panel: AISpellPanel, title: String) {
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self, weak panel] in
            if let panel { self?.dismiss(panel, returnFocus: true) }
        }
        ScreenCaptureVisibilityManager.shared.register(panel, scope: .panelsOnly)
    }

    private func position(_ panel: NSPanel, size preferred: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let size = NSSize(width: min(preferred.width, bounds.width), height: min(preferred.height, bounds.height))
        panel.setFrame(NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
    }

    private func dismiss(_ panel: NSWindow, returnFocus: Bool, cancelAction: Bool = true) {
        let target: Target?
        if panel === quickPanel {
            target = quickTarget
            // Clear first: intentional orderOut must not cancel an insertion in the delegate.
            quickPanel = nil
            quickTarget = nil
        } else if panel === managerPanel {
            target = managerTarget
            managerPanel = nil
            managerTarget = nil
        } else { return }
        if cancelAction { cancelPendingAction() }
        ScreenCaptureVisibilityManager.shared.unregister(panel)
        panel.orderOut(nil)
        panel.close()
        if returnFocus, let target { _ = activate(target) }
    }

    private func cancelPendingAction() {
        actionID = nil
        pendingAction?.cancel()
        pendingAction = nil
        quickState.isBusy = false
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application, !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular else { return }
        lastExternalApplication = application
    }

    private func captureTarget() -> Target? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalApplication(frontmost)
        let application = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? lastExternalApplication : frontmost
        guard let application, !application.isTerminated else { return nil }
        var focusedElement: AXUIElement?
        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                focusedElement = (value as! AXUIElement)
            }
        }
        return Target(application: application, focusedElement: focusedElement)
    }

    private func activate(_ target: Target) -> Bool {
        guard !target.application.isTerminated else { return false }
        let activated = target.application.activate(options: .activateIgnoringOtherApps)
        if AXIsProcessTrusted(), let element = target.focusedElement {
            // The nonactivating quick panel normally retains the input's first responder.
            // Restore the captured element when the manager/settings had activated the host.
            _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        return activated || NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier
    }

    private func targetInputIsUnchanged(_ target: Target) -> Bool {
        // Apps that never expose an accessibility focus element can still receive
        // a normal paste. When one was captured, never fall through to a different
        // field/window in the same process after navigation or a window close.
        guard let captured = target.focusedElement else { return true }
        var current: CFTypeRef?
        let appElement = AXUIElementCreateApplication(target.application.processIdentifier)
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &current) == .success,
              let current else { return false }
        return CFEqual(captured, current)
    }

    private func use(_ spell: AISpell, insert: Bool, from source: NSWindow?) {
        guard pendingAction == nil, let source, source.isVisible, source.attachedSheet == nil else { return }
        let target = source === quickPanel ? quickTarget : managerTarget
        let wasQuick = source === quickPanel
        let id = UUID()
        actionID = id
        quickState.isBusy = true
        quickState.message = nil
        quickState.offersPermissionSettings = false
        lastTargetName = target?.application.localizedName
        lastInsertionStatus = insert ? "准备插入" : "准备复制"
        var triggerKeys: Set<CGKeyCode> = [CGKeyCode(kVK_Return), CGKeyCode(kVK_ANSI_KeypadEnter)]
        if let event = NSApp.currentEvent, event.type == .keyDown || event.type == .keyUp {
            triggerKeys.insert(event.keyCode)
        }
        let environment = AISpellInsertionCoordinator.Environment(
            writeClipboard: { text in
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(text, forType: .string)
            },
            snapshot: { [weak self, weak source] in
                let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let destination: AISpellInsertionCoordinator.Frontmost
                if frontmost == target?.application.processIdentifier, frontmost != nil { destination = .target }
                else if frontmost == ProcessInfo.processInfo.processIdentifier { destination = .host }
                else { destination = frontmost == nil ? .none : .other }
                return AISpellInsertionCoordinator.Snapshot(
                    isAvailable: Defaults[.enableAISpells] && self?.actionID == id,
                    sourceIsFocused: source?.isVisible == true && source?.isKeyWindow == true && source?.attachedSheet == nil,
                    keysAreReleased: self?.triggerKeysAreReleased(triggerKeys) == true,
                    clipboardMatches: NSPasteboard.general.string(forType: .string) == spell.content,
                    accessibilityGranted: AXIsProcessTrusted(),
                    target: target.map { $0.application.isTerminated ? .terminated : .running } ?? .missing,
                    frontmost: destination
                )
            },
            dismissSource: { [weak self, weak source] in
                if let source { self?.dismiss(source, returnFocus: false, cancelAction: false) }
            },
            activateTarget: { [weak self] in target.map { self?.activate($0) == true } ?? false },
            postPaste: { [weak self] in
                guard let self, let target, self.actionID == id, Defaults[.enableAISpells],
                      !target.application.isTerminated, AXIsProcessTrusted(),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier,
                      self.targetInputIsUnchanged(target),
                      self.triggerKeysAreReleased(triggerKeys), NSPasteboard.general.string(forType: .string) == spell.content,
                      let eventSource = CGEventSource(stateID: .combinedSessionState),
                      let down = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.post(tap: .cgSessionEventTap)
                up.post(tap: .cgSessionEventTap)
                // Exactly one paste shortcut, never a Return / message-send event.
                return true
            },
            pause: { try await Task.sleep(nanoseconds: 50_000_000) }
        )
        pendingAction = Task { @MainActor [weak self] in
            let outcome = await AISpellInsertionCoordinator.use(spell.content, insert: insert, environment: environment)
            guard let self, self.actionID == id else { return }
            self.pendingAction = nil
            self.actionID = nil
            self.quickState.isBusy = false
            self.refreshAccessibilityStatus()
            self.handle(outcome, source: source, target: target, wasQuick: wasQuick)
        }
    }

    private func triggerKeysAreReleased(_ codes: Set<CGKeyCode>) -> Bool {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .control, .option, .shift])
        return modifiers.isEmpty && NSEvent.pressedMouseButtons == 0 && codes.allSatisfy {
            !CGEventSource.keyState(.combinedSessionState, key: $0)
        }
    }

    private func handle(_ outcome: AISpellInsertionCoordinator.Outcome, source: NSWindow, target: Target?, wasQuick: Bool) {
        let message: String
        switch outcome {
        case .copied: lastInsertionStatus = "已复制正文"; return
        case .pasteRequested: lastInsertionStatus = "已向原应用请求粘贴（不自动发送）"; return
        case .cancelled: lastInsertionStatus = "操作已取消"; return
        case .copyFailed: message = "系统剪切板暂时不可用，请重试。"
        case .noTarget: message = "内容已复制。请先点击目标输入框，再用快捷键呼出咒语面板。"
        case .permissionDenied: message = "内容已复制。当前运行的 BangsBuddy 尚未获得辅助功能授权，请在设置中重新检查。"
        case .keysHeld: message = "内容已复制。请松开键盘和鼠标按键后重试。"
        case .focusFailed: message = "内容已复制，但原输入框未能恢复焦点。请点击目标输入框后按 ⌘V。"
        case .targetExited: message = "内容已复制，原应用已经退出。"
        case .clipboardChanged: message = "剪切板内容在操作期间改变，本次插入已取消。请重新选择咒语。"
        case .eventFailed: message = "内容已复制，但未能发出粘贴操作。请在目标输入框按 ⌘V。"
        }
        lastInsertionStatus = message
        if wasQuick || !source.isVisible {
            quickState.message = message
            quickState.offersPermissionSettings = outcome == .permissionDenied
            if quickPanel == nil, Defaults[.enableAISpells] {
                quickTarget = target
                showQuickPanel(resetFeedback: false)
            }
        } else if source.isVisible, source.attachedSheet == nil {
            let alert = NSAlert()
            alert.messageText = "AI 咒语"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: source)
        }
    }
}

private final class AISpellPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !styleMask.contains(.nonactivatingPanel) }

    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        onCancel?()
    }
}
