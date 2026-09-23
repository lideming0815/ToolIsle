from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ChecklessSelectionTests(unittest.TestCase):
    def test_visual_and_accessible_selection(self):
        source = (ROOT / 'DynamicIsland/ToolIsleFeatures/Gitee/GITagControls.swift').read_text()
        for fragment in ['systemName: "checkmark', 'systemName: "square"', '.frame(width: 10)', 'menuOverflow ? 25 : 29']:
            self.assertNotIn(fragment, source)
        for fragment in ['GIChipFaceMetrics.width', '.accessibilityAddTraits(tag.selected ? .isSelected : [])',
                         '.accessibilityAddTraits(selected ? .isSelected : [])', 'tag.selected ? 1.2 : 0.5', '（当前）']:
            self.assertIn(fragment, source)

    def test_native_entrypoint_and_archived_automation(self):
        self.assertFalse((ROOT / 'Package.swift').exists())
        self.assertTrue((ROOT / 'DynamicIsland.xcodeproj/project.pbxproj').exists())
        for name in ['ci.yml', 'release.yml', 'mirror-release.yml', 'nightly-merge.yml', 'triage-slash-commands.yml']:
            self.assertFalse((ROOT / '.github/workflows' / name).exists())
            self.assertTrue((ROOT / 'docs/upstream-workflows' / name).exists())

    def test_copy_toolbar_and_rows(self):
        root = ROOT / 'DynamicIsland/ToolIsleFeatures/Gitee'
        row = (root / 'GIReaderControls.swift').read_text().split('struct GIIssueRow:')[1]
        self.assertNotIn('GICopyIssueButton', row)
        source = (root / 'GIViews.swift').read_text()
        header = source.split('private var header:')[1].split('@ViewBuilder private var detail:')[0]
        self.assertLess(header.index('textformat.size'), header.index('GICopyIssueButton'))
        self.assertLess(header.index('GICopyIssueButton'), header.index('arrow.clockwise'))


if __name__ == '__main__':
    unittest.main()
