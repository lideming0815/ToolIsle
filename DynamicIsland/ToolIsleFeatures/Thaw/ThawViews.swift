// ToolIsle menu bar integration. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@MainActor
final class ThawSettingsNavigation: ObservableObject {
    static let shared = ThawSettingsNavigation()
    @Published var request: UUID?

    func open() {
        request = UUID()
        SettingsWindowController.shared.showWindow()
    }
}

struct ThawSettingsView: View {
    @ObservedObject private var controller = ThawController.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(controller.enabled
                         ? (controller.isRunning ? "菜单栏组件已启动" : "已开启，组件尚未运行")
                         : "菜单栏管理未启用")
                    Spacer()
                    if controller.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    if controller.enabled {
                        Button("停用") { controller.disable() }
                    } else {
                        Button("启用菜单栏管理") { controller.enable() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("thaw-enable")
                    }
                }
                .disabled(controller.isBusy)

                Text(controller.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if controller.enabled && !controller.isRunning {
                    Button("重试启动") { controller.retry() }
                        .disabled(controller.isBusy)
                }
            } header: {
                Text("菜单栏管理")
            } footer: {
                Text("首次启用后，按 Thaw 引导授予辅助功能权限；图标预览可选授予屏幕录制权限。请先退出其他菜单栏管理工具。启用后随本应用启动和退出。")
            }

            if controller.enabled {
                Section("快捷操作") {
                    ThawActionButtons()
                        .disabled(!controller.isRunning || controller.isBusy)
                }

                if let settings = controller.settings {
                    Section("自动重新隐藏") {
                        Toggle("自动重新隐藏菜单栏图标", isOn: Binding(
                            get: { settings.autoRehide },
                            set: { controller.set(.autoRehide, to: .bool($0)) }
                        ))
                        .accessibilityIdentifier("thaw-auto-rehide")

                        Picker("触发方式", selection: Binding(
                            get: { settings.rehideStrategy },
                            set: { controller.set(.rehideStrategy, to: .text($0)) }
                        )) {
                            Text("智能隐藏").tag("smart")
                            Text("定时隐藏").tag("timed")
                            Text("切换前台应用时").tag("focusedApp")
                        }
                        .disabled(!settings.autoRehide)

                        if settings.rehideStrategy == "timed" {
                            Stepper(value: Binding(
                                get: { settings.rehideInterval },
                                set: { controller.set(.rehideInterval, to: .number($0)) }
                            ), in: 1...300, step: 1) {
                                LabeledContent("隐藏前等待", value: "\(Int(settings.rehideInterval)) 秒")
                            }
                            .disabled(!settings.autoRehide)
                        }
                    }
                    .disabled(controller.isBusy || !controller.isRunning)

                    Section("鼠标悬停") {
                        Toggle("悬停在菜单栏空白区域时展开", isOn: Binding(
                            get: { settings.showOnHover },
                            set: { controller.set(.showOnHover, to: .bool($0)) }
                        ))

                        Stepper(value: Binding(
                            get: { settings.showOnHoverDelay },
                            set: { controller.set(.showOnHoverDelay, to: .number($0)) }
                        ), in: 0...5, step: 0.1) {
                            LabeledContent("展开前等待", value: "\(settings.showOnHoverDelay.formatted(.number.precision(.fractionLength(1)))) 秒")
                        }
                        .disabled(!settings.showOnHover)
                    }
                    .disabled(controller.isBusy || !controller.isRunning)

                    Section {
                        LabeledContent("当前屏幕", value: controller.displayName)
                        Toggle("在独立浮条中显示隐藏图标", isOn: Binding(
                            get: { settings.useIceBar },
                            set: { controller.set(.useIceBar, to: .bool($0)) }
                        ))
                        .accessibilityIdentifier("thaw-current-display-bar")
                    } header: {
                        Text("Thaw Bar")
                    } footer: {
                        Text("此设置应用于当前读取的屏幕。切换屏幕后点击“刷新设置”重新读取。")
                    }
                    .disabled(controller.isBusy || !controller.isRunning)
                } else {
                    Section("常用设置") {
                        Text("授权后可在这里调整自动隐藏、鼠标悬停和当前屏幕的 Thaw Bar。若尚未开启设置控制，请先在 Thaw 的更多设置中开启 Settings URI。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("授权设置") { controller.authorizeSettings() }
                            .disabled(controller.isBusy || !controller.isRunning)
                    }
                }

                Section {
                    HStack {
                        Button("刷新设置") { controller.refreshSettings() }
                        Spacer()
                        Button("更多菜单栏设置…") { controller.perform(.openSettings) }
                    }
                    .disabled(controller.isBusy || !controller.isRunning)
                } footer: {
                    Text("图标排序、外观等高级功能在 Thaw 窗口中设置。这里的常用设置以 Thaw 读回的结果为准。")
                }
            }
        }
        .navigationTitle("菜单栏")
        .onAppear { controller.refreshSettings() }
    }
}

private struct ThawActionButtons: View {
    @ObservedObject private var controller = ThawController.shared

    var body: some View {
        HStack {
            Button("切换隐藏区", systemImage: "menubar.arrow.up.rectangle") {
                controller.perform(.toggleHidden)
            }
            Button("搜索菜单栏", systemImage: "magnifyingglass") {
                controller.perform(.search)
            }
            Button("更多设置", systemImage: "gearshape") {
                controller.perform(.openSettings)
            }
        }
    }
}

/// One entry in the existing notch toolbar, without a new notch tab.
struct ThawNotchControl: View {
    @ObservedObject private var controller = ThawController.shared

    var body: some View {
        Group {
            if controller.enabled {
                Menu {
                    ThawMenuItems()
                } label: {
                    glyph
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Button { ThawSettingsNavigation.shared.open() } label: { glyph }
                    .buttonStyle(.plain)
            }
        }
        .help(controller.enabled ? "菜单栏快捷操作" : "启用菜单栏管理")
        .accessibilityLabel("菜单栏管理")
        .accessibilityIdentifier("thaw-notch-control")
    }

    private var glyph: some View {
        Image(systemName: "menubar.rectangle")
            .font(.system(size: 14.4, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.black, in: Capsule())
    }
}

/// Shared by the notch menu and the host's menu-bar menu.
struct ThawMenuItems: View {
    @ObservedObject private var controller = ThawController.shared

    var body: some View {
        Button("切换隐藏区") { controller.perform(.toggleHidden) }
            .disabled(!controller.isRunning || controller.isBusy)
        Button("搜索菜单栏") { controller.perform(.search) }
            .disabled(!controller.isRunning || controller.isBusy)
        Button("更多菜单栏设置…") { controller.perform(.openSettings) }
            .disabled(!controller.isRunning || controller.isBusy)
        Divider()
        Button(controller.enabled ? "菜单栏管理…" : "启用菜单栏管理…") { ThawSettingsNavigation.shared.open() }
    }
}
