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

if __name__ == '__main__':
    unittest.main()
