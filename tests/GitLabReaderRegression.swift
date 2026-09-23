import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GLFixture: URLProtocol {
    static var requests: [URLRequest] = []
    static var status = 200
    static var malformed = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let path = request.url!.path
        let body: String
        if Self.malformed { body = "invalid json" }
        else if path.hasSuffix("/notes") {
            body = #"[{"id":42,"body":"Comment","author":{"id":3,"username":"alice"},"created_at":"2026-09-23T00:00:00Z"},{"id":43,"body":"closed","system":true}]"#
        } else if path.hasSuffix("/issues/7") {
            body = Self.issue
        } else if path.hasSuffix("/issues") {
            body = "[" + Self.issue + "]"
        } else if path.hasSuffix("/projects") {
            body = #"[{"id":5,"name":"Project","path_with_namespace":"team/sub/project","web_url":"https://git.example.test/gitlab/team/sub/project"}]"#
        } else {
            body = #"{"id":3,"username":"alice","name":"Alice"}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static let issue = #"{"id":9001,"iid":7,"title":"Nested issue","state":"opened","description":"[next](8#note_42)","author":{"id":3,"username":"alice"},"labels":["bug","team"],"user_notes_count":1,"web_url":"https://git.example.test/gitlab/team/sub/project/-/issues/7"}"#
}

@main struct GitLabReaderRegression {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }
    static func main() async throws {
        let remote = try GIReaderRemote.gitLab("https://GIT.example.test:443/gitlab/")
        expect(remote.webURL.absoluteString == "https://git.example.test/gitlab", "canonical server")
        expect(remote.imageOrigins == ["https://git.example.test"], "images use same HTTPS origin")
        let other = try GIReaderRemote.gitLab("https://other.example.test/gitlab")
        expect(remote.storagePrefix != other.storagePrefix, "site selection isolation")
        expect(remote.credentialAccount != other.credentialAccount, "site credential isolation")
        expect(remote.credentialService != GIReaderRemote.gitee.credentialService, "provider credential isolation")
        expect(GIReaderRemote.gitee.storagePrefix == "toolisle.gitee", "old Gitee preferences preserved")
        expect(GIReaderRemote.gitee.credentialAccount == "gitee.com", "old Gitee Keychain account preserved")
        expect(GIReaderRemote.gitee.credentialService == "io.github.lideming0815.toolisle.gitee-reader", "old Gitee Keychain service preserved")
        for raw in ["ftp://gitlab.com", "https://user:pass@gitlab.com", "https://gitlab.com?token=a", "https://gitlab.com/#a", "https://gitlab.com/api/v4", "https://gitlab.com/a/../b", "https://gitlab.com/a%2fb", "https://gitlab.com:0", "https://gitlab.com:65536", "https://gitlab.com//a", "https://gitlab.com\\@evil.test"] {
            do { _ = try GIReaderRemote.gitLab(raw); fatalError("unsafe server accepted: \(raw)") }
            catch GIServiceError.invalidServer { expect(true, "invalid server rejected") }
        }
        let route = GIIssueRoute(repository: "team/sub/project", number: "7", remote: remote)
        expect(route.url.absoluteString == "https://git.example.test/gitlab/team/sub/project/-/issues/7", "subgroup browser URL")
        expect(GIIssueLinks.resolve("8#note_42", relativeTo: route.url, remote: remote) == .issue(GIIssueRoute(repository: route.repository, number: "8", remote: remote), fragment: "note_42"), "relative link and note anchor")
        let cross = "https://git.example.test/gitlab/another/group/project/-/issues/12#note_43"
        expect(GIIssueLinks.resolve(cross, relativeTo: route.url, remote: remote) == .issue(GIIssueRoute(repository:"another/group/project", number:"12", remote:remote), fragment:"note_43"), "cross project issue link")
        for url in ["https://evil.test/gitlab/team/sub/project/-/issues/7", "https://git.example.test/team/sub/project/-/issues/7", "https://git.example.test:8443/gitlab/team/sub/project/-/issues/7", "https://git.example.test/gitlab/team%2Fsub/project/-/issues/7", "https://git.example.test/gitlab/team/sub/project/-/merge_requests/7", "https://gitee.com/team/repo/issues/I1"] {
            if case .external = GIIssueLinks.resolve(url, relativeTo: route.url, remote: remote) { expect(true,"external origin/resource never uses token") }
            else { fatalError("cross-origin/resource link intercepted") }
        }
        for url in ["javascript:alert(1)", route.url.absoluteString + "?private_token=secret", "https://user:pass@git.example.test/gitlab/team/project/-/issues/7"] {
            expect(GIIssueLinks.resolve(url, relativeTo: route.url, remote: remote) == .blocked, "sensitive link blocked")
        }
        expect(route != GIIssueRoute(repository: route.repository, number: "7", remote: other), "route cache isolation")
        let oldRoute = try JSONDecoder().decode(GIIssueRoute.self, from: Data(#"{"repository":"team/repo","number":"I1"}"#.utf8))
        expect(oldRoute == GIIssueRoute(repository:"team/repo", number:"I1"), "old Gitee route decode")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GLFixture.self]
        let api = GLAPI(remote: remote, token: "synthetic-only-token", configuration: config)
        defer { api.cancel() }
        let user = try await api.user()
        expect(user.login == "alice" && user.displayName == "Alice", "user mapping")
        let repos = try await api.repositories(source: "subscriptions", page: 1)
        expect(repos[0].path == "team/sub/project", "nested namespace preserved")
        let saved = try JSONDecoder().decode([GIRepository].self, from: JSONEncoder().encode(repos))
        expect(saved[0].path == repos[0].path, "GitLab selection survives persistence roundtrip")
        _ = try await api.repositories(source:"starred", page:2)
        let issues = try await api.issues(repository: repos[0].path, page: 2)
        expect(issues[0].id == 9001 && issues[0].number == "7", "use iid not global id")
        expect(issues[0].state == "open" && issues[0].visibleLabels.map(\.name) == ["bug","team"], "state and label mapping")
        expect(GIListPresentation.candidates([GIListItem(route:route,issue:issues[0])], state:"unfinished",query:"").count == 1, "existing unfinished filter handles opened")
        let issue = try await api.issue(route)
        let notes = try await api.comments(route, page:2)
        expect(issue.body?.contains("note_42") == true && notes[0].user?.login == "alice", "description and note mapping")
        expect(notes.count == 2 && notes[1].id == 43, "system notes do not truncate pagination")
        for request in GLFixture.requests {
            let c = URLComponents(url:request.url!, resolvingAgainstBaseURL:false)!
            let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a,_ in a })
            expect(request.httpMethod == "GET" && request.url!.host == "git.example.test", "read-only fixed site")
            expect(request.value(forHTTPHeaderField:"PRIVATE-TOKEN") == "synthetic-only-token" && request.value(forHTTPHeaderField:"Authorization") == nil, "GitLab token header")
            expect(!request.url!.absoluteString.contains("synthetic-only-token"), "no token in URL")
            if request.url!.path.hasSuffix("/projects") {
                expect(q["membership"] == "true" || q["starred"] == "true", "explicit project scope")
            }
            if c.percentEncodedPath.contains("/issues") {
                expect(c.percentEncodedPath.contains("team%2Fsub%2Fproject"), "namespace encoded as a single API component")
                expect(!c.percentEncodedPath.contains("%252F"), "no double encoding")
            }
            if request.url!.path.hasSuffix("/issues") { expect(q["scope"] == "all" && q["state"] == "all" && q["page"] == "2", "list scope/pagination") }
            if request.url!.path.hasSuffix("/notes") { expect(q["sort"] == "asc" && q["page"] == "2" && q["per_page"] == "50", "notes chronological pagination") }
        }
        let previousCount = GLFixture.requests.count
        do { _ = try await api.issue(GIIssueRoute(repository:route.repository,number:"7",remote:other)); fatalError("wrong site accepted") }
        catch GIServiceError.format { expect(GLFixture.requests.count == previousCount, "cross-site API blocked before network") }
        for status in [401,403,404,429,500,302] {
            GLFixture.status = status
            do { _ = try await api.user(); fatalError("HTTP failure ignored") }
            catch let error as GIServiceError {
                if status == 302 { guard case .unsafeRedirect = error else { fatalError("redirect not blocked") } }
                expect(!error.localizedDescription.contains("synthetic-only-token"), "safe HTTP error")
            }
        }
        GLFixture.status = 200; GLFixture.malformed = true
        do { _ = try await api.user(); fatalError("malformed JSON ignored") }
        catch GIServiceError.format { expect(true, "malformed response") }
        GLFixture.malformed = false
        let http = try GIReaderRemote.gitLab("HTTP://192.168.0.200:80/")
        expect(http.webURL.absoluteString == "http://192.168.0.200" && http.usesHTTP, "HTTP root and default port canonicalization")
        let https = try GIReaderRemote.gitLab("https://192.168.0.200")
        expect(http.storagePrefix != https.storagePrefix && http.credentialAccount != https.credentialAccount, "HTTP/HTTPS identities stay separate")
        let httpRoute = GIIssueRoute(repository: "dzhihao/project", number: "7", remote: http)
        expect(httpRoute.url.absoluteString == "http://192.168.0.200/dzhihao/project/-/issues/7", "HTTP issue URL")
        expect(GIIssueLinks.resolve("8#note_42", relativeTo: httpRoute.url, remote: http) == .issue(GIIssueRoute(repository: "dzhihao/project", number: "8", remote: http), fragment: "note_42"), "HTTP relative route and note")
        expect(http.contains(URL(string:"http://192.168.0.200:80/dzhihao/project")!), "HTTP default port origin")
        expect(!http.contains(URL(string:"https://192.168.0.200/dzhihao/project")!), "no cross-scheme API navigation")
        expect(!http.contains(URL(string:"http://192.168.0.200:8080/dzhihao/project")!), "no cross-port API navigation")
        expect(!https.contains(httpRoute.url), "HTTPS reader never follows HTTP internally")
        expect(http.imageOrigins == ["http://192.168.0.200"], "HTTP image allowlist limited to active origin")
        let restoredHTTP = try JSONDecoder().decode(GIReaderRemote.self, from: JSONEncoder().encode(http))
        let validatedHTTP = try GIReaderRemote.gitLab(restoredHTTP.webURL.absoluteString)
        expect(validatedHTTP == http, "HTTP endpoint survives restart validation")
        let httpClient = GLAPI(remote: http, token: "synthetic-http-token", configuration: config)
        _ = try await httpClient.user()
        _ = try await httpClient.issue(httpRoute)
        _ = try await httpClient.comments(httpRoute, page:1)
        for request in GLFixture.requests.suffix(3) {
            expect(request.url?.scheme == "http" && request.url?.host == "192.168.0.200", "HTTP transport stays on configured server")
            expect(request.value(forHTTPHeaderField:"PRIVATE-TOKEN") == "synthetic-http-token" && !request.url!.absoluteString.contains("synthetic-http-token"), "HTTP uses existing token header")
        }
        httpClient.cancel()
        print("PASS: \(checks) GitLab routing, persistence identity and API assertions; synthetic responses only.")
    }
}
