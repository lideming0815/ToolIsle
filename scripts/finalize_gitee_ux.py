from pathlib import Path
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIReaderSession.swift')
s=p.read_text()
old='''    private static func isDocument(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal
    }'''
new='''    private static func isDocument(_ window: NSWindow) -> Bool {
        // AppKit/SwiftUI can retain ordered-in helper windows after a menu or
        // activation transition. Their isVisible flag alone does not make them
        // user-facing documents that should keep a menu-bar app in the Dock.
        guard window.styleMask.contains(.titled), !(window is NSPanel),
              window.level == .normal, window.canBecomeMain,
              !window.isExcludedFromWindowsMenu, !window.ignoresMouseEvents,
              window.alphaValue > 0, window.contentView != nil else { return false }
        let content = window.contentLayoutRect
        return content.width > 1 && content.height > 1
    }'''
assert s.count(old)==1
p.write_text(s.replace(old,new))
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIUXProbe.swift')
s=p.read_text()
old='''                     "minimized": window.isMiniaturized, "key": window.isKeyWindow,
                     "normal_document": window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal]'''
new='''                     "minimized": window.isMiniaturized, "key": window.isKeyWindow,
                     "can_become_main": window.canBecomeMain, "excluded_from_menu": window.isExcludedFromWindowsMenu,
                     "ignores_mouse": window.ignoresMouseEvents, "alpha": window.alphaValue,
                     "frame": NSStringFromRect(window.frame), "content_rect": NSStringFromRect(window.contentLayoutRect),
                     "content_view": window.contentView.map { String(describing: type(of: $0)) } ?? "nil",
                     "accessibility_subrole": String(describing: window.accessibilitySubrole()),
                     "normal_document": window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal]'''
assert s.count(old)==1
p.write_text(s.replace(old,new))
