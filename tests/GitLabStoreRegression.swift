import AppKit
import Defaults

/// Run as a standalone test executable, never inside the installed application.
/// Disable network/keychain restoration through the highest-priority defaults domain.
@main struct GitLabStoreRegression {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier != "com.Ebullioscopic.Atoll")
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let keys = ["toolisle.reader.remote", "toolisle.reader.gitlabServer", "toolisle.gitee.enabled"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.setVolatileDomain(["toolisle.gitee.enabled": false], forName: UserDefaults.argumentDomain)
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain)
        }
        var count = 0
        func expect(_ value: Bool, _ message: String) {
            count += 1; precondition(value, message)
        }
        let store = GIStore.shared
        store.useRemote(.gitee)
        defaults.setVolatileDomain(["toolisle.gitee.enabled": true], forName: UserDefaults.argumentDomain)
        store.startDemo()
        expect(store.demoMode && store.account != nil, "seed old session")
        expect(!store.items.isEmpty && !store.pages.isEmpty && store.visit != nil, "seed old private reading content")
        store.query = "old search"; store.selectedLabels = ["old label"]
        store.loadRemoteImages = true
        let gitlab = try GIReaderRemote.gitLab("https://git.example.test/gitlab")
        defaults.setVolatileDomain(["toolisle.gitee.enabled": false], forName: UserDefaults.argumentDomain)
        store.useRemote(gitlab)
        expect(store.remote == gitlab && store.platformName == "GitLab", "switch provider")
        expect(store.account == nil && !store.demoMode && !store.isConnecting, "clear identity without restoring disabled reader")
        expect(store.items.isEmpty && store.pages.isEmpty && store.visit == nil, "clear content and history")
        expect(store.selectedRepositories.isEmpty && store.repositories.isEmpty, "clear old project list")
        expect(store.query.isEmpty && store.selectedLabels.isEmpty && store.collapsedProjects.isEmpty, "clear filters")
        expect(!store.loadRemoteImages && !store.loadingList && !store.loadingDetail, "reset image opt-in and requests")
        expect(store.availableStates == ["all", "unfinished", "open", "closed"], "GitLab states")
        expect(store.savedGitLabServer == gitlab.webURL.absoluteString, "remember custom endpoint")
        let savedRemote = try JSONDecoder().decode(GIReaderRemote.self, from: defaults.data(forKey: "toolisle.reader.remote")!)
        expect(savedRemote == gitlab, "persist selected site")
        store.open(GIStore.demoA)
        expect(store.visit == nil, "reject stale Gitee routes in GitLab session")
        store.connect("synthetic-token-must-not-be-used")
        expect(!store.isConnecting && store.account == nil, "disabled reader cannot connect")
        store.useRemote(.gitee)
        expect(store.availableStates == GIListPresentation.states && store.platformName == "Gitee", "switch back")
        expect(store.savedGitLabServer == gitlab.webURL.absoluteString, "retain GitLab endpoint after switching back")
        expect(store.visit == nil && store.account == nil, "no cross-platform session revival")
        print("PASS: \(count) live GIStore switching assertions; no network or keychain access.")
    }
}
