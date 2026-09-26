// SPDX-License-Identifier: GPL-3.0-or-later
// Run: swiftc DynamicIsland/ToolIsleFeatures/Thaw/ThawProtocol.swift tests/ThawProtocolRegression.swift -o /tmp/thaw-protocol-regression && /tmp/thaw-protocol-regression
import Foundation

@main
struct ThawProtocolRegression {
    static func main() throws {
        var checks = 0
        func expect(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            checks += 1
        }
        func rejects(_ name: String, _ operation: () throws -> Void) {
            do {
                try operation()
                fatalError("Expected rejection: \(name)")
            } catch {
                checks += 1
            }
        }
        let requestID = UUID(uuidString: "17A1D0D5-F3C6-4220-A015-2C7C310178AB")!
        func callback(_ json: String, host: String = "settings", duplicateData: Bool = false) -> URL {
            var parts = URLComponents()
            parts.scheme = "toolisle-thaw"
            parts.host = host
            parts.queryItems = [URLQueryItem(name: "data", value: json)]
            if duplicateData { parts.queryItems!.append(URLQueryItem(name: "data", value: json)) }
            return parts.url!
        }
        func query(_ url: URL) -> [String: String] {
            Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map {
                ($0.name, $0.value ?? "")
            })
        }

        // These are commands, not an idempotent show/hide API. Runtime retry behavior is outside this check.
        expect(ThawProtocol.action(.toggleHidden).absoluteString == "thaw://toggle-hidden", "toggle remains the exact one-shot command URI")
        expect(ThawProtocol.action(.search).absoluteString == "thaw://search", "search command")
        expect(ThawProtocol.action(.openSettings).absoluteString == "thaw://open-settings", "settings command")
        expect(ThawSettingKey(rawValue: "arbitraryDefaultsKey") == nil, "unlisted settings cannot enter the typed API")

        for (key, value) in [(ThawSettingKey.autoRehide, ThawSettingValue.bool(true)),
                             (.showOnHover, .bool(false)), (.useIceBar, .bool(true)),
                             (.rehideStrategy, .text("focusedApp")), (.rehideInterval, .number(300)),
                             (.showOnHoverDelay, .number(0))] {
            let values = query(try ThawProtocol.set(key, value: value, display: nil))
            expect(values["key"] == key.rawValue && values["value"] != nil, "supported setting is expressible: \(key.rawValue)")
        }
        for (key, value) in [(ThawSettingKey.autoRehide, ThawSettingValue.number(1)),
                             (.showOnHover, .text("true")), (.rehideInterval, .bool(true)),
                             (.rehideStrategy, .text("unknown")), (.rehideInterval, .number(0)),
                             (.rehideInterval, .number(301)), (.showOnHoverDelay, .number(-0.1)),
                             (.showOnHoverDelay, .number(5.1)), (.showOnHoverDelay, .number(.nan)),
                             (.rehideInterval, .number(.infinity))] {
            rejects("invalid type or range: \(key.rawValue)") {
                _ = try ThawProtocol.set(key, value: value, display: nil)
            }
        }

        let screen = "screen & 外接 + /?="
        let getURL = ThawProtocol.get(.useIceBar, id: requestID, display: screen)
        let get = query(getURL)
        expect(getURL.host == "get" && get["display"] == screen, "screen selector survives URL query encoding")
        expect(get["callback"] == "toolisle-thaw://settings" && get["requestId"] == requestID.uuidString, "read includes the explicit callback and correlation ID")
        expect(query(ThawProtocol.get(.autoRehide, id: requestID, display: screen))["display"] == nil, "global setting is not scoped to a display")
        expect(query(try ThawProtocol.set(.useIceBar, value: .bool(false), display: screen))["display"] == screen, "write preserves the captured display selector")

        // Fixtures use the shape sent by Thaw 2.0.1's SettingsURIHandler.
        let boolean = #"{"status":"success","requestId":"17A1D0D5-F3C6-4220-A015-2C7C310178AB","key":"autoRehide","data":{"type":"boolean","value":true}}"#
        let number = #"{"status":"success","requestId":"17A1D0D5-F3C6-4220-A015-2C7C310178AB","key":"showOnHoverDelay","data":{"type":"double","value":0.5}}"#
        let strategy = #"{"status":"success","requestId":"17A1D0D5-F3C6-4220-A015-2C7C310178AB","key":"rehideStrategy","data":{"type":"enum","value":"smart"}}"#
        expect(try ThawProtocol.response(callback(boolean), id: requestID, key: .autoRehide) == .bool(true), "boolean readback")
        expect(try ThawProtocol.response(callback(number), id: requestID, key: .showOnHoverDelay) == .number(0.5), "number readback")
        expect(try ThawProtocol.response(callback(strategy), id: requestID, key: .rehideStrategy) == .text("smart"), "strategy readback")
        rejects("wrong callback host") {
            _ = try ThawProtocol.response(callback(boolean, host: "unrelated"), id: requestID, key: .autoRehide)
        }
        rejects("unsolicited correlation ID") {
            _ = try ThawProtocol.response(callback(boolean), id: UUID(), key: .autoRehide)
        }
        rejects("duplicate callback payload") {
            _ = try ThawProtocol.response(callback(boolean, duplicateData: true), id: requestID, key: .autoRehide)
        }
        rejects("response for a different setting") {
            _ = try ThawProtocol.response(callback(boolean), id: requestID, key: .showOnHover)
        }
        rejects("JSON number must not become a boolean") {
            _ = try ThawProtocol.response(callback(boolean.replacingOccurrences(of: "true", with: "1")), id: requestID, key: .autoRehide)
        }
        rejects("JSON boolean must not become a number") {
            _ = try ThawProtocol.response(callback(number.replacingOccurrences(of: "0.5", with: "true")), id: requestID, key: .showOnHoverDelay)
        }
        rejects("out-of-range readback") {
            _ = try ThawProtocol.response(callback(number.replacingOccurrences(of: "0.5", with: "6")), id: requestID, key: .showOnHoverDelay)
        }
        rejects("unknown strategy readback") {
            _ = try ThawProtocol.response(callback(strategy.replacingOccurrences(of: "smart", with: "newStrategy")), id: requestID, key: .rehideStrategy)
        }
        let remoteError = #"{"status":"error","requestId":"17A1D0D5-F3C6-4220-A015-2C7C310178AB","error":"not_authorized"}"#
        do {
            _ = try ThawProtocol.response(callback(remoteError), id: requestID, key: .autoRehide)
            fatalError("Remote denial must not be interpreted as a value")
        } catch ThawError.remote(let message) {
            expect(message == "not_authorized", "remote error remains distinguishable from malformed data")
        }
        rejects("partial readback must not create fake defaults") {
            _ = try ThawSettings(values: [.autoRehide: .bool(true)])
        }
        print("PASS: \(checks) Thaw protocol checks; no apps launched or runtime retry behavior inferred.")
    }
}
