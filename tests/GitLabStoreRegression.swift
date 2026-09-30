// Runs against the unmodified production GIStore and the built Defaults module on macOS.
// All credentials, preferences and responses are isolated synthetic test doubles.
import AppKit
import Defaults

final class ReaderFixtureService: GIIssueService, @unchecked Sendable {
    let remote: GIReaderRemote
    private let lock = NSLock()
    private var failure: GIServiceError?
    private var delay: UInt64 = 0
    private var requests = 0
    init(_ remote: GIReaderRemote) { self.remote = remote }
    func fail(_ error: GIServiceError?) { lock.lock(); failure = error; lock.unlock() }
    func delayLists(_ nanos: UInt64) { lock.lock(); delay = nanos; lock.unlock() }
    private func snapshot() -> (GIServiceError?, UInt64) { lock.lock(); defer { lock.unlock() }; requests += 1; return (failure, delay) }
    func cancel() {} // Deliberately ignore cancellation: the Store must reject stale responses itself.
    func user() async throws -> GIUser { GIUser(id: 1, login: "fixture", name: nil) }
    var repository: GIRepository { GIRepository(id: 7, full_name: "team/project", name: "Project", description: nil, html_url: nil).on(remote) }
    func repositories(source: String, page: Int) async throws -> [GIRepository] { [repository] }
    func issues(repository: String, page: Int) async throws -> [GIIssue] { try await issuePage(repository: repository, page: page).items }
    func issuePage(repository: String, page: Int) async throws -> GIResultPage<GIIssue> {
        let (failure, delay) = snapshot()
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        if let failure { throw failure }
        return GIResultPage(items: [makeIssue(String(page))], nextPage: page == 1 ? 2 : nil)
    }
    func makeIssue(_ number: String) -> GIIssue {
        GIIssue(id: Int64(number) ?? 1, number: number, title: remote.name + " fixture " + number,
                state: "open", body: "synthetic private body", html_url: nil, user: nil, updated_at: "2026-09-30T00:00:00Z", comments: 1)
    }
    func issue(_ route: GIIssueRoute) async throws -> GIIssue {
        precondition((route.remote ?? .gitee) == remote, "wrong credential routing")
        return makeIssue(route.number)
    }
    func comments(_ route: GIIssueRoute, page: Int) async throws -> [GIComment] {
        precondition((route.remote ?? .gitee) == remote, "wrong comment credential routing")
        return [GIComment(id: 1, body: remote.name + " fixture comment", user: nil, created_at: nil)]
    }
}
@main struct GitLabStoreRegression {
    @MainActor static func main() async throws {
        precondition(Bundle.main.bundleIdentifier != "com.Ebullioscopic.Atoll")
        let suite = "toolisle.git-reader-tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let gl = try GIReaderRemote.gitLab("https://git.example.test/prefix")
        let oldHidden = try GIReaderRemote.gitLab("https://second.example.test")
        var enabled = false, readCount = 0, deleted: [GIReaderRemote] = []
        var tokens: [GIReaderRemote: String] = [.gitee: "fixture-gitee", gl: "fixture-gitlab"]
        var clients: [GIReaderRemote: ReaderFixtureService] = [:]
        for site in [GIReaderRemote.gitee, gl, oldHidden] {
            let repo = GIRepository(id: 7, full_name: "team/project", name: "Project", description: nil, html_url: nil)
            preferences.set(try JSONEncoder().encode([repo]), forKey: "\(site.storagePrefix).selection.1")
        }
        preferences.set(try JSONEncoder().encode(gl), forKey: "toolisle.reader.remote")
        preferences.set(gl.webURL.absoluteString, forKey: "toolisle.reader.gitlabServer")
        let store = GIStore(preferences: preferences, observePreference: false, enabled: { enabled },
            readCredential: { site in readCount += 1; return tokens[site] },
            saveCredential: { token, site in tokens[site] = token },
            deleteCredential: { site in tokens[site] = nil; deleted.append(site) },
            makeClient: { site, _ in let client = ReaderFixtureService(site); clients[site] = client; return client })
        var count = 0
        func expect(_ value: Bool, _ name: String) { count += 1; precondition(value, name) }
        func settle(_ predicate: @escaping @MainActor () -> Bool) async throws {
            for _ in 0..<300 {
                if predicate() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("async fixture did not settle")
        }
        expect(store.connections.count == 3, "migration discovers previous GitLab sites, not just selected site")
        store.activate(); expect(readCount == 0, "disabled feature must not read credentials")
        enabled = true; store.activate()
        try await settle { !store.connectingAny && !store.loadingList && store.items.count == 2 }
        expect(Set(store.issueGroups.map(\.id)).count == 2, "same ID/path from Gitee and GitLab are isolated")
        store.useRemote(.github); store.connect("fixture-github")
        try await settle { store.account != nil && !store.isConnecting && !store.loadingRepositories }
        store.applySelection([clients[.github]!.repository, clients[.github]!.repository])
        try await settle { !store.loadingList && store.items.count == 3 }
        expect(store.issueGroups.count == 3 && store.settingsSelectedRepositories.count == 1, "three-platform aggregation and duplicate suppression")
        let ghRoute = GIIssueRoute(repository: "team/project", number: "1", remote: .github)
        let giRoute = GIIssueRoute(repository: "team/project", number: "1")
        store.open(ghRoute, fromList: true)
        try await settle { !store.loadingDetail && store.currentPage != nil }
        expect(store.currentPage?.issue.title == "GitHub fixture 1", "detail uses selected route's client")
        store.useRemote(.gitee)
        expect(store.visit?.route == ghRoute && store.currentPage != nil && store.items.count == 3, "editing another connection preserves reading and other sessions")
        store.open(giRoute, fromList: true)
        try await settle { !store.loadingDetail && store.currentPage?.issue.title == "Gitee fixture 1" }
        store.loadRemoteImages = true; store.moveHistory(-1)
        expect(store.visit?.route == ghRoute && !store.loadRemoteImages, "cross-site history resets image consent")
        let ghURL = clients[.github]!.repository.canonicalURL
        store.refreshIssues(reset: false, only: [ghURL])
        try await settle { !store.loadingList }
        expect(store.items.filter { $0.route.remote == .github }.count == 2 && store.items.count == 4, "one repository pagination does not reload or replace others")
        // Removing the last repository while a request is pending cannot revive its results.
        store.useRemote(.github)
        clients[.github]!.delayLists(150_000_000)
        store.refreshIssues(reset: true, only: [ghURL])
        try await Task.sleep(nanoseconds: 10_000_000)
        store.applySelection([])
        try await Task.sleep(nanoseconds: 180_000_000)
        expect(!store.loadingList && !store.items.contains { $0.route.remote == .github }, "removing final selection invalidates in-flight results")
        expect(store.items.count == 2, "removing a repository does not clear other connections")
        clients[.github]!.delayLists(0)
        store.applySelection([clients[.github]!.repository])
        try await settle { !store.loadingList && store.items.count == 3 }
        store.refreshIssues(reset: false, only: [ghURL])
        try await settle { !store.loadingList && store.items.count == 4 }
        store.useRemote(.gitee)
        let glURL = clients[gl]!.repository.canonicalURL
        clients[gl]!.fail(.forbidden)
        store.refreshIssues(reset: true, only: [glURL])
        try await settle { !store.loadingList }
        expect(!store.items.contains { $0.route.remote == gl } && store.items.count == 3, "permission loss purges only affected repository")
        expect(store.listFailures.first?.repository == glURL, "failure identity is complete URL")
        clients[gl]!.fail(nil); store.retryFailedRepositories()
        try await settle { !store.loadingList }
        expect(store.items.count == 4 && store.listFailures.isEmpty, "failed reset retries page one without stale duplicates")
        store.disconnect() // editor is Gitee; current reader is still GitHub
        expect(deleted == [.gitee], "only explicitly selected credential removed")
        expect(store.items.count == 3 && store.currentPage?.issue.title == "GitHub fixture 1", "disconnect retains other platform content")
        expect(!store.pages.keys.contains { $0.remote == nil } && !store.history.visits.contains { $0.route.remote == nil }, "private cache/history of disconnected connection purged")
        let readsAfterDisconnect = readCount; store.activate()
        expect(readCount == readsAfterDisconnect, "explicitly disconnected site does not silently restore")
        store.setEnabled(gl, false)
        expect(!store.items.contains { $0.route.remote == gl } && store.settingsSelectedRepositories.isEmpty, "disable isolates source")
        store.setEnabled(gl, true)
        try await settle { !store.connectingAny && !store.loadingList && store.items.count == 3 }
        expect(store.items.filter { $0.route.remote == gl }.count == 1, "reenable restores saved site selection")
        // An authorization failure must clear all private data for its site, but no others.
        clients[gl]!.fail(.missingToken)
        store.refreshIssues(reset: true, only: [glURL])
        try await settle { !store.loadingList }
        expect(store.items.count == 2 && store.connectionStatus(gl).contains("授权"), "401 is connection-scoped and does not expose cached private content")
        // A late response from a disconnected client must never repopulate the list.
        clients[.github]!.delayLists(150_000_000)
        store.refreshIssues(reset: true, only: [ghURL])
        try await Task.sleep(nanoseconds: 10_000_000)
        store.useRemote(.github); store.disconnect()
        try await Task.sleep(nanoseconds: 180_000_000)
        expect(!store.items.contains { $0.route.remote == .github } && store.pages.isEmpty, "late cancelled response cannot revive private data")
        enabled = false; store.deactivate()
        let reads = readCount; store.activate(); store.connect("must-not-be-used")
        expect(reads == readCount && !store.isConnecting && store.items.isEmpty && store.pages.isEmpty, "global disable cancels and forbids restoration")
        let saved = preferences.data(forKey: "toolisle.reader.connections.v2")!
        let second = GIStore(preferences: preferences, observePreference: false, enabled: { false },
                             readCredential: { _ in preconditionFailure("disabled restore") },
                             saveCredential: { _, _ in preconditionFailure("disabled write") },
                             deleteCredential: { _ in preconditionFailure("disabled delete") },
                             makeClient: { _, _ in preconditionFailure("disabled network") })
        expect(second.connections.count == 4 && preferences.data(forKey: "toolisle.reader.connections.v2") == saved, "configuration migration is idempotent")
        expect(preferences.data(forKey: "\(oldHidden.storagePrefix).selection.1") != nil, "legacy metadata is not destroyed")
        print("PASS: \(count) production GIStore aggregation, migration, pagination, permission and cancellation assertions; no real credentials or network.")
    }
}
