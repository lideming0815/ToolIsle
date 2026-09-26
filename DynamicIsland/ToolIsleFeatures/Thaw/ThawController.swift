// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine

/// Owns only the helper inside this application. Views never launch applications,
/// compose URIs, or persist a second copy of Thaw's settings.
@MainActor
final class ThawController: ObservableObject {
    static let shared = ThawController()
    private static let enabledKey = "toolisle.thaw.enabled"

    @Published private(set) var enabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var message = "菜单栏管理尚未启用。启用后会引导你授予所需权限。"
    @Published private(set) var settings: ThawSettings?
    @Published private(set) var displayName = "当前屏幕"

    private var application: NSRunningApplication?
    private let defaults: UserDefaults
    private let hostURL: URL
    private let notificationCenter: NotificationCenter
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var stopTask: Task<Bool, Never>?
    private var isStopping = false
    private var terminationRequested = false
    private var displayUUID: String?
    private var observers: [NSObjectProtocol] = []
    private var pending: PendingRead?

    private struct PendingRead {
        let id: UUID
        let key: ThawSettingKey
        let continuation: AsyncThrowingStream<ThawSettingValue, Error>.Continuation
    }

    init(defaults: UserDefaults = .standard, hostURL: URL = Bundle.main.bundleURL) {
        self.defaults = defaults
        self.hostURL = hostURL
        self.notificationCenter = NSWorkspace.shared.notificationCenter
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard let self, app.processIdentifier == self.application?.processIdentifier else { return }
                self.application = nil
                self.isRunning = false
                self.settings = nil
                self.failPending(ThawError.unavailable)
                if !self.isStopping { self.message = "菜单栏组件已退出，可手动重试。ToolIsle 其他功能不受影响。" }
            }
        })
    }

    deinit { for observer in observers { notificationCenter.removeObserver(observer) } }

    func startIfEnabled() {
        guard enabled, !AppRuntimeEnvironment.isUITesting else { return }
        run {
            try await self.launch()
            try await self.loadSettings()
        }
    }

    func enable() {
        guard !isStopping, !isBusy else { return }
        enabled = true
        defaults.set(true, forKey: Self.enabledKey)
        run {
            try await self.launch()
            self.message = "Thaw 已启动。请完成它的系统权限引导，再点击“授权设置”，允许 ToolIsle 读取和修改设置。"
        }
    }

    func disable() {
        guard !isStopping else { return }
        enabled = false
        defaults.set(false, forKey: Self.enabledKey)
        isStopping = true
        isBusy = true
        settings = nil
        Task { _ = await stop(terminating: false) }
    }

    func retry() {
        guard enabled else { enable(); return }
        run {
            try await self.launch()
            try await self.loadSettings()
        }
    }

    func authorizeSettings() {
        guard enabled, isRunning else { return }
        run {
            try await self.send(ThawProtocol.authorize, activates: true)
            self.settings = nil
            self.message = "请在 Thaw 中允许 ToolIsle 的设置访问，然后点击“重新读取”。拒绝后也可继续使用 ToolIsle。"
        }
    }

    func refreshSettings() {
        guard enabled, isRunning else { return }
        run { try await self.loadSettings() }
    }

    func perform(_ action: ThawAction) {
        guard enabled, isRunning else { message = ThawError.unavailable.localizedDescription; return }
        run {
            // A toggle has no completion callback and is never retried automatically.
            try await self.send(ThawProtocol.action(action), activates: action != .toggleHidden)
            self.message = "请求已发送给 Thaw。若功能未出现，请检查 Thaw 的系统权限。"
        }
    }

    func set(_ key: ThawSettingKey, to value: ThawSettingValue) {
        guard enabled, isRunning, settings != nil else { return }
        // Keep the display of the displayed snapshot, even if the mouse moves to another screen.
        let targetDisplay = displayUUID
        run {
            guard key.accepts(value), key != .useIceBar || targetDisplay != nil else { throw ThawError.invalidSetting }
            self.settings = nil
            try await self.send(try ThawProtocol.set(key, value: value, display: targetDisplay))
            let actual = try await self.read(key, display: targetDisplay)
            try await self.loadSettings(display: targetDisplay)
            guard actual == value else { throw ThawError.readbackMismatch }
            self.message = "设置已读回确认。"
        }
    }

    /// Consumes our scheme even for stale or malformed callbacks, never routing it to Shelf.
    func handleCallback(_ url: URL) -> Bool {
        guard ThawProtocol.isCallback(url) else { return false }
        guard let pending else { return true }
        do {
            let value = try ThawProtocol.response(url, id: pending.id, key: pending.key)
            finishRead(id: pending.id, result: .success(value))
        } catch ThawError.remote(let text) {
            finishRead(id: pending.id, result: .failure(ThawError.remote(text)))
        } catch {
            // Unsolicited or mismatched responses cannot complete a pending request.
        }
        return true
    }

    func stopForTermination() async -> Bool { await stop(terminating: true) }

    func cancelTermination() {
        guard stopTask == nil else { return }
        terminationRequested = false
        isStopping = false
    }

    private var helperURL: URL {
        hostURL.appendingPathComponent("Contents/Helpers/Thaw.app", isDirectory: true)
    }

    private func validatedHelper() throws -> URL {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
            throw ThawError.remote("此菜单栏组件需要 macOS 26 或更高版本。")
        }
        let expected = helperURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: expected.path) else { throw ThawError.missingHelper }
        let root = hostURL.resolvingSymlinksInPath().path + "/Contents/Helpers/"
        guard expected.resolvingSymlinksInPath().path.hasPrefix(root),
              let bundle = Bundle(url: expected), bundle.bundleIdentifier == ThawProtocol.helperBundleID,
              bundle.object(forInfoDictionaryKey: "ToolIsleManagedComponent") as? Bool == true,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == ThawProtocol.helperVersion else {
            throw ThawError.incompatibleHelper
        }
        return expected
    }

    private func launch() async throws {
        try Task.checkCancellation()
        guard enabled, !isStopping else { throw CancellationError() }
        let target = try validatedHelper()
        let managers = ["com.stonerl.Thaw", "com.jordanbaird.Ice", ThawProtocol.helperBundleID]
        for app in NSWorkspace.shared.runningApplications where managers.contains(app.bundleIdentifier ?? "") {
            guard app.bundleIdentifier == ThawProtocol.helperBundleID,
                  app.bundleURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath() else {
                throw ThawError.conflictingApp(app.localizedName ?? "其他菜单栏管理器")
            }
        }
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: ThawProtocol.helperBundleID)
            .first(where: { $0.bundleURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath() }) {
            application = existing
            isRunning = !existing.isTerminated
            return
        }
        message = "正在启动内嵌菜单栏组件…"
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: target, configuration: config) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: ThawError.unavailable) }
            }
        }
        // Record ownership even if cancellation occurred during the native launch request.
        // The termination path waits for this operation and will then stop this exact app.
        application = app
        isRunning = !app.isTerminated
        try Task.checkCancellation()
        guard isRunning else { throw ThawError.unavailable }
    }

    private func send(_ url: URL, activates: Bool = false) async throws {
        try Task.checkCancellation()
        guard enabled, !isStopping, let application, !application.isTerminated else { throw ThawError.unavailable }
        let target = try validatedHelper()
        guard application.bundleURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath() else {
            throw ThawError.incompatibleHelper
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activates
        let recipient: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open([url], withApplicationAt: target, configuration: config) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: ThawError.unavailable) }
            }
        }
        // Launch Services can relaunch a recipient that exited during dispatch.
        // Retain that exact instance before checking cancellation so quit can stop it.
        guard recipient.bundleURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath() else {
            throw ThawError.incompatibleHelper
        }
        self.application = recipient
        isRunning = !recipient.isTerminated
        try Task.checkCancellation()
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !isStopping else { return }
        let id = UUID()
        operationID = id
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.operationID == id {
                    self.operation = nil
                    self.operationID = nil
                    self.isBusy = self.isStopping
                }
            }
            do { try await body() }
            catch is CancellationError { }
            catch {
                if case ThawError.readbackMismatch = error { } else { self.settings = nil }
                self.message = error.localizedDescription
            }
        }
    }

    private func loadSettings(display: String? = nil) async throws {
        var targetDisplay = display
        if targetDisplay == nil {
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
                throw ThawError.remote("无法确定当前屏幕，请重新读取。")
            }
            targetDisplay = CFUUIDCreateString(nil, uuid) as String
            displayName = screen.localizedName
        }
        settings = nil
        var values: [ThawSettingKey: ThawSettingValue] = [:]
        for key in ThawSettingKey.allCases { values[key] = try await read(key, display: targetDisplay) }
        try Task.checkCancellation()
        settings = try ThawSettings(values: values)
        displayUUID = targetDisplay
        message = "设置已读取。菜单栏操作仍取决于 Thaw 的系统权限。"
    }

    private func read(_ key: ThawSettingKey, display: String?) async throws -> ThawSettingValue {
        try Task.checkCancellation()
        let id = UUID()
        let url = ThawProtocol.get(key, id: id, display: display)
        let (responses, continuation) = AsyncThrowingStream<ThawSettingValue, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        pending = PendingRead(id: id, key: key, continuation: continuation)
        let timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 6_000_000_000) } catch { return }
            self?.finishRead(id: id, result: .failure(ThawError.timeout))
        }
        defer {
            timeout.cancel()
            finishRead(id: id, result: .failure(CancellationError()))
        }
        // Await dispatch in this operation, so shutdown also waits for an in-flight
        // native open request. A fast callback is buffered until dispatch returns.
        try await send(url)
        var iterator = responses.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        try Task.checkCancellation()
        return value
    }

    private func finishRead(id: UUID, result: Result<ThawSettingValue, Error>) {
        guard let current = pending, current.id == id else { return }
        pending = nil
        switch result {
        case .success(let value):
            current.continuation.yield(value)
            current.continuation.finish()
        case .failure(let error): current.continuation.finish(throwing: error)
        }
    }

    private func failPending(_ error: Error) {
        if let pending { finishRead(id: pending.id, result: .failure(error)) }
    }

    private func stop(terminating: Bool) async -> Bool {
        terminationRequested = terminationRequested || terminating
        if let stopTask { return await stopTask.value }
        isStopping = true
        isBusy = true
        settings = nil
        operation?.cancel()
        failPending(CancellationError())
        let previousOperation = operation
        let task = Task { @MainActor in
            await previousOperation?.value
            let app = self.application.flatMap { $0.isTerminated ? nil : $0 }
                ?? NSRunningApplication.runningApplications(withBundleIdentifier: ThawProtocol.helperBundleID)
                    .first(where: { $0.bundleURL?.resolvingSymlinksInPath() == self.helperURL.resolvingSymlinksInPath() })
            guard let app else { return true }
            guard app.bundleURL?.resolvingSymlinksInPath() == self.helperURL.resolvingSymlinksInPath() else {
                self.message = "组件路径不匹配，已取消退出以避免操作其他应用。"
                return false
            }
            guard app.terminate() else {
                self.message = "Thaw 未接受退出请求，请关闭它的对话框后重试。"
                return false
            }
            for _ in 0..<50 {
                if app.isTerminated { return true }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            self.message = "Thaw 尚未退出。为保留菜单栏恢复流程，请关闭它的对话框后重试。"
            return false
        }
        stopTask = task
        let stopped = await task.value
        stopTask = nil
        isBusy = false
        if stopped {
            application = nil
            isRunning = false
            message = enabled ? "菜单栏组件已停止。" : "菜单栏管理已停用。"
        }
        if !stopped { terminationRequested = false }
        isStopping = stopped && terminationRequested
        return stopped
    }
}
