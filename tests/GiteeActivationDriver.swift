// Explicit CI-only synthetic focus driver. Not part of the application target.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3, let pid = Int32(args[1]), let target = NSRunningApplication(processIdentifier: pid) else { exit(2) }
let hiddenMode = args.count > 3 && args[3] == "hidden"
let output = URL(fileURLWithPath: args[2])
let ready = output.appendingPathExtension("ready")
let app = NSApplication.shared
app.setActivationPolicy(hiddenMode ? .accessory : .regular)
var window: NSWindow?
if !hiddenMode {
    window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 350, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window?.title = "ToolIsle synthetic focus driver"
    window?.makeKeyAndOrderFront(nil)
}
var report: [String: Any] = ["driver_pid": ProcessInfo.processInfo.processIdentifier, "target_pid": pid, "synthetic_driver": true, "native_cmd_tab_tested": false, "hidden_mode": hiddenMode]
func finish(_ error: String? = nil) {
    if let error { report["error"] = error }
    report["target_active"] = target.isActive
    report["target_hidden"] = target.isHidden
    try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    app.terminate(nil)
}
@MainActor func commandTab() async {
    report["native_cmd_tab_tested"] = true
    let source = CGEventSource(stateID: .hidSystemState)
    for (key, down, flags): (CGKeyCode, Bool, CGEventFlags) in [(55, true, .maskCommand), (48, true, .maskCommand), (48, false, .maskCommand), (55, false, [])] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    for _ in 0..<30 {
        if target.isActive && !target.isHidden { break }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    report["native_cmd_tab_returned_to_reader"] = target.isActive && !target.isHidden
}
DispatchQueue.main.async {
    try? String(ProcessInfo.processInfo.processIdentifier).write(to: ready, atomically: true, encoding: .utf8)
    if !hiddenMode { app.activate() }
    Task { @MainActor in
        if hiddenMode {
            let front = NSWorkspace.shared.frontmostApplication
            report["external_application_active"] = front?.processIdentifier != pid
            report["external_bundle_identifier"] = front?.bundleIdentifier ?? "unknown"
            guard CGPreflightPostEventAccess() else { finish("CI has no permission to post Cmd-Tab"); return }
            await commandTab()
            finish(target.isActive ? nil : "Cmd-Tab did not restore the hidden application")
            return
        }
        for _ in 0..<40 {
            if app.isActive { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        report["external_application_active"] = app.isActive
        guard app.isActive else { finish("Driver did not receive activation"); return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        if CGPreflightPostEventAccess() { await commandTab() }
        if !target.isActive {
            app.yieldActivation(to: target)
            target.unhide()
            target.activate(options: [.activateAllWindows])
            report["cooperative_activation_used"] = true
        }
        for _ in 0..<40 {
            if target.isActive { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        finish(target.isActive ? nil : "Target did not receive activation")
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 12) { finish("Driver deadline exceeded") }
app.run()
