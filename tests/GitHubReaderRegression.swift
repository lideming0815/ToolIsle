import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GHFixture: URLProtocol {
    static var requests: [URLRequest] = []
    static var status = 200
    static var payload = "[]"
    static var headers: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: Self.headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.payload.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct GitHubReaderRegression {
    static var count = 0
    static func expect(_ value: Bool, _ name: String) { count += 1; precondition(value, name) }
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GHFixture.self]
        let api = GHAPI(token: "synthetic-only-token", configuration: config)
        defer { api.cancel() }
        GHFixture.payload = #"{"id":7,"login":"fixture"}"#
        let user = try await api.user(); expect(user.login == "fixture", "user mapping")
        let request = GHFixture.requests.last!
        expect(request.url?.absoluteString == "https://api.github.com/user", "fixed API origin")
        expect(request.httpMethod == "GET", "read only")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-only-token", "header authentication")
        expect(request.url?.query == nil && request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == nil, "no credentials in URL or other provider headers")
        expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10", "pinned API version")
        GHFixture.payload = #"[{"id":1,"full_name":"Team/Project","name":"Project","html_url":"https://github.com/Team/Project"}]"#
        let repos = try await api.repositoryPage(source: "subscriptions", page: 1)
        expect(repos.items.first?.remote == .github && repos.items.first?.canonicalURL == "https://github.com/team/project", "canonical URL and source")
        expect(GHFixture.requests.last!.url!.path == "/user/subscriptions", "Watch source")
        _ = try await api.repositoryPage(source: "starred", page: 1)
        expect(GHFixture.requests.last!.url!.path == "/user/starred", "Star source")
        let issue = #"{"id":12,"number":42,"title":"fixture","state":"open","body":"Markdown","labels":[{"name":"bug","color":"ff0000"}]}"#
        let pr = #"{"id":13,"number":43,"title":"pull request","state":"open","pull_request":{"url":"https://api.github.com/repos/team/project/pulls/43"}}"#
        GHFixture.payload = "[" + issue + "," + pr + "]"
        GHFixture.headers = ["Link": #"<https://api.github.com/repos/team/project/issues?page=2&per_page=50>; rel="next""#]
        let first = try await api.issuePage(repository: "team/project", page: 1)
        expect(first.items.count == 1 && first.items[0].number == "42", "numeric numbers and PR filtering")
        expect(first.items[0].visibleLabels.first?.name == "bug", "label mapping")
        expect(first.nextPage == 2, "filtered count does not control pagination")
        expect(GHFixture.requests.last!.url!.query!.contains("state=all"), "load all lifecycle states before local filtering")
        GHFixture.payload = "[" + pr + "]"
        let empty = try await api.issuePage(repository: "team/project", page: 1)
        expect(empty.items.isEmpty && empty.nextPage == 2, "PR-only page still advances")
        GHFixture.headers = [:]; GHFixture.payload = "[" + issue + "]"
        let last = try await api.issuePage(repository: "team/project", page: 2)
        expect(last.items.count == 1 && last.nextPage == nil, "next issue after PR-only page")
        let route = GIIssueRoute(repository: "Team/Project", number: "42", remote: .github)
        expect(route.url.absoluteString == "https://github.com/team/project/issues/42", "GitHub issue route")
        expect(route != GIIssueRoute(repository: "team/project", number: "42"), "same number on Gitee cannot share cache key")
        expect(GIIssueLinks.resolve("43#issuecomment-9", relativeTo: route.url, remote: .github) == .issue(GIIssueRoute(repository: "team/project", number: "43", remote: .github), fragment: "issuecomment-9"), "GitHub link/comment resolution")
        for raw in ["https://github.com/team/project/pull/43", "http://github.com/team/project/issues/42", "https://github.com.evil.test/team/project/issues/42", "https://github.com/team%2Fproject/issues/42"] {
            if case .external = GIIssueLinks.resolve(raw, relativeTo: route.url, remote: .github) { expect(true, "unsafe origin or non-Issue uses browser") }
            else { preconditionFailure(raw) }
        }
        expect(GIIssueLinks.resolve("https://github.com/team/project/issues/42?token=fixture", relativeTo: route.url, remote: .github) == .blocked, "credential-bearing navigation rejected")
        for link in [#"<https://evil.test/repos/team/project/issues?page=3>; rel="next""#, #"<https://api.github.com/repos/team/other/issues?page=3>; rel="next""#, #"<https://api.github.com/repos/team/project/issues?page=1>; rel="next""#] {
            let response = HTTPURLResponse(url: URL(string: "https://api.github.com/repos/team/project/issues")!, statusCode: 200, httpVersion: nil, headerFields: ["Link": link])!
            expect(GHAPI.nextPage(response, current: 1) == nil, "pagination origin/path/progress checked")
        }
        let before = GHFixture.requests.count
        do { _ = try await api.issue(GIIssueRoute(repository: "team/project", number: "42")); preconditionFailure("cross-site route") }
        catch { expect(GHFixture.requests.count == before, "cross-site route rejected before request") }
        GHFixture.payload = pr
        do { _ = try await api.issue(route); preconditionFailure("PR detail accepted") }
        catch { expect(true, "PR detail filtered") }
        GHFixture.payload = #"[{"id":9,"body":"comment","user":{"id":1,"login":"fixture"}}]"#
        GHFixture.headers = ["Link": #"<https://api.github.com/repos/team/project/issues/42/comments?page=2>; rel="next""#]
        let comments = try await api.commentPage(route, page: 1)
        expect(comments.items.first?.id == 9 && comments.nextPage == 2, "comment pagination metadata")
        GHFixture.status = 403; GHFixture.headers = ["X-RateLimit-Remaining": "0", "Retry-After": "30"]
        do { _ = try await api.issue(route); preconditionFailure("limit accepted") }
        catch GIServiceError.throttledUntil(let date) { expect(date > Date(), "403 rate limit is distinct from permission failure") }
        let blockedCount = GHFixture.requests.count
        do { _ = try await api.issue(route); preconditionFailure("cooldown ignored") } catch { expect(GHFixture.requests.count == blockedCount, "cooldown prevents further requests") }
        let old = try JSONDecoder().decode(GIReaderRemote.self, from: Data("{}".utf8))
        expect(old == .gitee, "legacy Gitee remote migrates")
        let roundtrip = try JSONDecoder().decode(GIReaderRemote.self, from: JSONEncoder().encode(GIReaderRemote.github))
        expect(roundtrip == .github, "GitHub configuration roundtrip")
        print("PASS: \(count) GitHub adapter, pagination, authentication boundary and route assertions; synthetic responses only.")
    }
}
