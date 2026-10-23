// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
struct AISpellSettingsView: View {
    @Default(.enableAISpells) private var enabled
    @Default(.enableShortcuts) private var enableShortcuts

    var body: some View {
        Form {
            Section("AI 咒语") {
                Toggle("启用 AI 咒语", isOn: $enabled)
                    .accessibilityIdentifier("ai-spells-settings-enabled")
                Text("长期保存常用提示词，按标题、正文或分类搜索，并将常用内容收藏。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("打开咒语库") { AISpellPanelController.shared.show() }
                    .disabled(!enabled)
                if !enabled {
                    Text("关闭后仍保留已保存的咒语，再次启用即可继续使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("快捷呼出") {
                KeyboardShortcuts.Recorder("打开 / 收起咒语库：", name: .aiSpellsPanel)
                    .disabled(!enabled || !enableShortcuts)
                Text("点击快捷键框后按下你希望使用的组合键。默认 ⌃⌥P（Control + Option + P）。")
                    .font(.caption).foregroundStyle(.secondary)
                if !enableShortcuts {
                    Text("全局快捷键已关闭；请在“快捷键”设置中启用后再使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("快速使用") {
                LabeledContent("↑ / ↓", value: "选择咒语")
                LabeledContent("↩ 回车", value: "复制正文并收起面板")
                LabeledContent("⌘↩", value: "粘贴到呼出前的应用")
                LabeledContent("Esc", value: "收起面板")
                Text("插入只粘贴文字，不自动发送消息。首次使用插入功能时，macOS 可能要求辅助功能权限；复制功能不需要此权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("保存与备份") {
                Text("咒语仅保存在本机，与剪切板历史独立。清空剪切板或调整历史保留策略不会删除咒语。无需联网或配置 AI 密钥。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("可在咒语库右上角的菜单中导入、导出备份。导入时保留本机已有记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI 咒语")
    }
}
