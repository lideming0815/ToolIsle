// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GitLab REST v4 adapter. Maps into the existing reader models; no additional SDK.
final class GLAPI: GIIssueService, @unchecked Sendable {
    let remote: GIReaderRemote
    private let token: String
    private let session: URLSession
    init(remote: GIReaderRemote, token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.remote = remote; self.token = token
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration, delegate: GINoRedirect(), delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }

    private func get<T: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws -> T {
        guard remote.isGitLab else { throw GIServiceError.invalidServer }
        var c = URLComponents(url: remote.webURL, resolvingAgainstBaseURL: false)!
        // The full namespace/project is ONE encoded API component, including subgroups.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        c.percentEncodedPath += "/api/v4/" + path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        c.queryItems = query.isEmpty ? nil : query
        guard let url = c.url else { throw GIServiceError.format }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ToolIsle-IssueReader/0.1", forHTTPHeaderField: "User-Agent")
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
    func user() async throws -> GIUser {
        let value: User = try await get(["user"])
        return value.reader
    }
    func repositories(source: String, page: Int) async throws -> [GIRepository] {
        let values: [Project] = try await get(["projects"], query: GIAPI.page(page) + [
            URLQueryItem(name: source == "starred" ? "starred" : "membership", value: "true"),
            URLQueryItem(name: "order_by", value: "last_activity_at"), URLQueryItem(name: "sort", value: "desc")
        ])
        return values.map { $0.reader }
    }
    func issues(repository: String, page: Int) async throws -> [GIIssue] {
        guard GIReaderRemote.validProject(repository) else { throw GIServiceError.format }
        let values: [Issue] = try await get(["projects", repository, "issues"], query: GIAPI.page(page) + [
            URLQueryItem(name: "scope", value: "all"), URLQueryItem(name: "state", value: "all"),
            URLQueryItem(name: "order_by", value: "updated_at"), URLQueryItem(name: "sort", value: "desc")
        ])
        return values.map { $0.reader }
    }
    private func issuePath(_ route: GIIssueRoute) throws -> [String] {
        guard route.remote == remote, GIReaderRemote.validProject(route.repository),
              GIReaderRemote.validIID(route.number) else { throw GIServiceError.format }
        return ["projects", route.repository, "issues", route.number]
    }
    func issue(_ route: GIIssueRoute) async throws -> GIIssue {
        let value: Issue = try await get(issuePath(route))
        return value.reader
    }
    func comments(_ route: GIIssueRoute, page: Int) async throws -> [GIComment] {
        let values: [Note] = try await get(issuePath(route) + ["notes"], query: GIAPI.page(page) + [
            URLQueryItem(name: "order_by", value: "created_at"), URLQueryItem(name: "sort", value: "asc")
        ])
        // Retain system notes too: filtering after pagination would truncate later pages.
        return values.map { GIComment(id: $0.id, body: $0.body, user: $0.author?.reader, created_at: $0.created_at) }
    }
    private struct User: Decodable {
        let id: Int64
        let username: String
        let name: String?
        var reader: GIUser { GIUser(id: id, login: username, name: name) }
    }
    private struct Project: Decodable {
        let id: Int64
        let name: String
        let path_with_namespace: String
        let description: String?
        let web_url: String?
        var reader: GIRepository {
            GIRepository(id: id, full_name: path_with_namespace, name: name, description: description,
                         html_url: web_url, gitLabPath: path_with_namespace)
        }
    }
    private struct Issue: Decodable {
        let id: Int64
        let iid: Int64
        let title: String
        let state: String
        let description: String?
        let web_url: String?
        let author: User?
        let updated_at: String?
        let user_notes_count: Int?
        let labels: [GIIssueLabel]?
        var reader: GIIssue {
            GIIssue(id: id, number: String(iid), title: title, state: state == "opened" ? "open" : state,
                    body: description, html_url: web_url, user: author?.reader, updated_at: updated_at,
                    comments: user_notes_count, labels: labels)
        }
    }
    private struct Note: Decodable {
        let id: Int64
        let body: String?
        let author: User?
        let created_at: String?
    }
}
