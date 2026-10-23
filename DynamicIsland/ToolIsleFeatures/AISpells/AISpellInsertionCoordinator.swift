// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later

/// Coordinates one copy/insert attempt; the environment owns the native OS effects.
/// This module never sends Return and does not assume the host application is active.
@MainActor
enum AISpellInsertionCoordinator {
    enum TargetState: Equatable, Sendable {
        case missing, running, terminated
    }

    enum Frontmost: Equatable, Sendable {
        case target, host, other, none
    }

    struct Snapshot: Equatable, Sendable {
        var isAvailable: Bool
        var sourceIsFocused: Bool
        var keysAreReleased: Bool
        /// Compare the current plain-text value with this attempt's text, not changeCount.
        var clipboardMatches: Bool
        var accessibilityGranted: Bool
        var target: TargetState
        var frontmost: Frontmost
    }

    struct Environment {
        var writeClipboard: @MainActor (String) -> Bool
        var snapshot: @MainActor () -> Snapshot
        var dismissSource: @MainActor () -> Void
        var activateTarget: @MainActor () -> Bool
        var postPaste: @MainActor () -> Bool
        /// The native adapter supplies its polling interval; tests supply a fake clock.
        var pause: @MainActor () async throws -> Void
    }

    enum Outcome: Equatable, Sendable {
        case copied, pasteRequested, copyFailed, noTarget, permissionDenied
        case keysHeld, focusFailed, targetExited, clipboardChanged, cancelled, eventFailed
    }

    static func use(_ text: String, insert: Bool, environment: Environment) async -> Outcome {
        guard !Task.isCancelled else { return .cancelled }
        guard environment.writeClipboard(text) else { return .copyFailed }
        for wait in 0...100 {
            guard !Task.isCancelled else { return .cancelled }
            let source = environment.snapshot()
            if let failure = sourceFailure(source) { return failure }
            if source.keysAreReleased { break }
            guard wait < 100 else { return .keysHeld }
            do { try await environment.pause() }
            catch { return .cancelled }
            guard !Task.isCancelled else { return .cancelled }
        }
        let ready = environment.snapshot()
        if let failure = sourceFailure(ready) { return failure }
        guard ready.keysAreReleased else { return .keysHeld }
        if !insert {
            environment.dismissSource()
            if ready.target == .running { _ = environment.activateTarget() }
            return .copied
        }
        switch ready.target {
        case .missing: return .noTarget
        case .terminated: return .targetExited
        case .running: break
        }
        guard ready.accessibilityGranted else { return .permissionDenied }
        environment.dismissSource()
        guard environment.activateTarget() else { return .focusFailed }
        // A nonactivating panel can leave the target frontmost throughout. Give
        // AppKit a turn to return its field focus even when that PID never changes.
        for _ in 0..<20 {
            do { try await environment.pause() }
            catch { return .cancelled }
            guard !Task.isCancelled else { return .cancelled }
            let current = environment.snapshot()
            if !current.isAvailable { return .cancelled }
            if current.frontmost == .other { return .cancelled }
            if !current.clipboardMatches { return .clipboardChanged }
            switch current.target {
            case .missing: return .noTarget
            case .terminated: return .targetExited
            case .running: break
            }
            guard current.accessibilityGranted else { return .permissionDenied }
            guard current.frontmost == .target, current.keysAreReleased else { continue }
            guard !Task.isCancelled else { return .cancelled }
            return environment.postPaste() ? .pasteRequested : .eventFailed
        }
        return .focusFailed
    }

    private static func sourceFailure(_ snapshot: Snapshot) -> Outcome? {
        if !snapshot.isAvailable { return .cancelled }
        if snapshot.frontmost == .other { return .cancelled }
        if !snapshot.clipboardMatches { return .clipboardChanged }
        if !snapshot.sourceIsFocused { return .focusFailed }
        return nil
    }
}
