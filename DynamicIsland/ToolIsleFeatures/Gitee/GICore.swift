// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum GIProvider: String, Codable, CaseIterable { case gitee, gitlab, github }

/// A credential boundary, not the currently selected UI tab. Legacy keys remain readable.
struct GIReaderRemote: Codable, Hashable {
    let provider: GIProvider
    let gitLabURL: URL?
    static let gitee = GIReaderRemote(provider: .gitee, gitLabURL: nil)
    static let github = GIReaderRemote(provider: .github, gitLabURL: nil)
    private init(provider: GIProvider, gitLabURL: URL?) { self.provider = provider; self.gitLabURL = gitLabURL }
    private enum CodingKeys: String, CodingKey { case provider, gitLabURL }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let url = try c.decodeIfPresent(URL.self, forKey: .gitLabURL)
        let kind = try c.decodeIfPresent(GIProvider.self, forKey: .provider) ?? (url == nil ? .gitee : .gitlab)
        switch kind {
        case .gitee: self = .gitee
        case .github: self = .github
        case .gitlab:
            guard let url else { throw GIServiceError.invalidServer }
            self = try Self.gitLab(url.absoluteString)
        }
    }
    var isGitLab: Bool { provider == .gitlab }
    var isGitHub: Bool { provider == .github }
    var usesHTTP: Bool { webURL.scheme == "http" }
    var name: String { [.gitee: "Gitee", .gitlab: "GitLab", .github: "GitHub"][provider]! }
    var webURL: URL { gitLabURL ?? URL(string: isGitHub ? "https://github.com" : "https://gitee.com")! }
    var storagePrefix: String {
        if isGitHub { return "toolisle.github" }
        guard let gitLabURL else { return "toolisle.gitee" }
        return "toolisle.gitlab." + Data(gitLabURL.absoluteString.utf8).base64EncodedString()
    }
    var credentialService: String { "io.github.lideming0815.toolisle.\(provider.rawValue)-reader" }
    var credentialAccount: String { gitLabURL?.absoluteString ?? (isGitHub ? "github.com" : "gitee.com") }
    var imageOrigins: [String] {
        if isGitHub { return ["https://github.com", "https://user-images.githubusercontent.com", "https://private-user-images.githubusercontent.com", "https://raw.githubusercontent.com"] }
        guard isGitLab else { return ["https://gitee.com", "https://foruda.gitee.com", "https://images.gitee.com"] }
        var c = URLComponents(url: webURL, resolvingAgainstBaseURL: false)!
        c.path = ""
        return [c.url!.absoluteString]
    }
    var tokenURL: URL {
        webURL.appendingPathComponent(isGitHub ? "settings/personal-access-tokens" : (isGitLab ? "-/user_settings/personal_access_tokens" : "profile/personal_access_tokens"))
    }
    func repositoryURL(_ path: String) -> URL {
        var url = webURL
        for part in path.split(separator: "/") { url.appendPathComponent(String(part)) }
        return url
    }
    /// HTTP(S), optional port and reverse-proxy prefix. Never accept an API URL or credentials.
    static func gitLab(_ input: String) throws -> Self {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains("\\"), !value.contains("%"),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              var c = URLComponents(string: value), ["https", "http"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host, !host.isEmpty, host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-:[]".contains($0)) }),
              c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil,
              c.port == nil || (1...65535).contains(c.port!) else { throw GIServiceError.invalidServer }
        let parts = c.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard !parts.contains(where: { $0 == "." || $0 == ".." }), !c.path.contains("//"),
              !c.path.contains("/api/") else { throw GIServiceError.invalidServer }
        c.scheme = c.scheme?.lowercased(); c.host = host.lowercased()
        if c.port == (c.scheme == "http" ? 80 : 443) { c.port = nil }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        guard let url = c.url else { throw GIServiceError.invalidServer }
        return GIReaderRemote(provider: .gitlab, gitLabURL: url)
    }
    func contains(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.scheme?.lowercased() == webURL.scheme else { return false }
        if isGitHub { return url.host?.lowercased() == "github.com" && (url.port == nil || url.port == 443) }
        if !isGitLab { return GIIssueLinks.hosts.contains(url.host?.lowercased() ?? "") && (url.port == nil || url.port == 443) }
        let defaultPort = usesHTTP ? 80 : 443
        guard url.host?.lowercased() == webURL.host?.lowercased(), (url.port ?? defaultPort) == (webURL.port ?? defaultPort) else { return false }
        return webURL.path.isEmpty || url.path == webURL.path || url.path.hasPrefix(webURL.path + "/")
    }
    static func validProject(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { GIRepositoryAddress.validSlug(String($0)) && $0 != "-" }
    }
    static func validIID(_ number: String) -> Bool {
        !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber } && (Int64(number) ?? 0) > 0
    }
    func issueRoute(_ url: URL) -> GIIssueRoute? {
        if isGitHub {
            guard contains(url), let c = URLComponents(url: url, resolvingAgainstBaseURL: false), !c.percentEncodedPath.contains("%") else { return nil }
            let p = url.path.split(separator: "/").map(String.init)
            guard p.count == 4, p[2] == "issues", p.prefix(2).allSatisfy(GIRepositoryAddress.validSlug), Self.validIID(p[3]) else { return nil }
            return GIIssueRoute(repository: p.prefix(2).joined(separator: "/").lowercased(), number: String(Int64(p[3])!), remote: self)
        }
        guard isGitLab, contains(url),
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !c.percentEncodedPath.contains("%") else { return nil }
        let prefix = webURL.path.split(separator: "/").count
        let parts = url.path.split(separator: "/").dropFirst(prefix).map(String.init)
        guard parts.count >= 5, parts[parts.count-3] == "-", parts[parts.count-2] == "issues",
              let number = parts.last, Self.validIID(number) else { return nil }
        let project = parts.dropLast(3).joined(separator: "/")
        guard Self.validProject(project) else { return nil }
        return GIIssueRoute(repository: project, number: number, remote: self)
    }
}

