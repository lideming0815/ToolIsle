// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
struct AISpellSettingsView: View {
    @Default(.enableAISpells) private var enabled
    @Default(.enableShortcuts) private var enableShortcuts
    @ObservedObject private var panelController = AISpellPanelController.shared

    var body: some View {
        Form {
            Section("AI 咒语") {
                Toggle("启用 AI 咒语", isOn: $enabled)
                    .accessibilityIdentifier("ai-spells-settings-enabled")
                Text("长期保存常用提示词，按标题、正文或分类搜索，并将常用内容收藏。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开咒语面板") { AISpellPanelController.shared.show() }
                        .accessibilityIdentifier("ai-spells-settings-open-quick")
                    Button("管理咒语…") { AISpellPanelController.shared.showManager() }
                        .accessibilityIdentifier("ai-spells-settings-open-manager")
                }
                .disabled(!enabled)
                if !enabled {
                    Text("关闭后仍保留已保存的咒语，再次启用即可继续使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("快捷呼出") {
                KeyboardShortcuts.Recorder("打开 / 收起咒语面板：", name: .aiSpellsPanel)
                    .disabled(!enabled || !enableShortcuts)
                Text("点击快捷键框后按下你希望使用的组合键。默认 ⌃⌥P（Control + Option + P）。")
                    .font(.caption).foregroundStyle(.secondary)
                if !enableShortcuts {
                    Text("全局快捷键已关闭；请在“快捷键”设置中启用后再使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("快速使用") {
                LabeledContent("单击咒语", value: "直接插入原应用")
                LabeledContent("↑ / ↓", value: "选择咒语")
                LabeledContent("↩ 回车", value: "插入选中的咒语")
                LabeledContent("⌘↩", value: "仅复制正文并收起面板")
                LabeledContent("Esc", value: "收起面板")
                Text("插入只粘贴文字，不自动发送消息。首次使用插入功能时，macOS 可能要求辅助功能权限；复制功能不需要此权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("插入权限与诊断") {
                LabeledContent("当前应用的辅助功能权限", value: panelController.accessibilityGranted ? "已授权" : "未授权")
                HStack {
                    Button("重新检查") { panelController.refreshAccessibilityStatus() }
                    Button("打开辅助功能设置") { panelController.openAccessibilitySettings() }
                    Button("复制诊断信息") { panelController.copyDiagnosticInformation() }
                }
                if !panelController.accessibilityGranted {
                    Text("如果系统开关已经开启，这里仍显示未授权，请退出 BangsBuddy，在辅助功能列表中移除旧条目，再添加应用程序文件夹里的当前版本后重启。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(panelController.lastInsertionStatus)
                    .font(.caption).foregroundStyle(.secondary)
                Text("诊断信息包含当前应用版本、安装位置和操作状态，不包含咒语正文或剪切板内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("保存与备份") {
                Text("咒语仅保存在本机，与剪切板历史独立。清空剪切板或调整历史保留策略不会删除咒语。无需联网或配置 AI 密钥。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("在管理窗口中新建、编辑、分类或收藏咒语。管理窗口右上角的菜单可导入、导出备份，导入时保留本机已有记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI 咒语")
        .onAppear { panelController.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            panelController.refreshAccessibilityStatus()
        }
    }
}
