// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// FIFO per-connection request admission. A cancelled waiter checks cancellation on admission.
private actor GHRequestGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var retryAt: Date?
    func acquire() async throws {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        do {
            try Task.checkCancellation()
            if let retryAt, retryAt > Date() { throw GIServiceError.throttledUntil(retryAt) }
        } catch { release(); throw error }
    }
    func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
    func limit(until date: Date) { retryAt = date }
}

/// GitHub.com only. Never derive the API host from issue HTML, redirects, or pagination links.
final class GHAPI: GIIssueService, @unchecked Sendable {
    private let token: String
    private let session: URLSession
    private let gate = GHRequestGate()
    init(token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.token = token
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration, delegate: GINoRedirect(), delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }

    private func get<T: Decodable>(_ path: [String], page: Int? = nil,
                                    query: [URLQueryItem] = []) async throws -> (T, HTTPURLResponse) {
        var url = URL(string: "https://api.github.com")!
        for component in path {
            guard GIRepositoryAddress.validSlug(component) else { throw GIServiceError.format }
            url.appendPathComponent(component)
        }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let parameters = (page.map(GIAPI.page) ?? []) + query
        c.queryItems = parameters.isEmpty ? nil : parameters
        var request = URLRequest(url: c.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ToolIsle-IssueReader/0.2", forHTTPHeaderField: "User-Agent")
        try await gate.acquire()
        defer { Task { await gate.release() } }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GIServiceError.format }
        if http.statusCode == 429 || (http.statusCode == 403 &&
            (http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" ||
             http.value(forHTTPHeaderField: "Retry-After") != nil ||
             (String(data: data, encoding: .utf8)?.lowercased().contains("rate limit") == true))) {
            let retry: Date
            if let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) {
                retry = Date().addingTimeInterval(max(1, seconds))
            } else if let epoch = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) {
                retry = max(Date().addingTimeInterval(1), Date(timeIntervalSince1970: epoch))
            } else { retry = Date().addingTimeInterval(60) }
            await gate.limit(until: retry)
            throw GIServiceError.throttledUntil(retry)
        }
        switch http.statusCode {
        case 200..<300: break
        case 300..<400: throw GIServiceError.unsafeRedirect
        case 401: throw GIServiceError.missingToken
        case 403: throw GIServiceError.forbidden
        case 404: throw GIServiceError.missing
        default: throw GIServiceError.response(http.statusCode)
        }
        guard data.count <= 8 * 1024 * 1024 else { throw GIServiceError.tooLarge }
        do { return (try JSONDecoder().decode(T.self, from: data), http) }
        catch { throw GIServiceError.format }
    }
    /// Extract only the page number; the next request is always constructed locally.
    static func nextPage(_ response: HTTPURLResponse, current: Int) -> Int? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }
        for entry in link.split(separator: ",") {
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.dropFirst().contains(where: { $0 == "rel=\"next\"" || $0 == "rel=next" }),
                  let raw = parts.first, raw.hasPrefix("<"), raw.hasSuffix(">"),
                  let c = URLComponents(string: String(raw.dropFirst().dropLast())),
                  c.scheme == "https", c.host == "api.github.com", c.user == nil, c.password == nil,
                  c.port == nil || c.port == 443, c.path == response.url?.path,
                  let number = c.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init),
                  number > current else { continue }
            return number
        }
        return nil
    }
    func user() async throws -> GIUser { let (user, _): (GIUser, HTTPURLResponse) = try await get(["user"]); return user }
    func repositories(source: String, page: Int) async throws -> [GIRepository] {
        try await repositoryPage(source: source, page: page).items
    }
    func repositoryPage(source: String, page: Int) async throws -> GIResultPage<GIRepository> {
        let (values, response): ([GIRepository], HTTPURLResponse) = try await get(["user", source == "starred" ? "starred" : "subscriptions"], page: page)
        return GIResultPage(items: values.map { $0.on(.github) }, nextPage: Self.nextPage(response, current: page))
    }
    func issues(repository: String, page: Int) async throws -> [GIIssue] {
        try await issuePage(repository: repository, page: page).items
    }
    func issuePage(repository: String, page: Int) async throws -> GIResultPage<GIIssue> {
        let path = try projectPath(repository) + ["issues"]
        let (values, response): ([Issue], HTTPURLResponse) = try await get(path, page: page, query: [
            URLQueryItem(name: "state", value: "all"), URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "direction", value: "desc")])
        return GIResultPage(items: values.filter { $0.pull_request == nil }.map(\.reader), nextPage: Self.nextPage(response, current: page))
    }
    func issue(_ route: GIIssueRoute) async throws -> GIIssue {
        let (value, _): (Issue, HTTPURLResponse) = try await get(try issuePath(route))
        guard value.pull_request == nil else { throw GIServiceError.missing }
        return value.reader
    }
    func comments(_ route: GIIssueRoute, page: Int) async throws -> [GIComment] {
        try await commentPage(route, page: page).items
    }
    func commentPage(_ route: GIIssueRoute, page: Int) async throws -> GIResultPage<GIComment> {
        let (values, response): ([GIComment], HTTPURLResponse) = try await get(try issuePath(route) + ["comments"], page: page)
        return GIResultPage(items: values, nextPage: Self.nextPage(response, current: page))
    }
    private func projectPath(_ repository: String) throws -> [String] {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(GIRepositoryAddress.validSlug) else { throw GIServiceError.format }
        return ["repos"] + parts
    }
    private func issuePath(_ route: GIIssueRoute) throws -> [String] {
        guard route.remote == .github, GIReaderRemote.validIID(route.number) else { throw GIServiceError.format }
        return try projectPath(route.repository) + ["issues", route.number]
    }
    private struct PullRequest: Decodable {}
    private struct Issue: Decodable {
        let id: Int64
        let number: Int64
        let title: String
        let state: String
        let body: String?
        let html_url: String?
        let user: GIUser?
        let updated_at: String?
        let comments: Int?
        let labels: [GIIssueLabel]?
        let pull_request: PullRequest?
        var reader: GIIssue {
            GIIssue(id: id, number: String(number), title: title, state: state, body: body, html_url: html_url,
                    user: user, updated_at: updated_at, comments: comments, labels: labels)
        }
    }
}
