// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone AppKit check: compile with ThawController.swift, ThawProtocol.swift and AppRuntimeEnvironment.swift.
// Uses a unique defaults suite and a nonexistent helper path. Never launches a helper or opens permissions UI.
import AppKit
import Combine

@main
struct ThawControllerRegression {
    @MainActor
    static func main() async throws {
        let suiteName = "ToolIsle.ThawControllerRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let host = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThawRegression-\(UUID().uuidString).app", isDirectory: true)
        precondition(!FileManager.default.fileExists(atPath: host.path), "Test host must have no executable helper")
        let controller = ThawController(defaults: defaults, hostURL: host)
        var checks = 0
        func expect(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            checks += 1
        }
        func waitUntil(_ name: String, _ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while !condition() {
                precondition(ContinuousClock.now < deadline, "Timed out: \(name)")
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        var busyTransitions = 0
        let observation = controller.$isBusy.dropFirst().sink { busy in
            if busy { busyTransitions += 1 }
        }
        defer { observation.cancel() }

        expect(!controller.enabled && !controller.isRunning && !controller.isBusy, "fresh suite is disabled and idle")
        expect(controller.settings == nil, "no invented settings snapshot")
        let initialMessage = controller.message
        controller.startIfEnabled()
        controller.refreshSettings()
        controller.authorizeSettings()
        controller.set(.autoRehide, to: .bool(true))
        await Task.yield()
        expect(busyTransitions == 0 && controller.message == initialMessage, "passive entry points do not enqueue work while disabled")
        for action in ThawAction.allCases { controller.perform(action) }
        expect(busyTransitions == 0 && !controller.enabled && !controller.isRunning, "disabled actions never enqueue a launch or command")
        expect(controller.message == ThawError.unavailable.localizedDescription, "disabled action is unavailable, not successful")
        expect(!controller.handleCallback(URL(string: "file:///tmp/thaw-test.txt")!), "unrelated callback remains available to Shelf")
        expect(!controller.handleCallback(URL(string: "https://example.invalid/settings")!), "web URLs are not consumed")
        expect(controller.handleCallback(URL(string: "toolisle-thaw://settings?data=stale")!), "own stale callback is consumed without changing state")
        expect(controller.settings == nil && !controller.isBusy, "stale callback cannot manufacture a snapshot")

        controller.enable()
        expect(controller.enabled && controller.isBusy, "explicit enable starts one operation")
        try await waitUntil("missing helper failure") { !controller.isBusy }
        expect(!controller.isRunning && controller.settings == nil, "missing helper cannot appear running or authorized")
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            expect(controller.message == ThawError.missingHelper.localizedDescription, "missing helper has an explicit repair message")
        } else {
            expect(controller.message.contains("macOS 26"), "unsupported OS has an explicit compatibility message")
        }
        let resumed = ThawController(defaults: defaults, hostURL: host)
        expect(resumed.enabled && !resumed.isRunning && !resumed.isBusy, "enabled preference persists without init launching a helper")
        let failedMessage = controller.message
        let operationsBeforeUnauthorizedCalls = busyTransitions
        controller.authorizeSettings()
        controller.refreshSettings()
        controller.set(.showOnHover, to: .bool(true))
        expect(busyTransitions == operationsBeforeUnauthorizedCalls && controller.message == failedMessage,
               "unavailable component cannot claim authorization or a successful write")

        controller.disable()
        expect(!controller.enabled, "disable records intent synchronously")
        try await waitUntil("disable completes") { !controller.isBusy && controller.message == "菜单栏管理已停用。" }
        expect(!ThawController(defaults: defaults, hostURL: host).enabled, "disabled preference persists")
        expect(await controller.stopForTermination(), "termination succeeds when no owned helper exists")
        controller.enable()
        expect(!controller.enabled && !controller.isBusy, "termination gate prevents a late enable")
        controller.cancelTermination()
        controller.enable()
        expect(controller.enabled && controller.isBusy, "canceled termination restores explicit enable")
        try await waitUntil("post-cancel validation failure") { !controller.isBusy }

        // A second same-turn enable must not overtake the stop queued by disable.
        controller.disable()
        controller.enable()
        expect(!controller.enabled, "disable gates re-enable before its asynchronous stop begins")
        try await waitUntil("final disable") { !controller.isBusy && controller.message == "菜单栏管理已停用。" }
        expect(controller.settings == nil && !controller.isRunning, "final state remains disabled with no fake readback")
        print("PASS: \(checks) controller checks using an isolated defaults suite and missing helper; no GUI or helper launched.")
    }
}
