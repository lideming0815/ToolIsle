from pathlib import Path
import hashlib
import re

root = Path.cwd()
def replace(path, old, new, count=1):
    p = root / path
    text = p.read_text()
    assert text.count(old) == count, (path, text.count(old), old[:80])
    p.write_text(text.replace(old, new))

tag = 'DynamicIsland/ToolIsleFeatures/Gitee/GITagControls.swift'
data = (root/tag).read_bytes()
assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == '7d0771c1ccaa7d5d3289fa32244ca0572a686ca8'
replace(tag, '/// The size calculation reserves the same font/padding/checkmark used by GITagFace.', '/// Geometry matches GITagFace padding. Selection never reserves an icon slot.')
replace(tag, 'return min(Double(available), min(158, ceil(text) + (selectable ? (menuOverflow ? 25 : 29) : (tag.state ? 27 : 16))))', 'return GIChipFaceMetrics.width(textWidth: Double(text), available: Double(available),\n                                       selectable: selectable, compact: menuOverflow, state: tag.state)')
replace(tag, '''            if selectable {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 10).opacity(tag.selected ? 1 : 0)
            } else if tag.state {''', '''            if !selectable && tag.state {''')
replace(tag, '.accessibilityLabel(tag.title).accessibilityValue(tag.selected ? "已选中" : "未选中")', '.accessibilityLabel(tag.title).accessibilityValue(tag.selected ? "已选中" : "未选中")\n                                    .accessibilityAddTraits(tag.selected ? .isSelected : [])')
replace(tag, '''                        HStack { Text(GIListPresentation.stateTitle(state)); if state == store.stateFilter { Image(systemName: "checkmark") } }
                    }''', '''                        Text(GIListPresentation.stateTitle(state) + (state == store.stateFilter ? "（当前）" : ""))
                    }
                    .accessibilityValue(state == store.stateFilter ? "已选中" : "未选中")''')
replace(tag, '''    @FocusState private var focused: Bool
    private func matches''', '''    @FocusState private var focused: Bool
    @Environment(\\.colorScheme) private var appearance
    private func matches''')
replace(tag, '''    private func choice(_ name: String, detail: String, color: String?) -> some View {
        Button { store.toggleLabel(name) } label: {
            HStack(spacing: 8) {
                Image(systemName: store.selectedLabels.contains(name) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(store.selectedLabels.contains(name) ? Color.accentColor : .secondary)
                Circle().fill(GITagPalette.color(color, dark: false)).frame(width: 7, height: 7)''', '''    private func choice(_ name: String, detail: String, color: String?) -> some View {
        let selected = store.selectedLabels.contains(name)
        return Button { store.toggleLabel(name) } label: {
            HStack(spacing: 8) {
                Circle().fill(GITagPalette.color(color, dark: appearance == .dark)).frame(width: 7, height: 7)''')
replace(tag, '''            }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).help(name).accessibilityValue(store.selectedLabels.contains(name) ? "已选中" : "未选中")''', '''            }.padding(.vertical, 5).padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(selected ? (appearance == .dark ? 0.22 : 0.12) : 0),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                    Color.accentColor.opacity(selected ? 0.65 : 0), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(name)
            .accessibilityLabel(name).accessibilityValue(selected ? "已选中" : "未选中")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("gitee-label-choice-\\(name)")''')

core = root / 'DynamicIsland/ToolIsleFeatures/Gitee/GIListPresentation.swift'
core.write_text(core.read_text() + '''

/// Text measurement and horizontal padding only; selected and unselected filters
/// use identical geometry, with no invisible checkbox or checkmark reservation.
enum GIChipFaceMetrics {
    static func width(textWidth: Double, available: Double, selectable: Bool,
                      compact: Bool, state: Bool) -> Double {
        let extra: Double = selectable ? (compact ? 12 : 16) : (state ? 27 : 16)
        return min(max(0, available), min(158, ceil(max(0, textWidth)) + extra))
    }
}
''')
replace('tests/GiteeLabelsRegression.swift', '        let decoder = JSONDecoder()', '''        for compact in [false, true] {
            let padding: Double = compact ? 12 : 16
            for text in [0.0, 11.1, 33, 75.8] {
                expect(GIChipFaceMetrics.width(textWidth: text, available: 236, selectable: true, compact: compact, state: false) == ceil(text) + padding,
                       "filter geometry contains no checkmark slot")
            }
        }
        expect(GIChipFaceMetrics.width(textWidth: 300, available: 236, selectable: true, compact: false, state: false) == 158, "long chip remains bounded")
        expect(GIChipFaceMetrics.width(textWidth: 40, available: 30, selectable: true, compact: true, state: false) == 30, "narrow chip respects available width")
        expect(GIChipFaceMetrics.width(textWidth: 33, available: 236, selectable: false, compact: false, state: true) == 60, "noninteractive Issue status geometry is unchanged")
        expect(GIChipFaceMetrics.width(textWidth: 33, available: 236, selectable: false, compact: false, state: false) == 49, "noninteractive Issue label geometry is unchanged")
        let decoder = JSONDecoder()''')
