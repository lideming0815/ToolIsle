// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

private struct RegressionFailure: Error, CustomStringConvertible {
    let description: String
}

/// A fake OS and clock at the production coordinator's external seam.
/// No AppKit behavior or macOS accessibility permission is simulated as verified.
@MainActor
private final class InsertionEnvironment {
    typealias Coordinator = AISpellInsertionCoordinator

    var state = Coordinator.Snapshot(
        isAvailable: true, sourceIsFocused: true, keysAreReleased: true,
        clipboardMatches: true, accessibilityGranted: true,
        target: .running, frontmost: .target
    )
    var clipboard: String?
    var copiedValues: [String] = []
    var insertionRequests: [String] = []
    var sourceDismissals = 0
    var targetActivations = 0
    var pauseCount = 0
    var clipboardWriteSucceeds = true
    var activationSucceeds = true
    var eventSucceeds = true
    var returnKeyHeld = false
    var modifierKeyHeld = false
    var onPause: ((Int) throws -> Void)?

    var environment: Coordinator.Environment {
        .init(
            writeClipboard: { [self] value in
                copiedValues.append(value)
                guard clipboardWriteSucceeds else { return false }
                clipboard = value
                return true
            },
            snapshot: { [self] in
                var current = state
                current.keysAreReleased = state.keysAreReleased && !returnKeyHeld && !modifierKeyHeld
                return current
            },
            dismissSource: { [self] in
                sourceDismissals += 1
                state.sourceIsFocused = false
            },
            activateTarget: { [self] in
                targetActivations += 1
                return activationSucceeds
            },
            postPaste: { [self] in
                insertionRequests.append(clipboard ?? "")
                return eventSucceeds
            },
            pause: { [self] in
                pauseCount += 1
                try onPause?(pauseCount)
            }
        )
    }
}