protocol GIIssueService: AnyObject, Sendable {
    func cancel()
    func user() async throws -> GIUser
    func repositories(source: String, page: Int) async throws -> [GIRepository]
    func issues(repository: String, page: Int) async throws -> [GIIssue]
    func issue(_ route: GIIssueRoute) async throws -> GIIssue
    func comments(_ route: GIIssueRoute, page: Int) async throws -> [GIComment]
    func repositoryPage(source: String, page: Int) async throws -> GIResultPage<GIRepository>
    func issuePage(repository: String, page: Int) async throws -> GIResultPage<GIIssue>
    func commentPage(_ route: GIIssueRoute, page: Int) async throws -> GIResultPage<GIComment>
}

/// Pagination metadata is determined BEFORE any provider-specific filtering (e.g. GitHub PRs).
struct GIResultPage<Item> {
    let items: [Item]
    let nextPage: Int?
}
extension GIIssueService {
    func repositoryPage(source: String, page: Int) async throws -> GIResultPage<GIRepository> {
        let values = try await repositories(source: source, page: page)
        return GIResultPage(items: values, nextPage: values.count == 50 ? page + 1 : nil)
    }
    func issuePage(repository: String, page: Int) async throws -> GIResultPage<GIIssue> {
        let values = try await issues(repository: repository, page: page)
        return GIResultPage(items: values, nextPage: values.count == 50 ? page + 1 : nil)
    }
    func commentPage(_ route: GIIssueRoute, page: Int) async throws -> GIResultPage<GIComment> {
        let values = try await comments(route, page: page)
        return GIResultPage(items: values, nextPage: values.count == 50 ? page + 1 : nil)
    }
}

struct GIUser: Codable, Hashable {
    let id: Int64
    let login: String
    let name: String?
    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? login }
}

