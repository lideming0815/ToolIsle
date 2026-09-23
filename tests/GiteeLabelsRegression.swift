import Foundation
@main struct GiteeLabelsRegression {
    static var count = 0
    static func expect(_ result: @autoclosure () throws -> Bool, _ name: String) {
        count += 1; if !(try! result()) { fatalError(name) }
    }
    static func main() throws {
        let decoder = JSONDecoder()
        func decode(_ value: String) throws -> GIIssue {
            try decoder.decode(GIIssue.self, from: Data(("{\"id\":1,\"number\":\"IAb12\",\"title\":\"test\",\"state\":\"open\"" + value + "}").utf8))
        }
        expect(try decode("").labels == nil, "missing is not empty")
        expect(try decode(",\"labels\":null").labels == nil, "null is unknown")
        expect(try decode(",\"labels\":[]").labels?.count == 0, "known none")
        let issue = try decode(##", "labels":[{"id":1,"name":"bug","color":"#fa0"}, {"name":"bug"},"文档", 3, null, {}, {"name":" "}, {"name":"Bug","color":"invalid"}]"##)
        expect(issue.visibleLabels.map(\.key) == ["bug", "文档", "Bug"], "lossy entries, distinct case, stable deduplication")
        expect(issue.visibleLabels[0].hexColor == "FFAA00", "short hex normalizes")
        expect(issue.visibleLabels.last?.hexColor == nil, "invalid color is safe")
        expect(try decode(#", "labels":{"bad":"shape"}"#).labels == nil, "malformed optional array does not discard issue")
        let roundtrip = try decoder.decode(GIIssue.self, from: JSONEncoder().encode(issue))
        expect(roundtrip.visibleLabels == issue.visibleLabels, "codable roundtrip")
        let r1 = GIRepository(id:1, full_name:"team/a",name:"同名项目",description:nil,html_url:nil)
        let r2 = GIRepository(id:2, full_name:"team/b",name:"同名项目",description:nil,html_url:nil)
        func item(_ n: Int, repo: String, state: String, labels: [GIIssueLabel]) -> GIListItem {
            GIListItem(route:GIIssueRoute(repository:repo,number:"I\(n)"),issue:GIIssue(id:Int64(n),number:"I\(n)",title:"任务 \(n)",state:state,body:nil,html_url:nil,user:nil,updated_at:"2026-09-22",comments:0,labels:labels))
        }
        let bug = GIIssueLabel(name:"bug",color:"#123456"), doc = GIIssueLabel(name:"文档",color:"bad")
        let all = [item(1,repo:r1.path,state:"open",labels:[bug,bug]), item(2,repo:r2.path,state:"closed",labels:[GIIssueLabel(name:"bug",color:"#654321"),doc]), item(3,repo:r2.path,state:"progressing",labels:[doc])]
        let facets = GIListPresentation.facets(all)
        expect(facets.count == 2 && facets.allSatisfy { $0.count == 2 }, "one occurrence per issue")
        expect(facets.first { $0.name == "bug" }?.repositories.count == 2, "cross project facets")
        expect(facets.first { $0.name == "bug" }?.color == nil, "conflicting colors use neutral")
        expect(GIListPresentation.filter(all,labels:["bug","文档"]).count == 3, "OR labels not AND")
        expect(GIListPresentation.filter(all,labels:["BUG"]).isEmpty, "case preserved")
        let pending = GIListPresentation.candidates(all,state:"unfinished",query:"")
        expect(pending.count == 2, "unfinished open and progressing")
        expect(GIListPresentation.candidates(all,state:"all",query:"I3").count == 1, "number search retained")
        expect(GIListPresentation.candidates(all,state:"closed",query:"I3").isEmpty, "state and query combine")
        let groups = GIListPresentation.groups(all,repositories:[r2,r1])
        expect(groups.map(\.path) == [r2.path,r1.path], "stable project order")
        expect(groups.map(\.title) == [r2.path,r1.path], "duplicate names disambiguated")
        expect(groups.map(\.id) == ["repo:2","repo:1"], "persistent ID not display name")
        expect(GIListPresentation.groups(pending,repositories:[r1,r2]).count == 2, "group after filtering")
        expect(Array(GIListPresentation.states.prefix(3)) == ["unfinished","progressing","closed"], "requested state priority")
        for width in [212.0,217,220,236,260,296,356,600] {
            let plan = GIChipPacking.pack(widths:[58,58,58,44,44,58],available:width,maxRows:1,overflow:28)
            expect(plan.rows.count == 1,"single-line state")
            if width >= 217 { expect(plan.rows[0].prefix(3) == [0,1,2],"three priority states fit") }
        }
        for width in [1.0,100,212,236,296,356,600] {
            for n in [0,1,2,8,20,100,500] {
                let widths = (0..<n).map { Double(40 + ($0 * 17) % 125) }
                let p = GIChipPacking.pack(widths:widths,available:width,maxRows:2,overflow:52)
                expect(p.rows.count <= 2,"never third line")
                expect(p.rows.flatMap { $0 }.filter { $0 >= 0 }.count + p.hidden == n,"no missing chips")
                expect(p.rows.flatMap { $0 }.filter { $0 == -1 }.count == (p.hidden > 0 ? 1 : 0),"overflow exactly when needed")
                for row in p.rows {
                    let used = row.reduce(0.0) { $0 + min(width,$1 < 0 ? 52 : widths[$1]) } + Double(max(0,row.count-1)) * 5
                    expect(used <= width + 0.1,"no clipping")
                }
            }
        }
        print("PASS: \(count) label decoding, grouping, filtering and bounded chip layout assertions (synthetic data).")
    }
}