probe = 'DynamicIsland/ToolIsleFeatures/Gitee/GILabelProbe.swift'
replace(probe, '            store.installLabelFixtures(); store.clearFilters()', '''            store.installLabelFixtures(); store.clearFilters()
            for compact in [true, false] {
                let text = ("进行中" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
                let actual = GIChipFaceMetrics.width(textWidth: Double(text), available: 236,
                    selectable: true, compact: compact, state: false)
                let old = ceil(Double(text)) + (compact ? 25 : 29)
                check(abs(old - actual - 13) < 0.01, "checkless filters reclaim 13pt in \\(compact ? "status" : "label") chips")
            }''')
replace(probe, '                    store.stateFilter = "unfinished"', '                    store.stateFilter = "unfinished"\n                    store.selectedLabels = ["bug"]')
replace(probe, '                picker.makeKeyAndOrderFront(nil); await pause(); capture(picker, "labels-picker")', '''                picker.makeKeyAndOrderFront(nil); await pause(); capture(picker, "labels-picker")
                check(store.selectedLabels == ["bug"], "selected label remains explicit without checkbox")
                store.toggleLabel("bug"); await pause()
                check(store.selectedLabels.isEmpty, "selected label can be deselected without checkbox")
                capture(picker, "labels-picker-cleared")
                store.toggleLabel("bug"); await pause()''')
replace('DynamicIsland.xcodeproj/project.pbxproj', 'CURRENT_PROJECT_VERSION = 1643;', 'CURRENT_PROJECT_VERSION = 1644;', 2)

expected = {
    tag: 'e3d501e945f3a9b8bfdd97a4d4ef6b270cc25a5af3cdc71f1dae9d563191ad1c',
    'DynamicIsland/ToolIsleFeatures/Gitee/GIListPresentation.swift': '7b89c85568664a070585659d1be95b3bff8edce6f9dc601a8894cc656dcb5efc',
    probe: 'ac30e201b21a8e559bee14c8a1f584c23038bf4f02d9f237f5f67c320e3734a0',
    'tests/GiteeLabelsRegression.swift': '59066b4a2ea137a875436a3e3060dd6934c20a62cccef889edd866f34890748e',
    'DynamicIsland.xcodeproj/project.pbxproj': 'ca7bbaad867c9039e36caa9288dab64fec13e2b9d2ffe8d87601247c4e7c01b2'
}
for path, digest in expected.items():
    assert hashlib.sha256((root/path).read_bytes()).hexdigest() == digest, path

# Fork integration must not restart upstream publication/mirror/nightly writes.
for name in ['ci.yml', 'release.yml', 'nightly-merge.yml', 'mirror-release.yml', 'triage-slash-commands.yml']:
    p = root/'.github/workflows'/name
    text=p.read_text()
    if '    if: >-\n' in text:
        pattern = r'    if: >-\n((?:      [^\n]*\n)+)'
        def guard(m):
            return "    if: >-\n      github.repository == 'Ebullioscopic/Atoll' && (\n" + m.group(1) + "      )\n"
        text,n=re.subn(pattern,guard,text,count=1);assert n==1,name
    elif '    if: contains(' in text:
        text=text.replace('    if: contains(', "    if: github.repository == 'Ebullioscopic/Atoll' && contains(",1)
    else:
        text,n=re.subn(r'(jobs:\n  [^\n]+:\n)',r"\1    if: github.repository == 'Ebullioscopic/Atoll'\n",text,count=1);assert n==1,name
    p.write_text(text)

