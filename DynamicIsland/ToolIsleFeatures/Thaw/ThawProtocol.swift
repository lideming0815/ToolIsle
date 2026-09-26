// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreFoundation

enum ThawAction: String, CaseIterable {
    case toggleHidden = "toggle-hidden", search, openSettings = "open-settings"
}

enum ThawSettingValue: Equatable {
    case bool(Bool), number(Double), text(String)
    var queryValue: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return String(value)
        case .text(let value): return value
        }
    }
}

enum ThawSettingKey: String, CaseIterable {
    case autoRehide, rehideStrategy, rehideInterval, showOnHover, showOnHoverDelay, useIceBar

    func accepts(_ value: ThawSettingValue) -> Bool {
        switch (self, value) {
        case (.autoRehide, .bool), (.showOnHover, .bool), (.useIceBar, .bool): return true
        case (.rehideStrategy, .text(let value)): return ["smart", "timed", "focusedApp"].contains(value)
        case (.rehideInterval, .number(let value)): return value.isFinite && (1...300).contains(value)
        case (.showOnHoverDelay, .number(let value)): return value.isFinite && (0...5).contains(value)
        default: return false
        }
    }
}

struct ThawSettings {
    var autoRehide: Bool
    var rehideStrategy: String
    var rehideInterval: Double
    var showOnHover: Bool
    var showOnHoverDelay: Double
    var useIceBar: Bool

    init(values: [ThawSettingKey: ThawSettingValue]) throws {
        guard case .bool(let autoRehide) = values[.autoRehide],
              case .text(let rehideStrategy) = values[.rehideStrategy],
              case .number(let rehideInterval) = values[.rehideInterval],
              case .bool(let showOnHover) = values[.showOnHover],
              case .number(let showOnHoverDelay) = values[.showOnHoverDelay],
              case .bool(let useIceBar) = values[.useIceBar] else { throw ThawError.invalidResponse }
        self.autoRehide = autoRehide
        self.rehideStrategy = rehideStrategy
        self.rehideInterval = rehideInterval
        self.showOnHover = showOnHover
        self.showOnHoverDelay = showOnHoverDelay
        self.useIceBar = useIceBar
    }
}

enum ThawError: LocalizedError {
    case invalidResponse, invalidSetting, timeout, missingHelper, incompatibleHelper, conflictingApp(String)
    case unavailable, readbackMismatch, remote(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "菜单栏设置响应无效，请重新读取。"
        case .invalidSetting: return "菜单栏设置值超出允许范围。"
        case .timeout: return "未收到设置响应。请完成 Thaw 的权限引导，点击“授权设置”并允许后重新读取。"
        case .missingHelper: return "安装包缺少 Thaw 组件，请使用完整融合版 DMG。"
        case .incompatibleHelper: return "Thaw 组件身份或版本不匹配，请重新安装完整融合版。"
        case .conflictingApp(let name): return "请先退出 \(name)，再启用菜单栏管理。"
        case .unavailable: return "菜单栏组件未运行，请先启用或重试。"
        case .readbackMismatch: return "设置尚未确认保存，已重新读取实际值。"
        case .remote(let text): return "Thaw 未能读取设置：\(text)"
        }
    }
}

/// Only the six settings and three actions used by our UI cross this interface.
/// Pure Foundation so malformed callbacks and non-idempotent action semantics can be checked without launching apps.
enum ThawProtocol {
    static let helperBundleID = "com.toolisle.Thaw"
    static let helperVersion = "2.0.1"
    static let callbackURL = URL(string: "toolisle-thaw://settings")!

    static func action(_ action: ThawAction) -> URL { url(host: action.rawValue) }
    static var authorize: URL { url(host: "authorize") }

    static func get(_ key: ThawSettingKey, id: UUID, display: String?) -> URL {
        var query = [URLQueryItem(name: "key", value: key.rawValue),
                     URLQueryItem(name: "callback", value: callbackURL.absoluteString),
                     URLQueryItem(name: "requestId", value: id.uuidString)]
        if key == .useIceBar, let display { query.append(URLQueryItem(name: "display", value: display)) }
        return url(host: "get", query: query)
    }

    static func set(_ key: ThawSettingKey, value: ThawSettingValue, display: String?) throws -> URL {
        guard key.accepts(value) else { throw ThawError.invalidSetting }
        var query = [URLQueryItem(name: "key", value: key.rawValue), URLQueryItem(name: "value", value: value.queryValue)]
        if key == .useIceBar, let display { query.append(URLQueryItem(name: "display", value: display)) }
        return url(host: "set", query: query)
    }

    private static func url(host: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents()
        parts.scheme = "thaw"
        parts.host = host
        if !query.isEmpty { parts.queryItems = query }
        return parts.url!
    }

    static func isCallback(_ url: URL) -> Bool { url.scheme?.lowercased() == callbackURL.scheme }

    static func response(_ url: URL, id: UUID, key: ThawSettingKey) throws -> ThawSettingValue {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == callbackURL.scheme, parts.host == callbackURL.host,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              parts.path.isEmpty,
              let items = parts.queryItems, items.count == 1, items[0].name == "data",
              let raw = items[0].value, let data = raw.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let request = payload["requestId"] as? String, UUID(uuidString: request) == id else {
            throw ThawError.invalidResponse
        }
        if payload["status"] as? String == "error" {
            throw ThawError.remote(String((payload["error"] as? String ?? "未知错误").prefix(160)))
        }
        guard payload["status"] as? String == "success", payload["key"] as? String == key.rawValue,
              let result = payload["data"] as? [String: Any] else { throw ThawError.invalidResponse }
        let value: ThawSettingValue
        switch result["type"] as? String {
        case "boolean":
            guard let number = result["value"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw ThawError.invalidResponse
            }
            value = .bool(number.boolValue)
        case "double":
            guard let number = result["value"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                throw ThawError.invalidResponse
            }
            value = .number(number.doubleValue)
        case "enum":
            guard let text = result["value"] as? String else { throw ThawError.invalidResponse }
            value = .text(text)
        default: throw ThawError.invalidResponse
        }
        guard key.accepts(value) else { throw ThawError.invalidResponse }
        return value
    }
}