/// Minimal namespace metadata; deliberately distinct from the display name.
struct GIRepositorySpace: Codable, Hashable {
    let path: String?
    let login: String?
}

enum GIRepositoryAddress {
    /// Only legacy URL/full_name fallbacks lose the clone suffix. Explicit API
    /// path metadata is authoritative and is never blindly renamed.
    static func legacyPath(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if raw.contains("://") {
            guard let c = URLComponents(string: raw),
                  ["https", "http"].contains(c.scheme?.lowercased() ?? ""),
                  GIIssueLinks.hosts.contains(c.host?.lowercased() ?? ""),
                  c.user == nil, c.password == nil,
                  c.port == nil || c.port == (c.scheme == "https" ? 443 : 80),
                  !c.percentEncodedPath.lowercased().contains("%2f"),
                  !c.percentEncodedPath.lowercased().contains("%5c") else { return nil }
            candidate = c.path
        } else if raw.hasPrefix("git@gitee.com:") {
            candidate = String(raw.dropFirst("git@gitee.com:".count))
        } else {
            guard !raw.contains("://"), !raw.contains(":"), !raw.contains("?"), !raw.contains("#") else { return nil }
            candidate = raw
        }
        var parts = candidate.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[1].hasSuffix(".git") { parts[1].removeLast(4) }
        guard parts.allSatisfy(validSlug) else { return nil }
        return parts.joined(separator: "/")
    }
    static func validSlug(_ part: String) -> Bool {
        GIIssueLinks.validPart(part) && !part.contains("%") && !part.contains(":") &&
        !part.contains("?") && !part.contains("#") && !part.contains("@") &&
        !part.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
    }
}

struct GIRepository: Codable, Identifiable, Hashable {
    let id: Int64
    let full_name: String
    let name: String
    let description: String?
    let html_url: String?
    let gitLabPath: String?
    var readerRemote: GIReaderRemote? = nil
    var remote: GIReaderRemote { readerRemote ?? .gitee }
    var canonicalURL: String { remote.repositoryURL(remote.isGitHub ? path.lowercased() : path).absoluteString }
    var scopedID: String { remote.storagePrefix + ":" + String(id) }
    func on(_ site: GIReaderRemote) -> Self { var copy = self; copy.readerRemote = site == .gitee ? nil : site; return copy }
    let repositoryPath: String?
    let namespace: GIRepositorySpace?
    let owner: GIRepositorySpace?
    enum CodingKeys: String, CodingKey {
        case id, full_name, name, description, html_url, namespace, owner, gitLabPath, readerRemote
        case repositoryPath = "path"
    }
    init(id: Int64, full_name: String, name: String, description: String?, html_url: String?,
         gitLabPath: String? = nil, repositoryPath: String? = nil, namespace: GIRepositorySpace? = nil, owner: GIRepositorySpace? = nil) {
        self.id = id; self.full_name = full_name; self.name = name
        self.description = description; self.html_url = html_url
        self.gitLabPath = gitLabPath; self.repositoryPath = repositoryPath; self.namespace = namespace; self.owner = owner
    }
    var path: String {
        if remote.isGitHub {
            let parts = full_name.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy({ GIRepositoryAddress.validSlug(String($0)) }) ? full_name : ""
        }
        if let gitLabPath { return GIReaderRemote.validProject(gitLabPath) ? gitLabPath : "" }
        let web = html_url.flatMap(GIRepositoryAddress.legacyPath)
        let fallback = GIRepositoryAddress.legacyPath(full_name)
        if let repo = repositoryPath, GIRepositoryAddress.validSlug(repo) {
            let space = [namespace?.path, web?.split(separator: "/").first.map(String.init),
                         fallback?.split(separator: "/").first.map(String.init), owner?.path, owner?.login]
                .compactMap { $0 }.first(where: GIRepositoryAddress.validSlug)
            if let space { return "\(space)/\(repo)" }
        }
        return web ?? fallback ?? ""
    }
}

