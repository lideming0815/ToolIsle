// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// All normal quit/restart paths wait for the owned menu-bar component to restore
/// its items. A replacement host is launched only after that component has exited.
@MainActor
final class ThawAppLifecycle {
    static let shared = ThawAppLifecycle()

    private var restartRequested = false
    private var terminationTask: Task<Void, Never>?

    func restart() {
        guard terminationTask == nil else { return }
        restartRequested = true
        NSApplication.shared.terminate(nil)
    }

    func shouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task {
            let controller = ThawController.shared
            guard await controller.stopForTermination() else {
                cancelTermination(application, message: controller.message)
                return
            }

            if restartRequested {
                do {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.createsNewApplicationInstance = true
                    _ = try await NSWorkspace.shared.openApplication(
                        at: Bundle.main.bundleURL,
                        configuration: configuration
                    )
                } catch {
                    controller.cancelTermination()
                    cancelTermination(application, message: "无法重新启动应用：\(error.localizedDescription)")
                    if !AppRuntimeEnvironment.isUITesting {
                        controller.startIfEnabled()
                    }
                    return
                }
            }

            // Keep the operation in flight until the process exits, so repeated
            // termination requests cannot stop a newly launched host's helper.
            application.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func cancelTermination(_ application: NSApplication, message: String) {
        restartRequested = false
        terminationTask = nil
        application.reply(toApplicationShouldTerminate: false)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "应用保持运行"
        alert.informativeText = message.isEmpty
            ? "菜单栏组件尚未正常退出。请稍后重试，避免中断菜单栏恢复。"
            : message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