@main
@MainActor
struct AISpellInsertionRegression {
    typealias Coordinator = AISpellInsertionCoordinator
    private static var assertions = 0

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw RegressionFailure(description: message) }
    }

    @MainActor
    static func main() async {
        do {
            try await run()
            print("AI spell insertion contract regressions passed (\(assertions) assertions).")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let text = "  测试咒语\nGiving context.\n"
        let success = InsertionEnvironment()
        let outcome = await Coordinator.use(text, insert: true, environment: success.environment)
        try expect(outcome == .pasteRequested, "A focused nonactivating panel can request insertion into its captured target")
        try expect(success.insertionRequests == [text], "One request preserves the exact multiline content")
        try expect(success.sourceDismissals == 1 && success.targetActivations == 1,
                   "Successful insertion dismisses the source and activates the target exactly once")
        try expect(success.pauseCount == 1,
                   "Even an already-frontmost target gets one focus-settling pause before paste")

        let held = InsertionEnvironment()
        held.returnKeyHeld = true
        held.modifierKeyHeld = true
        held.onPause = { tick in
            if tick <= 3 {
                try expect(held.sourceDismissals == 0 && held.insertionRequests.isEmpty,
                           "Holding Return or a modifier keeps focus in the source without posting paste")
            }
            if tick == 1 { held.returnKeyHeld = false }
            if tick == 3 { held.modifierKeyHeld = false }
        }
        let afterRelease = await Coordinator.use(text, insert: true, environment: held.environment)
        try expect(afterRelease == .pasteRequested && held.pauseCount == 4,
                   "Insertion waits until both Return and the modifier are released")
        try expect(held.insertionRequests == [text], "Released keys result in exactly one insertion request")

        let heldForever = InsertionEnvironment()
        heldForever.returnKeyHeld = true
        let timedOut = await Coordinator.use(text, insert: true, environment: heldForever.environment)
        try expect(timedOut == .keysHeld && heldForever.pauseCount == 100,
                   "An unreleased trigger has a bounded wait and an explicit keysHeld outcome")
        try expect(heldForever.sourceDismissals == 0 && heldForever.insertionRequests.isEmpty,
                   "A held key never dismisses the source or inserts into the target")

        let denied = InsertionEnvironment()
        denied.state.accessibilityGranted = false
        let deniedOutcome = await Coordinator.use(text, insert: true, environment: denied.environment)
        try expect(deniedOutcome == .permissionDenied && denied.clipboard == text,
                   "Denied accessibility retains the copied text and reports permissionDenied")
        try expect(denied.sourceDismissals == 0 && denied.targetActivations == 0 && denied.insertionRequests.isEmpty,
                   "Denied accessibility keeps the popup available and never switches applications")

        for target in [Coordinator.TargetState.missing, .terminated] {
            let unavailable = InsertionEnvironment()
            unavailable.state.target = target
            let result = await Coordinator.use(text, insert: true, environment: unavailable.environment)
            try expect(result == (target == .missing ? .noTarget : .targetExited),
                       "A missing or terminated target has an explicit outcome")
            try expect(unavailable.sourceDismissals == 0 && unavailable.targetActivations == 0 && unavailable.insertionRequests.isEmpty,
                       "An unavailable target leaves the popup open without requesting insertion")
        }

        let copyOnly = InsertionEnvironment()
        copyOnly.state.accessibilityGranted = false
        let copied = await Coordinator.use(text, insert: false, environment: copyOnly.environment)
        try expect(copied == .copied && copyOnly.clipboard == text,
                   "Copy-only succeeds without accessibility permission")
        try expect(copyOnly.sourceDismissals == 1 && copyOnly.targetActivations == 1 && copyOnly.insertionRequests.isEmpty,
                   "Copy-only restores the captured application without sending a keyboard event")

        let copyWithoutTarget = InsertionEnvironment()
        copyWithoutTarget.state.target = .missing
        copyWithoutTarget.state.accessibilityGranted = false
        let copiedWithoutTarget = await Coordinator.use(text, insert: false, environment: copyWithoutTarget.environment)
        try expect(copiedWithoutTarget == .copied && copyWithoutTarget.sourceDismissals == 1,
                   "Copy-only remains usable when opened from the host application without a target")
        try expect(copyWithoutTarget.targetActivations == 0 && copyWithoutTarget.insertionRequests.isEmpty,
                   "Copy-only never tries to activate a missing target")

        let delayedActivation = InsertionEnvironment()
        delayedActivation.state.frontmost = .host
        delayedActivation.onPause = { tick in
            try expect(delayedActivation.insertionRequests.isEmpty,
                       "Paste is not posted while the target has not become frontmost")
            if tick == 2 { delayedActivation.state.frontmost = .target }
        }
        let activated = await Coordinator.use(text, insert: true, environment: delayedActivation.environment)
        try expect(activated == .pasteRequested && delayedActivation.pauseCount == 2,
                   "The coordinator waits for the captured target to become frontmost")
        try expect(delayedActivation.sourceDismissals == 1 && delayedActivation.targetActivations == 1,
                   "Waiting does not repeatedly dismiss or reactivate applications")

        let neverFocused = InsertionEnvironment()
        neverFocused.state.frontmost = .host
        let noFocus = await Coordinator.use(text, insert: true, environment: neverFocused.environment)
        try expect(noFocus == .focusFailed && neverFocused.pauseCount == 20,
                   "Focus restoration has a bounded wait and reports focusFailed")
        try expect(neverFocused.insertionRequests.isEmpty, "An unfocused target never receives a paste request")

        let sourceInterruptions: [(String, Coordinator.Outcome, (InsertionEnvironment) -> Void)] = [
            ("feature disable", .cancelled, { $0.state.isAvailable = false }),
            ("source focus loss", .focusFailed, { $0.state.sourceIsFocused = false }),
            ("switch to another app", .cancelled, { $0.state.frontmost = .other }),
            ("copy in another app", .cancelled, { $0.state.frontmost = .other; $0.state.clipboardMatches = false }),
            ("clipboard content replacement", .clipboardChanged, { $0.state.clipboardMatches = false })
        ]
        for (name, expected, interrupt) in sourceInterruptions {
            let interrupted = InsertionEnvironment()
            interrupted.returnKeyHeld = true
            interrupted.onPause = { _ in
                interrupt(interrupted)
                interrupted.returnKeyHeld = false
            }
            let result = await Coordinator.use(text, insert: true, environment: interrupted.environment)
            try expect(result == expected, "Waiting for key release detects \(name)")
            try expect(interrupted.sourceDismissals == 0 && interrupted.targetActivations == 0 && interrupted.insertionRequests.isEmpty,
                       "\(name) during key release cannot dismiss, reactivate or insert")
        }

        let focusInterruptions: [(String, Coordinator.Outcome, (InsertionEnvironment) -> Void)] = [
            ("feature disable", .cancelled, { $0.state.isAvailable = false }),
            ("switch to another app", .cancelled, { $0.state.frontmost = .other }),
            ("copy in another app", .cancelled, { $0.state.frontmost = .other; $0.state.clipboardMatches = false }),
            ("clipboard content replacement", .clipboardChanged, { $0.state.clipboardMatches = false }),
            ("permission revocation", .permissionDenied, { $0.state.accessibilityGranted = false }),
            ("target exit", .targetExited, { $0.state.target = .terminated }),
            ("target disappearance", .noTarget, { $0.state.target = .missing })
        ]
        for (name, expected, interrupt) in focusInterruptions {
            let interrupted = InsertionEnvironment()
            interrupted.onPause = { tick in
                if tick == 1 { interrupt(interrupted) }
                else { interrupted.state.frontmost = .target }
            }
            let result = await Coordinator.use(text, insert: true, environment: interrupted.environment)
            try expect(result == expected && interrupted.pauseCount == 1,
                       "Focus restoration immediately detects \(name), even if the target would later reactivate")
            try expect(interrupted.sourceDismissals == 1 && interrupted.targetActivations == 1 && interrupted.insertionRequests.isEmpty,
                       "\(name) after dismissal never posts paste or retries activation")
        }

        let cancelledBeforeStart = InsertionEnvironment()
        let preCancelled = Task { @MainActor in
            await Coordinator.use(text, insert: true, environment: cancelledBeforeStart.environment)
        }
        preCancelled.cancel()
        let preCancelledOutcome = await preCancelled.value
        try expect(preCancelledOutcome == .cancelled && cancelledBeforeStart.copiedValues.isEmpty,
                   "A pre-cancelled attempt does not overwrite the clipboard")
        try expect(cancelledBeforeStart.sourceDismissals == 0 && cancelledBeforeStart.targetActivations == 0,
                   "A pre-cancelled attempt does not change focus")

        for duringKeyRelease in [true, false] {
            let cancelled = InsertionEnvironment()
            cancelled.returnKeyHeld = duringKeyRelease
            cancelled.onPause = { _ in
                // A fake clock can return normally even after the task was cancelled.
                withUnsafeCurrentTask { $0?.cancel() }
                cancelled.returnKeyHeld = false
            }
            let running = Task { @MainActor in
                await Coordinator.use(text, insert: true, environment: cancelled.environment)
            }
            let result = await running.value
            try expect(result == .cancelled && cancelled.pauseCount == 1 && cancelled.insertionRequests.isEmpty,
                       "Cancellation after a normally-returning pause prevents insertion in either waiting phase")
            try expect(cancelled.sourceDismissals == (duringKeyRelease ? 0 : 1),
                       "Cancellation during key release preserves the source popup")
        }

        let throwingClock = InsertionEnvironment()
        throwingClock.onPause = { _ in throw CancellationError() }
        let interruptedSleep = await Coordinator.use(text, insert: true, environment: throwingClock.environment)
        try expect(interruptedSleep == .cancelled && throwingClock.insertionRequests.isEmpty,
                   "A cancelled or failed pause never falls through to paste")

        let writeFailure = InsertionEnvironment()
        writeFailure.clipboardWriteSucceeds = false
        let failedCopy = await Coordinator.use(text, insert: true, environment: writeFailure.environment)
        try expect(failedCopy == .copyFailed && writeFailure.sourceDismissals == 0 && writeFailure.targetActivations == 0,
                   "A clipboard write failure leaves the popup open and preserves focus")
        try expect(writeFailure.pauseCount == 0 && writeFailure.insertionRequests.isEmpty,
                   "A clipboard write failure does not start insertion")

        let activationFailure = InsertionEnvironment()
        activationFailure.activationSucceeds = false
        let failedActivation = await Coordinator.use(text, insert: true, environment: activationFailure.environment)
        try expect(failedActivation == .focusFailed && activationFailure.targetActivations == 1 && activationFailure.insertionRequests.isEmpty,
                   "A rejected activation does not send paste or repeatedly steal focus")

        let eventFailure = InsertionEnvironment()
        eventFailure.eventSucceeds = false
        let failedEvent = await Coordinator.use(text, insert: true, environment: eventFailure.environment)
        try expect(failedEvent == .eventFailed && eventFailure.insertionRequests == [text],
                   "A failed event request is reported without retrying a possibly-delivered paste")
    }
}