/// Read-only label metadata. Invalid optional entries never discard an Issue.
struct GIIssueLabel: Codable, Hashable {
    let id: Int64?
    let name: String
    let color: String?
    init(id: Int64? = nil, name: String, color: String? = nil) {
        self.id = id; self.name = name; self.color = color
    }
    enum CodingKeys: String, CodingKey { case id, name, color }
    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(name: text); return
        }
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init(name: ""); return
        }
        self.init(id: try? c.decode(Int64.self, forKey: .id),
                  name: (try? c.decode(String.self, forKey: .name)) ?? "",
                  color: try? c.decode(String.self, forKey: .color))
    }
    var key: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hexColor: String? {
        guard var value = color?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return value.uppercased()
    }
}

/// No guessed numeric workflow-state mapping. Unknown states remain visible and selectable.
enum GIStateProjection {
    static let standard = ["all", "unfinished", "progressing", "closed", "open", "rejected"]
    static func canonical(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "opened", "open": return "open"
        case "in_progress", "in-progress", "in progress", "progressing": return "progressing"
        case "closed": return "closed"
        case "rejected": return "rejected"
        default: return value
        }
    }
    static func title(_ key: String) -> String {
        if let pair = customParts(key) { return "\(pair[1])（\(title(pair[0]))）" }
        return ["all":"全部", "unfinished":"未完成", "open":"开启", "progressing":"进行中", "closed":"已关闭", "rejected":"已拒绝"][canonical(key)] ?? key
    }
    static func customParts(_ key: String) -> [String]? {
        guard key.hasPrefix("status:"), let data = Data(base64Encoded: String(key.dropFirst(7))),
              let pair = try? JSONDecoder().decode([String].self, from: data), pair.count == 2,
              !pair[0].hasPrefix("status:") else { return nil }
        return pair
    }
    static func customKey(base: String, title: String) -> String {
        "status:" + (try! JSONEncoder().encode([base, title])).base64EncodedString()
    }
    static func matches(_ issue: GIIssue, filter: String) -> Bool {
        if filter == "all" { return true }
        if filter == "unfinished" { return ["open", "progressing"].contains(issue.projectedState) }
        if filter.hasPrefix("status:") { return filter == issue.statusFilterKey }
        return canonical(filter) == issue.projectedState
    }
}
struct GIWorkflowState: Codable {
    let title: String?
    let name: String?
    let state: String?
    private enum CodingKeys: String, CodingKey { case title, name, state }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(String.self, forKey: .title)
        name = try? c.decode(String.self, forKey: .name)
        state = try? c.decode(String.self, forKey: .state)
    }
    var displayName: String? {
        [title, name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}

struct GIIssue: Codable, Identifiable {
    let id: Int64
    let number: String
    let title: String
    let state: String
    let body: String?
    let html_url: String?
    let user: GIUser?
    let updated_at: String?
    let comments: Int?
    /// nil means the response did not provide usable label metadata; [] means none.
    var labels: [GIIssueLabel]? = nil
    var issue_state: GIWorkflowState? = nil
    var projectedState: String {
        let base = GIStateProjection.canonical(state)
        // A known transport state wins; custom titles and numeric IDs are NOT lifecycle states.
        if ["open", "progressing", "closed", "rejected"].contains(base) { return base }
        if let nested = issue_state?.state {
            let key = GIStateProjection.canonical(nested)
            if ["open", "progressing", "closed", "rejected"].contains(key) { return key }
        }
        return base
    }
    var statusFilterKey: String {
        guard let title = issue_state?.displayName, title != GIStateProjection.title(projectedState) else { return projectedState }
        return GIStateProjection.customKey(base: projectedState, title: title)
    }
    enum CodingKeys: String, CodingKey { case id, number, title, state, body, html_url, user, updated_at, comments, labels, issue_state }
    init(id: Int64, number: String, title: String, state: String, body: String?, html_url: String?,
         user: GIUser?, updated_at: String?, comments: Int?, labels: [GIIssueLabel]? = nil) {
        self.id = id; self.number = number; self.title = title; self.state = state
        self.body = body; self.html_url = html_url; self.user = user
        self.updated_at = updated_at; self.comments = comments; self.labels = labels
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        state = try c.decode(String.self, forKey: .state)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        html_url = try c.decodeIfPresent(String.self, forKey: .html_url)
        user = try c.decodeIfPresent(GIUser.self, forKey: .user)
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)
        comments = try c.decodeIfPresent(Int.self, forKey: .comments)
        labels = try? c.decode([GIIssueLabel].self, forKey: .labels)
        issue_state = try? c.decode(GIWorkflowState.self, forKey: .issue_state)
    }
    var visibleLabels: [GIIssueLabel] {
        var seen = Set<String>()
        return (labels ?? []).filter { !$0.key.isEmpty && seen.insert($0.key).inserted }
    }
    var stateTitle: String { issue_state?.displayName ?? GIStateProjection.title(projectedState) }
}