p=root/'ReadMe.md';text=p.read_text();text=text.replace(text.splitlines()[0], '> **ToolIsle：保留 Atoll 主体的 Gitee Issue 阅读版。** `dev` 使用原 `DynamicIsland.xcodeproj`，包含独立 Gitee 设置、关联跳转、项目分组和紧凑筛选。当前说明见 [TOOLISLE-GITEE-CHECKLESS.md](TOOLISLE-GITEE-CHECKLESS.md)。下方保留上游介绍与来源链接；上游下载不是 ToolIsle 构建。',1);p.write_text(text)
p=root/'TOOLISLE.md';p.write_text('> 历史基线说明，仅作回滚对照。当前版本见 [TOOLISLE-GITEE-CHECKLESS.md](TOOLISLE-GITEE-CHECKLESS.md)，不再适用下文“仅替换 Logo”的范围。\n\n'+p.read_text())
p=root/'CHANGELOG.md';text=p.read_text();text=text.replace('### Added\n', '### Added\n- **ToolIsle native Gitee reader**: restore the Atoll app instead of the superseded standalone toolbox; retain supplied branding, scoped display/window fixes, read-only Issues, associated navigation, grouped projects and compact filters.\n',1);text=text.replace('### Changed\n','### Changed\n- **ToolIsle compact selection**: remove checkmarks and their reserved width from status/label filters and label popovers. Keep selection backgrounds, outlines, accessible state and reading history.\n',1);p.write_text(text)
(root/'TOOLISLE-GITEE-CHECKLESS.md').write_text('''# ToolIsle gitee.6 — 紧凑选择与 dev 集成

应用 2.3.3（1644），arm64。基于 gitee.5 提交 9b93364，继续使用原 DynamicIsland.xcodeproj / DynamicIsland scheme，产物 ToolIsle.app，不恢复独立 Swift Package 工具箱。

状态及标签平铺筛选去掉勾选图标及其 13pt 占位；选中/未选中宽度一致，用底色、边框和无障碍信息区分。更多状态使用“（当前）”文字；标签多选面板取消方框，使用选中背景/边框。保持三个优先状态单行、标签两行、搜索/OR 多选、按项目折叠与阅读位置。列表和刘海无复制图标，顶部复制仍在字号后。

Gitee API、Markdown、链接路由、窗口生命周期、刘海尺寸、媒体、锁屏、Shelf 和计时器不在此次改动范围。账户和项目配置不重置，GPL 与第三方声明保留。

ToolIsle 使用 toolisle-integration.yml 在集成分支与 dev 构建原 Target，并运行两轮原生窗口回归及标签 UI 检查。详细通过结果、源码 SHA 和截图见同提交的 toolisle-integrated-preview Actions 产物。旧上游 CI/发布/镜像/nightly/命令自动化仅允许在上游运行，避免合并到 dev 后意外发布或修改其他分支。代码通过普通 PR merge 合入，不 force-push。

测试包声明最低 macOS 14.6，临时签名、未经 Apple 公证。先退出旧 ToolIsle 和官方 Atoll，备份旧应用再替换，不需要清空账户。仍保留原 Bundle ID、偏好域、扩展协议及上游更新器；不要同时运行官方版，不要接受上游更新覆盖测试包。

自动测试使用合成数据、不含私有令牌；仅测试进程通过 -SUEnableAutomaticChecks NO 隔离首次更新询问，不修改产品更新设置。真实私有 Gitee、第三方 AltTab、实体多屏/合盖及全部原 Atoll 能力仍需本机验收。
''')
(root/'tests/test_gitee_checkless.py').write_text('''from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ChecklessSelectionTests(unittest.TestCase):
    def test_visual_and_accessible_selection(self):
        s=(ROOT/'DynamicIsland/ToolIsleFeatures/Gitee/GITagControls.swift').read_text()
        for fragment in ['systemName: "checkmark', 'systemName: "square"', '.frame(width: 10)', 'menuOverflow ? 25 : 29']:
            self.assertNotIn(fragment,s)
        for fragment in ['GIChipFaceMetrics.width', '.accessibilityAddTraits(tag.selected ? .isSelected : [])', '.accessibilityAddTraits(selected ? .isSelected : [])', 'tag.selected ? 1.2 : 0.5', '（当前）']:
            self.assertIn(fragment,s)
    def test_native_entrypoint_and_guarded_automation(self):
        self.assertFalse((ROOT/'Package.swift').exists())
        self.assertTrue((ROOT/'DynamicIsland.xcodeproj/project.pbxproj').exists())
        for name in ['ci.yml','release.yml','mirror-release.yml','nightly-merge.yml','triage-slash-commands.yml']:
            self.assertIn("github.repository == 'Ebullioscopic/Atoll'",(ROOT/'.github/workflows'/name).read_text())
    def test_copy_toolbar_and_rows(self):
        root=ROOT/'DynamicIsland/ToolIsleFeatures/Gitee'
        self.assertNotIn('GICopyIssueButton',(root/'GIReaderControls.swift').read_text().split('struct GIIssueRow:')[1])
        s=(root/'GIViews.swift').read_text();h=s.split('private var header:')[1].split('@ViewBuilder private var detail:')[0]
        self.assertLess(h.index('textformat.size'),h.index('GICopyIssueButton'))
        self.assertLess(h.index('GICopyIssueButton'),h.index('arrow.clockwise'))
if __name__=='__main__': unittest.main()
''')
print('Scoped source changes match prevalidated SHA256 digests.')
