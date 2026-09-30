import Foundation
@main struct GitReaderProjectionRegression {
    static var count = 0
    static func expect(_ value: Bool, _ name: String) { count += 1; precondition(value, name) }
    static func issue(_ raw: String, extra: String = "") throws -> GIIssue {
        try JSONDecoder().decode(GIIssue.self, from: Data("{\"id\":1,\"number\":\"I1\",\"title\":\"fixture\",\"state\":\"\(raw)\"\(extra)}".utf8))
    }
    static func main() throws {
        for raw in ["open", "opened", "OPEN", " open "] {
            let value = try issue(raw)
            expect(value.projectedState == "open", "open alias normalization")
            expect(GIStateProjection.matches(value, filter: "open") && GIStateProjection.matches(value, filter: "unfinished"), "display/filter share projection")
        }
        for raw in ["progressing", "in_progress", "in-progress"] {
            let value = try issue(raw)
            expect(value.projectedState == "progressing" && GIStateProjection.matches(value, filter: "unfinished"), "progress aliases")
        }
        let pending = try issue("open", extra: #", "issue_state":{"id":77,"title":"等待验收","state":1}"#)
        expect(pending.stateTitle == "等待验收", "custom state title survives optional numeric metadata")
        expect(GIStateProjection.matches(pending, filter: pending.statusFilterKey), "custom workflow state selectable")
        let closed = try issue("closed", extra: #", "issue_state":{"title":"等待验收"}"#)
        expect(!GIStateProjection.matches(closed, filter: "unfinished"), "custom title never overrides closed lifecycle")
        expect(closed.statusFilterKey != pending.statusFilterKey, "same title in distinct base states stays separate")
        let unknown = try issue("custom_unknown")
        expect(unknown.stateTitle == "custom_unknown" && GIStateProjection.matches(unknown, filter: "all"), "unknown state is preserved")
        expect(GIStateProjection.matches(unknown, filter: "custom_unknown") && !GIStateProjection.matches(unknown, filter: "unfinished"), "unknown never guessed as open")
        expect(try issue("open", extra: #", "issue_state":42"#).projectedState == "open", "malformed optional metadata cannot discard issue")
        let sites = [GIReaderRemote.gitee, .github, try GIReaderRemote.gitLab("https://git.example.test:8443/prefix")]
        let repos = sites.map { GIRepository(id: 1, full_name: "team/project", name: "same", description: nil, html_url: nil).on($0) }
        let rows = sites.map { GIListItem(route: GIIssueRoute(repository: "team/project", number: "1", remote: $0), issue: pending) }
        let groups = GIListPresentation.groups(rows, repositories: repos)
        expect(groups.count == 3 && Set(groups.map(\.id)).count == 3, "same paths and numeric IDs cannot collide across sites")
        expect(groups.allSatisfy { $0.items.count == 1 && $0.title == $0.id && $0.title.contains("://") }, "full URL is the visible group and key")
        expect(Set(repos.map(\.scopedID)).count == 3, "internal numeric IDs are site-scoped")
        expect(GIListPresentation.groups([], repositories: repos).count == 3, "empty or failed configured groups remain visible")
        expect(GIListPresentation.groups(rows, repositories: repos + repos).count == 3, "Watch/Star duplicate selection produces one group")
        expect(GIListPresentation.candidates(rows, state: "all", query: "github.com").count == 1, "URL search")
        expect(GIListPresentation.timestamp("2026-09-30T03:00:00Z") == GIListPresentation.timestamp("2026-09-30T11:00:00+08:00"), "timestamps compared as dates, not strings")
        var history = GIHistory()
        for row in rows { history.push(row.route) }
        history.move(-1); history.remove(remote: .gitee)
        expect(history.current?.route.remote == .github && history.visits.count == 2, "disconnect purges only its history")
        let metrics = GINotchMetrics(count: 5, limit: 5, groupCount: 3)
        expect(metrics.preferredContentHeight > GINotchMetrics(count: 5, limit: 5).preferredContentHeight, "URL headings are charged to preview height")
        print("PASS: \(count) state projection, URL grouping, identity, history and preview assertions; synthetic fixtures only.")
    }
}