struct GIComment: Codable, Identifiable {
    let id: Int64
    let body: String?
    let user: GIUser?
    let created_at: String?
}

struct GIIssueRoute: Codable, Hashable {
    let repository: String
    let number: String
    let remote: GIReaderRemote?
    init(repository: String, number: String, remote: GIReaderRemote = .gitee) {
        self.repository = remote.isGitHub ? repository.lowercased() : repository; self.number = number
        self.remote = remote == .gitee ? nil : remote
    }
    var url: URL {
        var result = (remote ?? .gitee).webURL
        for part in repository.split(separator: "/") { result.appendPathComponent(String(part)) }
        if remote?.isGitLab == true { result.appendPathComponent("-") }
        result.appendPathComponent("issues")
        result.appendPathComponent(number)
        return result
    }
    var label: String { "\(repository) #\(number)" }
    var repositoryURL: String { (remote ?? .gitee).repositoryURL(repository).absoluteString }
}

enum GILinkTarget: Equatable {
    case issue(GIIssueRoute, fragment: String?)
    case external(URL)
    case blocked
}

enum GIIssueLinks {
    static let hosts: Set<String> = ["gitee.com", "www.gitee.com"]

    /// Only real user-clicked links reach this resolver. Do not run it over code blocks.
    /// Preserve issue-number case; Gitee identifiers are not integer issue IDs.
    static func resolve(_ raw: String, relativeTo base: URL, remote: GIReaderRemote = .gitee) -> GILinkTarget {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\\"),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: true),
              c.user == nil, c.password == nil else { return .blocked }
        let scheme = c.scheme?.lowercased() ?? ""
        guard ["https", "http", "mailto"].contains(scheme) else { return .blocked }
        // Credentials must never be propagated into browser navigation or logging.
        let sensitive = Set(["access_token", "token", "authorization", "private_token"])
        if (c.queryItems ?? []).contains(where: { sensitive.contains($0.name.lowercased()) }) { return .blocked }
        guard scheme != "mailto" else { return .external(url) }
        guard let host = c.host?.lowercased(), !host.isEmpty else { return .blocked }
        if remote.isGitLab || remote.isGitHub {
            if let route = remote.issueRoute(url) {
                return .issue(route, fragment: c.fragment.flatMap { $0.isEmpty ? nil : $0 })
            }
            return .external(url)
        }
        guard hosts.contains(host), c.port == nil || c.port == (scheme == "https" ? 443 : 80) else {
            return .external(url)
        }
        // Reject encoded separators rather than reinterpreting a malformed path.
        let encoded = c.percentEncodedPath.lowercased()
        if encoded.contains("%2f") || encoded.contains("%5c") { return .external(url) }
        let parts = c.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[2] == "issues",
              validPart(parts[0]), validPart(parts[1]),
              !parts[3].isEmpty,
              parts[3].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            return .external(url)
        }
        guard let repository = GIRepositoryAddress.legacyPath("\(parts[0])/\(parts[1])") else { return .external(url) }
        return .issue(GIIssueRoute(repository: repository, number: parts[3]), fragment: c.fragment.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func validPart(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
        !value.contains("/") && !value.contains("\\") &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    /// Known comment anchor spellings; unknown anchors remain available for browser fallback.
    static func commentID(_ fragment: String?) -> Int64? {
        guard let fragment else { return nil }
        for prefix in ["note_", "issuecomment-", "comment-", "comment_"] where fragment.hasPrefix(prefix) {
            return Int64(fragment.dropFirst(prefix.count))
        }
        return nil
    }
}

struct GIVisit: Identifiable {
    let id = UUID()
    let route: GIIssueRoute
    let fragment: String?
    var scrollY: Double = 0
    var anchorHandled = false
    var sourceURL: URL {
        var c = URLComponents(url: route.url, resolvingAgainstBaseURL: false)!
        c.fragment = fragment
        return c.url ?? route.url
    }
}

struct GIHistory {
    private(set) var visits: [GIVisit] = []
    private(set) var position = -1
    var current: GIVisit? { visits.indices.contains(position) ? visits[position] : nil }
    var canBack: Bool { position > 0 }
    var canForward: Bool { position >= 0 && position + 1 < visits.count }
    mutating func push(_ route: GIIssueRoute, fragment: String? = nil) {
        if current?.route == route && current?.fragment == nil && fragment == nil { return }
        if position + 1 < visits.count { visits.removeSubrange((position + 1)..<visits.count) }
        visits.append(GIVisit(route: route, fragment: fragment))
        if visits.count > 100 { visits.removeFirst(visits.count - 100) }
        position = visits.count - 1
    }
    mutating func move(_ offset: Int) {
        guard visits.indices.contains(position + offset) else { return }
        position += offset
    }
    mutating func snapshot(id: UUID, y: Double, anchorHandled: Bool? = nil) {
        guard let i = visits.firstIndex(where: { $0.id == id }) else { return }
        visits[i].scrollY = y.isFinite ? max(0, y) : 0
        if let anchorHandled { visits[i].anchorHandled = anchorHandled }
    }
    mutating func remove(remote: GIReaderRemote) {
        let currentID = current?.id
        let keep = visits.enumerated().filter { ($0.element.route.remote ?? .gitee) != remote }
        let previous = keep.lastIndex { $0.offset <= position }
        visits = keep.map(\.element)
        position = currentID.flatMap { id in visits.firstIndex { $0.id == id } } ?? previous ?? (visits.isEmpty ? -1 : 0)
    }
    mutating func reset() { self = GIHistory() }
}

struct GIListItem: Identifiable {
    let route: GIIssueRoute
    let issue: GIIssue
    var id: GIIssueRoute { route }
}

struct GIPage {
    var issue: GIIssue
    var comments: [GIComment]
    var nextCommentPage: Int
    var hasMoreComments: Bool
    var revision = UUID()
}

struct GIRepositoryFailure: Identifiable {
    let repository: String
    let message: String
    let status: Int?
    var id: String { repository }
    init(repository: String, error: Error) {
        self.repository = repository
        self.message = GIServiceError.message(error)
        switch error as? GIServiceError {
        case .missingToken: status = 401
        case .forbidden: status = 403
        case .missing: status = 404
        case .throttled, .throttledUntil: status = 429
        case .response(let code): status = code
        default: status = nil
        }
    }
}

enum GIServiceError: Error, LocalizedError {
    case missingToken, forbidden, missing, throttled, response(Int), format, tooLarge, unsafeRedirect, invalidServer
    case throttledUntil(Date)
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "请输入有效的 GitLab HTTP 或 HTTPS 站点地址，不含令牌、查询参数或 /api/v4。"
        case .missingToken: return "授权已失效，请重新连接账户。"
        case .forbidden: return "当前账户没有权限，或接口暂时限制访问。请检查令牌权限后重试。"
        case .missing: return "该内容不存在，或当前账户没有访问权限。"
        case .throttledUntil(let date): return "接口限流，请在 \(date.formatted(date: .omitted, time: .standard)) 后重试。"
        case .throttled: return "请求过于频繁。请稍后手动重试。"
        case .response(let code): return "平台返回了错误（HTTP \(code)），请稍后重试。"
        case .format: return "无法读取接口返回的内容；可在平台网页中打开。"
        case .tooLarge: return "内容超过阅读器的安全大小限制，请在平台网页中打开。"
        case .unsafeRedirect: return "接口发生了重定向。为保护令牌，未跟随该地址。"
        }
    }
    static func message(_ error: Error) -> String {
        if let e = error as? GIServiceError { return e.localizedDescription }
        if let e = error as? URLError {
            if e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
                return "当前离线。已加载内容仍可阅读，联网后可重试。"
            }
            if e.code == .timedOut { return "连接超时，请重试。" }
            if e.code == .cannotFindHost || e.code == .dnsLookupFailed {
                return "无法解析服务器地址，请检查网络或 DNS 设置。"
            }
        }
        // Never show an underlying URLSession error containing a credential-bearing URL.
        return "加载失败，请检查网络后重试。"
    }
}

