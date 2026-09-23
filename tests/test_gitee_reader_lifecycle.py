"""Structural safeguards; real AppKit lifecycle is separately exercised by GIUXProbe."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class GiteeReaderLifecycleTests(unittest.TestCase):
    def text(self, path):
        return (ROOT / 'DynamicIsland' / path).read_text()

    def test_reader_is_a_normal_nonfloating_window(self):
        s = self.text('ToolIsleFeatures/Gitee/GIViews.swift').split('struct GINotchView:')[0]
        for expected in ('let window = NSWindow(', '.managed, .participatesInCycle',
                         'window.hidesOnDeactivate = false', 'window.isExcludedFromWindowsMenu = false',
                         'GIReaderSession.shared.opened(window)', 'GIReaderSession.shared.closed(window)'):
            self.assertIn(expected, s)
        self.assertNotIn('NSPanel(', s)

    def test_settings_close_preserves_reader_session(self):
        s = self.text('components/Settings/SettingsWindowController.swift')
        self.assertIn('GIReaderSession.shared.settingsClosed(window)', s)
        self.assertNotIn('setActivationPolicy(.accessory)', s)

    def test_permission_dialogs_do_not_hide_reader(self):
        for path in ('components/Webcam/WebcamView.swift', 'models/DynamicIslandViewModel.swift'):
            s = self.text(path)
            self.assertIn('GIReaderSession.shared.restorePolicy()', s)
            self.assertIn('if !GIReaderSession.shared.isOpen { NSApp.deactivate() }', s)
            self.assertNotIn('setActivationPolicy(.accessory)', s)

    def test_settings_only_does_not_construct_reader_or_steal_focus(self):
        s = self.text('ToolIsleFeatures/Gitee/GIReaderSession.swift')
        self.assertNotIn('GIReaderWindowController', s)
        self.assertNotIn('openApplication', s)
        self.assertIn('userIsInApplication', s)
        self.assertIn('!window.isMiniaturized', s)
        self.assertIn('Self.isDocument(key)', s)

    def test_notch_has_no_copy_controls(self):
        s = self.text('ToolIsleFeatures/Gitee/GIViews.swift')
        notch = s[s.index('struct GINotchView:'):s.index('struct GIReaderRootView:')]
        self.assertNotIn('GICopyIssueButton', notch)
        self.assertNotIn('GIPasteboard', notch)
        self.assertIn('prefix(layout.metrics.limit)', notch)
        self.assertIn('layout.contentHeight', notch)

    def test_copy_action_does_not_navigate(self):
        s = self.text('ToolIsleFeatures/Gitee/GIReaderControls.swift')
        copy = s[s.index('struct GICopyIssueButton:'):s.index('struct GIIssueRow:')]
        self.assertIn('GIPasteboard.copy(url.absoluteString)', copy)
        self.assertNotIn('GIReaderWindowController', copy)
        self.assertNotIn('store.open', copy)
        self.assertIn('failed = !copied', copy)

    def test_document_classification_uses_visible_geometry_not_private_names(self):
        s = self.text('ToolIsleFeatures/Gitee/GIReaderSession.swift').split('static func isDocument(')[1]
        for expected in ('window.styleMask.contains(.titled)', 'window.isMiniaturized', 'window.alphaValue > 0',
                         'frame.width > 1', 'body.width > 1'):
            self.assertIn(expected, s)
        self.assertNotIn('window.title', s)
        self.assertNotIn('identifier', s)

    def test_delayed_settings_focus_has_a_generation_and_visibility_guard(self):
        s = self.text('components/Settings/SettingsWindowController.swift')
        for expected in ('presentationGeneration += 1', 'generation == self.presentationGeneration',
                         'window.isVisible, !window.isMiniaturized'):
            self.assertIn(expected, s)

    def test_settings_and_probe_share_immediate_layout_action(self):
        for path in ('ToolIsleFeatures/Gitee/GISettingsView.swift', 'ToolIsleFeatures/Gitee/GIUXProbe.swift'):
            self.assertIn('GINotchLayout.shared.setMaximumItems(', self.text(path))
        s = self.text('ToolIsleFeatures/Gitee/GINotchLayout.swift')
        action = s.split('func setMaximumItems(')[1].split('private func schedule()')[0]
        self.assertIn('refreshNow()', action)

    def test_reopening_settings_invalidates_its_old_session_close(self):
        s = self.text('ToolIsleFeatures/Gitee/GIReaderSession.swift')
        action = s.split('func settingsOpened()')[1].split('func opened(')[0]
        self.assertIn('restoreGeneration += 1', action)
        self.assertIn('applyPolicy(.regular)', action)
        self.assertIn('GIReaderSession.shared.settingsOpened()',
                      self.text('components/Settings/SettingsWindowController.swift'))

    def test_other_document_close_reconciles_after_native_ordering(self):
        s = self.text('ToolIsleFeatures/Gitee/GIReaderSession.swift')
        self.assertIn('NSWindow.willCloseNotification', s)
        action = s.split('private init()')[1].split('func settingsOpened()')[0]
        self.assertIn('DispatchQueue.main.async', action)
        self.assertIn('self?.restorePolicy()', action)

if __name__ == '__main__':
    unittest.main()