final class GINoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class GIAPI: GIIssueService, @unchecked Sendable {
    private let token: String
    private let session: URLSession
    init(token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.token = token
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        self.session = URLSession(configuration: configuration, delegate: GINoRedirect(), delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }

    func get<T: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws -> T {
        var url = URL(string: "https://gitee.com/api/v5")!
        for component in path {
            guard GIIssueLinks.validPart(component) else { throw GIServiceError.format }
            url.appendPathComponent(component)
        }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        c.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: c.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ToolIsle-GiteeReader/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GIServiceError.format }
        switch http.statusCode {
        case 200..<300: break
        case 300..<400: throw GIServiceError.unsafeRedirect
        case 401: throw GIServiceError.missingToken
        case 403: throw GIServiceError.forbidden
        case 404: throw GIServiceError.missing
        case 429: throw GIServiceError.throttled
        default: throw GIServiceError.response(http.statusCode)
        }
        guard data.count <= 8 * 1024 * 1024 else { throw GIServiceError.tooLarge }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GIServiceError.format }
    }
    func user() async throws -> GIUser { try await get(["user"]) }
    func repositories(source: String, page: Int) async throws -> [GIRepository] {
        try await get(["user", source == "starred" ? "starred" : "subscriptions"], query: Self.page(page))
    }
    func issues(repository: String, page: Int) async throws -> [GIIssue] {
        guard repository.split(separator: "/").count == 2,
              repository.split(separator: "/").allSatisfy({ GIRepositoryAddress.validSlug(String($0)) }) else { throw GIServiceError.format }
        return try await get(["repos"] + repository.split(separator: "/").map(String.init) + ["issues"], query: Self.page(page) + [
            URLQueryItem(name: "state", value: "all"), URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "direction", value: "desc")
        ])
    }
    func issue(_ route: GIIssueRoute) async throws -> GIIssue { try await get(try issuePath(route)) }
    func comments(_ route: GIIssueRoute, page: Int) async throws -> [GIComment] {
        try await get(try issuePath(route) + ["comments"], query: Self.page(page))
    }
    private func issuePath(_ route: GIIssueRoute) throws -> [String] {
        guard (route.remote ?? .gitee) == .gitee, route.repository.split(separator: "/").count == 2,
              route.repository.split(separator: "/").allSatisfy({ GIRepositoryAddress.validSlug(String($0)) }),
              !route.number.isEmpty, route.number.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw GIServiceError.format }
        return ["repos"] + route.repository.split(separator: "/").map(String.init) + ["issues", route.number]
    }
    static func page(_ number: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "page", value: String(max(1, number))), URLQueryItem(name: "per_page", value: "50")]
    }
}
