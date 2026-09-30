// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import Defaults
import Security

extension Defaults.Keys {
    static let enableGiteeReader = Key<Bool>("toolisle.gitee.enabled", default: false)
}

enum GICredential {
    private static func query(_ remote: GIReaderRemote) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: remote.credentialService, kSecAttrAccount as String: remote.credentialAccount]
    }
    static func read(remote: GIReaderRemote = .gitee) throws -> String? {
        var q = query(remote)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CredentialError() }
        return value
    }
    static func save(_ token: String, remote: GIReaderRemote = .gitee) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(remote) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(remote)
            attributes.forEach { q[$0] = $1 }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CredentialError() }
        } else if status != errSecSuccess { throw CredentialError() }
    }
    static func delete(remote: GIReaderRemote = .gitee) throws {
        let status = SecItemDelete(query(remote) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError() }
    }
    struct CredentialError: LocalizedError {
        var errorDescription: String? { "无法访问钥匙串，请确认系统授权后重试。令牌未写入普通配置文件。" }
    }
}

struct GIConnectionConfiguration: Codable, Identifiable {
    let remote: GIReaderRemote
    var enabled: Bool = true
    var accountID: Int64? = nil
    var id: String { remote.storagePrefix }
}
private struct GIConnectionRegistry: Codable {
    var version = 2
    var connections: [GIConnectionConfiguration]
}
struct GIRepositoryLoadState {
    var nextPage: Int? = 1
    var loading = false
    var failure: GIRepositoryFailure?
    var lastSuccess: Date?
    var needsReset = true
}
@MainActor private final class GISiteSession {
    let remote: GIReaderRemote
    var account: GIUser?
    var api: (any GIIssueService)?
    var selected: [GIRepository] = []
    var repositories: [GIRepository] = []
    var connectionError: String?
    var repositoryError: String?
    var connecting = false
    var restoring = false
    var loadingRepositories = false
    var repositoryNextPage: Int? = 1
    var source = "subscriptions"
    var generation = UUID()
    var authGeneration = UUID()
    var repositoryGeneration = UUID()
    var listGeneration = UUID()
    var authTask: Task<Void, Never>?
    var repositoryTask: Task<Void, Never>?
    var listTask: Task<Void, Never>?
    init(_ remote: GIReaderRemote) { self.remote = remote }
    func stop() {
        generation = UUID(); authGeneration = UUID(); repositoryGeneration = UUID(); listGeneration = UUID()
        authTask?.cancel(); repositoryTask?.cancel(); listTask?.cancel()
        authTask = nil; repositoryTask = nil; listTask = nil
        api?.cancel(); api = nil; account = nil; connecting = false; loadingRepositories = false
        repositories = []; repositoryNextPage = 1; repositoryError = nil
    }
}

@MainActor
final class GIStore: ObservableObject {
    static let shared = GIStore()
    /// Editing selection only. Reading never dispatches through this property.
    @Published private(set) var remote: GIReaderRemote = .gitee
    @Published private(set) var connections: [GIConnectionConfiguration] = []
    @Published private(set) var account: GIUser?
    @Published private(set) var demoMode = false
    @Published private(set) var isConnecting = false
    @Published var connectionError: String?
    @Published private(set) var repositories: [GIRepository] = []
    @Published private(set) var selectedRepositories: [GIRepository] = []
    @Published private(set) var loadingRepositories = false
    @Published private(set) var moreRepositories = false
    @Published var repositoryError: String?
    @Published private(set) var items: [GIListItem] = []
    @Published private(set) var loadingList = false
    @Published private(set) var listFailures: [GIRepositoryFailure] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var repositoryStates: [String: GIRepositoryLoadState] = [:]
    @Published var repositoryFilter = "" // compatibility; never a hidden project filter
    @Published var selectedLabels: Set<String> = []
    @Published private(set) var collapsedProjects: Set<String> = []
    @Published var query = ""
    @Published var stateFilter = "unfinished"
    @Published var selectedListID: GIIssueRoute?
    @Published private(set) var history = GIHistory()
    @Published private(set) var pages: [GIIssueRoute: GIPage] = [:]
    @Published private(set) var loadingDetail = false
    @Published var detailError: String?
    @Published var notice: String?
    @Published var loadRemoteImages = false
    @Published var textScale = 1.0
    private var sessions: [GIReaderRemote: GISiteSession] = [:]
    private var epoch = UUID()
    private var detailTask: Task<Void, Never>?
    private var cacheOrder: [GIIssueRoute] = []
    private var cancellables = Set<AnyCancellable>()
    private let preferences: UserDefaults
    private let enabled: () -> Bool
    private let readCredential: (GIReaderRemote) throws -> String?
    private let saveCredential: (String, GIReaderRemote) throws -> Void
    private let deleteCredential: (GIReaderRemote) throws -> Void
    private let makeClient: (GIReaderRemote, String) -> any GIIssueService

    /// Injectable boundaries keep regression tests away from real Keychain, defaults and network.
    init(preferences: UserDefaults = .standard, observePreference: Bool = true,
         enabled: @escaping () -> Bool = { Defaults[.enableGiteeReader] },
         readCredential: @escaping (GIReaderRemote) throws -> String? = { try GICredential.read(remote: $0) },
         saveCredential: @escaping (String, GIReaderRemote) throws -> Void = { try GICredential.save($0, remote: $1) },
         deleteCredential: @escaping (GIReaderRemote) throws -> Void = { try GICredential.delete(remote: $0) },
         makeClient: @escaping (GIReaderRemote, String) -> any GIIssueService = { site, token in
             switch site.provider {
             case .gitee: return GIAPI(token: token)
             case .gitlab: return GLAPI(remote: site, token: token)
             case .github: return GHAPI(token: token)
             }
         }) {
        self.preferences = preferences; self.enabled = enabled
        self.readCredential = readCredential; self.saveCredential = saveCredential
        self.deleteCredential = deleteCredential; self.makeClient = makeClient
        if let data = preferences.data(forKey: "toolisle.reader.remote"),
           let value = try? JSONDecoder().decode(GIReaderRemote.self, from: data) { remote = value }
        if let data = preferences.data(forKey: "toolisle.reader.connections.v2"),
           let registry = try? JSONDecoder().decode(GIConnectionRegistry.self, from: data), registry.version == 2 {
            var seen = Set<GIReaderRemote>()
            connections = registry.connections.filter { seen.insert($0.remote).inserted }
        } else {
            // Migrate all recoverable legacy site metadata, not only the last visible site.
            var sites: Set<GIReaderRemote> = [.gitee, remote]
            if let saved = preferences.string(forKey: "toolisle.reader.gitlabServer"), let site = try? GIReaderRemote.gitLab(saved) { sites.insert(site) }
            for key in preferences.dictionaryRepresentation().keys where key.hasPrefix("toolisle.gitlab.") {
                let suffix = String(key.dropFirst("toolisle.gitlab.".count))
                guard let boundary = suffix.range(of: ".selection."),
                      let bytes = Data(base64Encoded: String(suffix[..<boundary.lowerBound])),
                      let address = String(data: bytes, encoding: .utf8), let site = try? GIReaderRemote.gitLab(address) else { continue }
                sites.insert(site)
            }
            connections = sites.sorted { $0.webURL.absoluteString < $1.webURL.absoluteString }.map { GIConnectionConfiguration(remote: $0) }
            // Old keys and credentials are deliberately not deleted. This operation is idempotent.
            persistConnections()
        }
        if !connections.contains(where: { $0.remote == remote }) { remote = connections.first?.remote ?? .gitee }
        for configuration in connections {
            let session = GISiteSession(configuration.remote)
            if let id = configuration.accountID { session.selected = savedSelection(site: configuration.remote, accountID: id) }
            sessions[configuration.remote] = session
        }
        publishState()
        if observePreference {
            Defaults.publisher(.enableGiteeReader, options: []).receive(on: DispatchQueue.main)
                .sink { [weak self] change in if !change.newValue { self?.deactivate() } }
                .store(in: &cancellables)
        }
    }
    var platformName: String { remote.name }
    var readingRemote: GIReaderRemote { visit?.route.remote ?? .gitee }
    var readingPlatformName: String { readingRemote.name }
    var savedGitLabServer: String { preferences.string(forKey: "toolisle.reader.gitlabServer") ?? "https://gitlab.com" }
    var projectSourceTitle: String { remote.isGitLab ? "参与项目 / Star" : "Watch / Star" }
    var availableStates: [String] { GIListPresentation.states }
    var settingsSelectedRepositories: [GIRepository] { demoMode ? selectedRepositories : sessions[remote]?.selected ?? [] }
    var hasReadingSources: Bool { demoMode || !selectedRepositories.isEmpty || sessions.values.contains { $0.account != nil } }
    var connectingAny: Bool { sessions.values.contains { $0.connecting } }
    var visit: GIVisit? { history.current }
    var currentPage: GIPage? { visit.flatMap { pages[$0.route] } }
    var hasMoreIssues: Bool { repositoryStates.values.contains { $0.nextPage != nil } }
    var candidateItems: [GIListItem] { GIListPresentation.candidates(items, state: stateFilter, query: query) }
    var labelFacets: [GILabelFacet] { GIListPresentation.facets(candidateItems) }
    var filteredItems: [GIListItem] { GIListPresentation.filter(candidateItems, labels: selectedLabels) }
    var issueGroups: [GIProjectGroup] { GIListPresentation.groups(filteredItems, repositories: selectedRepositories) }
    var hasActiveFilters: Bool { !query.isEmpty || stateFilter != "all" || !selectedLabels.isEmpty }
    var filterSummary: String { "全部已选仓库 · " + GIListPresentation.stateTitle(stateFilter) + (query.isEmpty ? "" : " · 搜索：" + query) + (selectedLabels.isEmpty ? "" : " · 标签 \(selectedLabels.count) 项") }
    func clearFilters() { query = ""; repositoryFilter = ""; stateFilter = "all"; selectedLabels = [] }
    func toggleLabel(_ name: String) { if selectedLabels.contains(name) { selectedLabels.remove(name) } else { selectedLabels.insert(name) } }
    private func session(_ site: GIReaderRemote) -> GISiteSession {
        if let existing = sessions[site] { return existing }
        let value = GISiteSession(site); sessions[site] = value; return value
    }
    func isEnabled(_ site: GIReaderRemote) -> Bool { connections.first { $0.remote == site }?.enabled == true }
    func connectionStatus(_ site: GIReaderRemote) -> String {
        guard isEnabled(site) else { return "已停用" }
        guard let value = sessions[site] else { return "未连接" }
        return value.connecting ? "正在连接…" : value.connectionError ?? value.account.map { "已连接 · @" + $0.login } ?? "未连接"
    }
    private func persistConnections() {
        if let data = try? JSONEncoder().encode(GIConnectionRegistry(connections: connections)) { preferences.set(data, forKey: "toolisle.reader.connections.v2") }
    }
    private func selectionKey(site: GIReaderRemote, accountID: Int64) -> String { "\(site.storagePrefix).selection.\(accountID)" }
    private func savedSelection(site: GIReaderRemote, accountID: Int64) -> [GIRepository] {
        guard let data = preferences.data(forKey: selectionKey(site: site, accountID: accountID)), let values = try? JSONDecoder().decode([GIRepository].self, from: data) else { return [] }
        return values.map { $0.on(site) }.filter { !$0.path.isEmpty }
    }
    private func saveSelection(_ value: GISiteSession) {
        guard !demoMode, let user = value.account, let data = try? JSONEncoder().encode(value.selected) else { return }
        preferences.set(data, forKey: selectionKey(site: value.remote, accountID: user.id))
    }
    private func publishState() {
        guard !demoMode else { return }
        let value = sessions[remote]
        account = value?.account; isConnecting = value?.connecting ?? false; connectionError = value?.connectionError
        repositories = value?.repositories ?? []; loadingRepositories = value?.loadingRepositories ?? false
        moreRepositories = value?.repositoryNextPage != nil && value?.account != nil
        repositoryError = value?.repositoryError
        selectedRepositories = sessions.values.filter { isEnabled($0.remote) }.flatMap(\.selected).sorted { $0.canonicalURL < $1.canonicalURL }
        loadingList = repositoryStates.values.contains { $0.loading }
        listFailures = repositoryStates.values.compactMap(\.failure).sorted { $0.repository < $1.repository }
        objectWillChange.send() // derived per-connection properties have no individual publishers
    }
    func useRemote(_ value: GIReaderRemote) {
        if demoMode { deactivate() }
        remote = value
        if !connections.contains(where: { $0.remote == value }) { connections.append(GIConnectionConfiguration(remote: value)) }
        _ = session(value)
        if let url = value.gitLabURL { preferences.set(url.absoluteString, forKey: "toolisle.reader.gitlabServer") }
        if let data = try? JSONEncoder().encode(value) { preferences.set(data, forKey: "toolisle.reader.remote") }
        persistConnections(); publishState(); activate()
    }
    func setEnabled(_ site: GIReaderRemote, _ value: Bool) {
        guard let index = connections.firstIndex(where: { $0.remote == site }) else { return }
        connections[index].enabled = value; persistConnections()
        if !value { stopSite(site, clearSelection: false) }
        else { sessions[site]?.restoring = false }
        publishState(); if value { activate() }
    }
    /// On-demand only: opening an opt-in surface restores all enabled connections independently.
    func activate() {
        guard enabled(), !demoMode else { return }
        for config in connections where config.enabled {
            let value = session(config.remote)
            guard !value.restoring, value.account == nil, !value.connecting else { continue }
            value.restoring = true
            do { if let token = try readCredential(config.remote) { connect(token, to: config.remote) } }
            catch { value.connectionError = "无法读取钥匙串。请重新连接该站点账户。" }
        }
        publishState()
    }
    func connect(_ input: String) { connect(input, to: remote) }
    private func connect(_ input: String, to site: GIReaderRemote) {
        guard enabled(), isEnabled(site), !demoMode else { return }
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines), value = session(site)
        guard !token.isEmpty, token.count <= 4096, !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            value.connectionError = "令牌格式不正确。"; publishState(); return
        }
        // Replacing a credential invalidates only that connection's private content immediately.
        stopSite(site, clearSelection: false)
        let attempt = UUID(); value.authGeneration = attempt; value.connecting = true; value.connectionError = nil; value.restoring = true
        publishState()
        let client = makeClient(site, token)
        value.authTask = Task { [weak self] in
            guard let self else { client.cancel(); return }
            do {
                let user = try await client.user()
                guard !Task.isCancelled, value.authGeneration == attempt, self.enabled(), self.isEnabled(site) else { client.cancel(); return }
                try self.saveCredential(token, site)
                value.api = client; value.account = user
                value.selected = self.savedSelection(site: site, accountID: user.id)
                if let index = self.connections.firstIndex(where: { $0.remote == site }) { self.connections[index].accountID = user.id; self.persistConnections() }
                let collapsed = Set(self.preferences.stringArray(forKey: "\(site.storagePrefix).collapsedProjects.\(user.id)") ?? [])
                for repo in value.selected where collapsed.contains(repo.canonicalURL) || collapsed.contains("repo:\(repo.id)") { self.collapsedProjects.insert(repo.canonicalURL) }
                self.refreshRepositories(site: site, source: "subscriptions", reset: true)
                self.refreshIssues(site: site, reset: true, only: nil)
            } catch {
                client.cancel()
                if !Task.isCancelled, value.authGeneration == attempt { value.connectionError = (error as? GICredential.CredentialError)?.localizedDescription ?? GIServiceError.message(error) }
            }
            if value.authGeneration == attempt { value.connecting = false; value.authTask = nil; self.publishState() }
        }
    }
    func disconnect() {
        let site = remote, value = session(site)
        do { try deleteCredential(site) }
        catch { value.connectionError = "无法移除钥匙串中的令牌，请重试。"; publishState(); return }
        let id = value.account?.id ?? connections.first(where: { $0.remote == site })?.accountID
        if let id {
            preferences.removeObject(forKey: selectionKey(site: site, accountID: id))
            preferences.removeObject(forKey: "\(site.storagePrefix).collapsedProjects.\(id)")
        }
        if let index = connections.firstIndex(where: { $0.remote == site }) { connections[index].accountID = nil; persistConnections() }
        stopSite(site, clearSelection: true); value.restoring = true; value.connectionError = nil; publishState()
    }
    private func stopSite(_ site: GIReaderRemote, clearSelection: Bool) {
        let value = session(site), currentSite = visit?.route.remote ?? .gitee
        value.stop(); value.restoring = false
        let urls = Set(value.selected.map(\.canonicalURL))
        for url in urls { repositoryStates[url] = nil; collapsedProjects.remove(url) }
        items.removeAll { ($0.route.remote ?? .gitee) == site }
        pages = pages.filter { ($0.key.remote ?? .gitee) != site }
        cacheOrder.removeAll { ($0.remote ?? .gitee) == site }
        if (selectedListID?.remote ?? .gitee) == site { selectedListID = nil }
        history.remove(remote: site)
        if clearSelection { value.selected = [] }
        if currentSite == site {
            detailTask?.cancel(); loadingDetail = false; detailError = nil; notice = nil; loadRemoteImages = false
            // The surviving history entry may belong to a different connection.
            if visit != nil { loadCurrent(force: false) }
        }
    }
    func deactivate() {
        epoch = UUID(); detailTask?.cancel()
        for value in sessions.values { value.stop(); value.restoring = false }
        demoMode = false
        items = []; pages = [:]; cacheOrder = []; repositoryStates = [:]; history.reset(); selectedListID = nil
        loadingDetail = false; detailError = nil; notice = nil; lastSync = nil; loadRemoteImages = false
        query = ""; repositoryFilter = ""; stateFilter = "unfinished"; selectedLabels = []; collapsedProjects = []
        publishState()
    }
    func setProjectExpanded(_ id: String, expanded: Bool) {
        if expanded { collapsedProjects.remove(id) } else { collapsedProjects.insert(id) }
        guard !demoMode, let repo = selectedRepositories.first(where: { $0.canonicalURL == id }), let user = sessions[repo.remote]?.account else { return }
        let urls = Set(sessions[repo.remote]?.selected.map(\.canonicalURL) ?? [])
        preferences.set(collapsedProjects.intersection(urls).sorted(), forKey: "\(repo.remote.storagePrefix).collapsedProjects.\(user.id)")
    }
    func expandMatchingProjects() { for group in issueGroups where !group.items.isEmpty { setProjectExpanded(group.id, expanded: true) } }
    func refreshRepositories(source: String, reset: Bool) { refreshRepositories(site: remote, source: source, reset: reset) }
    private func refreshRepositories(site: GIReaderRemote, source: String, reset: Bool) {
        let value = session(site)
        guard enabled(), isEnabled(site), !demoMode, let client = value.api else { return }
        if value.loadingRepositories && !reset { return }
        value.repositoryTask?.cancel()
        value.source = source == "starred" ? "starred" : "subscriptions"
        if reset { value.repositories = []; value.repositoryNextPage = 1 }
        guard let page = value.repositoryNextPage else { return }
        let generation = UUID(); value.repositoryGeneration = generation
        value.loadingRepositories = true; value.repositoryError = nil; publishState()
        let requestedSource = value.source
        value.repositoryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.repositoryPage(source: requestedSource, page: page)
                guard !Task.isCancelled, value.repositoryGeneration == generation, self.enabled() else { return }
                let repos = result.items.map { $0.on(site) }.filter { !$0.path.isEmpty }
                var unique = Dictionary(value.repositories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                for repo in repos { unique[repo.id] = repo }
                value.repositories = unique.values.sorted { $0.full_name.localizedStandardCompare($1.full_name) == .orderedAscending }
                value.repositoryNextPage = result.nextPage
                let fresh = Dictionary(repos.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                let old = value.selected.map(\.canonicalURL)
                value.selected = value.selected.map { fresh[$0.id] ?? $0 }
                self.saveSelection(value)
                if old != value.selected.map(\.canonicalURL) {
                    let removed = Set(old).subtracting(value.selected.map(\.canonicalURL))
                    self.items.removeAll { removed.contains($0.route.repositoryURL) }
                    for url in removed { self.repositoryStates[url] = nil }
                    self.refreshIssues(site: site, reset: true, only: nil)
                }
            } catch {
                guard !Task.isCancelled, value.repositoryGeneration == generation else { return }
                value.repositoryError = GIServiceError.message(error)
                self.handleUnauthorized(error, site: site)
            }
            if value.repositoryGeneration == generation { value.loadingRepositories = false; value.repositoryTask = nil }
            self.publishState()
        }
    }
    func applySelection(_ selection: [GIRepository]) {
        if demoMode { selectedRepositories = selection; return }
        let value = session(remote)
        var seen = Set<String>()
        value.selected = selection.map { $0.on(remote) }.filter { !$0.path.isEmpty && seen.insert($0.canonicalURL).inserted }.sorted { $0.canonicalURL < $1.canonicalURL }
        saveSelection(value)
        let keep = Set(value.selected.map(\.canonicalURL))
        let stale = Set(selectedRepositories.filter { $0.remote == remote }.map(\.canonicalURL)).subtracting(keep)
        items.removeAll { stale.contains($0.route.repositoryURL) }
        for url in stale { repositoryStates[url] = nil }
        publishState(); refreshIssues(site: remote, reset: true, only: nil)
    }
    func refreshIssues(reset: Bool, only: Set<String>? = nil) {
        for config in connections where config.enabled { refreshIssues(site: config.remote, reset: reset, only: only) }
    }
    private func refreshIssues(site: GIReaderRemote, reset: Bool, only: Set<String>?) {
        let value = session(site)
        guard enabled(), isEnabled(site), !demoMode, let client = value.api else { return }
        let repos = value.selected.filter { only == nil || only!.contains($0.canonicalURL) }
        if repos.isEmpty {
            // Removing the last selection must also invalidate an in-flight response.
            if reset && only == nil {
                value.listTask?.cancel(); value.listTask = nil; value.listGeneration = UUID()
            }
            publishState(); return
        }
        if value.listTask != nil && !reset { return }
        value.listTask?.cancel()
        for repo in value.selected { if repositoryStates[repo.canonicalURL] != nil { repositoryStates[repo.canonicalURL]?.loading = false } }
        let generation = UUID(); value.listGeneration = generation
        var requests: [(GIRepository, Int, Bool)] = []
        for repo in repos {
            var state = repositoryStates[repo.canonicalURL] ?? GIRepositoryLoadState()
            if reset { state.nextPage = 1; state.needsReset = true }
            guard let page = state.nextPage else { continue }
            requests.append((repo, page, state.needsReset)); state.loading = true; state.failure = nil
            repositoryStates[repo.canonicalURL] = state
        }
        guard !requests.isEmpty else { value.listTask = nil; publishState(); return }
        publishState()
        // Parallel connections, serial repository requests within each connection.
        value.listTask = Task { [weak self] in
            guard let self else { return }
            for (repo, page, replace) in requests {
                guard !Task.isCancelled, value.listGeneration == generation, self.enabled() else { return }
                let key = repo.canonicalURL
                do {
                    let result = try await client.issuePage(repository: repo.path, page: page)
                    guard !Task.isCancelled, value.listGeneration == generation, self.enabled() else { return }
                    if replace { self.items.removeAll { $0.route.repositoryURL == key } }
                    var merged = Dictionary(self.items.map { ($0.route, $0) }, uniquingKeysWith: { a, _ in a })
                    for issue in result.items {
                        let route = GIIssueRoute(repository: repo.path, number: issue.number, remote: site)
                        merged[route] = GIListItem(route: route, issue: issue)
                    }
                    self.items = merged.values.sorted(by: GIListPresentation.newer)
                    self.repositoryStates[key] = GIRepositoryLoadState(nextPage: result.nextPage, loading: false, failure: nil, lastSuccess: Date(), needsReset: false)
                } catch {
                    guard !Task.isCancelled, value.listGeneration == generation else { return }
                    if self.handleUnauthorized(error, site: site) { self.publishState(); return }
                    if let service = error as? GIServiceError {
                        switch service {
                        case .forbidden, .missing: self.purgeRepository(key)
                        default: break
                        }
                    }
                    self.repositoryStates[key]?.loading = false
                    self.repositoryStates[key]?.failure = GIRepositoryFailure(repository: key, error: error)
                }
                self.publishState()
            }
            if value.listGeneration == generation {
                value.listTask = nil
                if !self.repositoryStates.values.contains(where: { $0.loading || $0.failure != nil }) { self.lastSync = Date() }
                self.publishState()
            }
        }
    }
    private func purgeRepository(_ url: String) {
        items.removeAll { $0.route.repositoryURL == url }
        pages = pages.filter { $0.key.repositoryURL != url }; cacheOrder.removeAll { $0.repositoryURL == url }
    }
    @discardableResult private func handleUnauthorized(_ error: Error, site: GIReaderRemote) -> Bool {
        guard let error = error as? GIServiceError, case .missingToken = error else { return false }
        stopSite(site, clearSelection: false)
        let value = session(site); value.restoring = true; value.connectionError = GIServiceError.message(error)
        publishState(); return true
    }
    func retryFailedRepositories() {
        let keys = Set(listFailures.map(\.repository))
        refreshIssues(reset: false, only: keys)
    }
    func groupMessage(_ url: String) -> String? {
        if let error = repositoryStates[url]?.failure { return error.message }
        if let repo = selectedRepositories.first(where: { $0.canonicalURL == url }), let value = sessions[repo.remote], value.account == nil {
            return value.connecting ? "正在验证账户…" : value.connectionError ?? "请先连接此仓库所属站点。"
        }
        return nil
    }
    func open(_ route: GIIssueRoute, fragment: String? = nil, fromList: Bool = false) {
        guard enabled(), demoMode || (isEnabled(route.remote ?? .gitee) && sessions[route.remote ?? .gitee]?.api != nil) else { return }
        if visit?.route.remote != route.remote { loadRemoteImages = false }
        if fromList { selectedListID = route }
        history.push(route, fragment: fragment)
        notice = nil
        loadCurrent(force: false)
    }
    func moveHistory(_ offset: Int) {
        let previous = visit?.route.remote
        history.move(offset)
        if previous != visit?.route.remote { loadRemoteImages = false }
        notice = nil; loadCurrent(force: false)
    }
    func snapshot(id: UUID, y: Double, anchorHandled: Bool? = nil) {
        history.snapshot(id: id, y: y, anchorHandled: anchorHandled)
    }
    func handleLink(_ raw: String, visitID: UUID) {
        guard enabled(), let visit, visit.id == visitID else { return }
        let site = visit.route.remote ?? .gitee
        let canonical = currentPage?.issue.html_url.flatMap(URL.init(string:))
        let base = canonical.flatMap { site.contains($0) ? $0 : nil } ?? visit.route.url
        let target = GIIssueLinks.resolve(raw, relativeTo: base, remote: site)
        switch target {
        case .issue(let route, let fragment): open(route, fragment: fragment)
        case .external(let url):
            // Only registered, connected sites may receive credentialed internal navigation.
            let sites = connections.filter { $0.enabled && sessions[$0.remote]?.api != nil }.map(\.remote)
            for other in sites where other != site {
                if case .issue(let route, let fragment) = GIIssueLinks.resolve(url.absoluteString, relativeTo: base, remote: other) {
                    open(route, fragment: fragment); return
                }
            }
            NSWorkspace.shared.open(url)
        case .blocked: notice = "此链接的协议、地址或参数不安全，未打开。"
        }
    }

    func browserOpen() {
        guard let visit else { return }
        NSWorkspace.shared.open(visit.sourceURL)
    }
    func loadCurrent(force: Bool) {
        detailTask?.cancel(); loadingDetail = false; detailError = nil
        guard enabled(), let visit else { return }
        if demoMode { loadDemo(visit.route); return }
        if !force, let cached = pages[visit.route] {
            if let anchor = GIIssueLinks.commentID(visit.fragment), !visit.anchorHandled,
               !cached.comments.contains(where: { $0.id == anchor }), cached.hasMoreComments {
                // Fall through to the bounded anchor-aware load below.
            } else { return }
        }
        let site = visit.route.remote ?? .gitee
        guard let value = sessions[site], let client = value.api else { detailError = "请先连接此 Issue 所属的 Git 站点。"; return }
        let siteGeneration = value.generation
        loadingDetail = true
        let session = epoch, visitID = visit.id, route = visit.route
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let issue = try await client.issue(route)
                var comments: [GIComment] = []
                var nextPage = 1, hasMore = true
                var commentWarning: String?
                repeat {
                    do {
                        let result = try await client.commentPage(route, page: nextPage)
                        comments.append(contentsOf: result.items)
                        hasMore = result.nextPage != nil; nextPage = result.nextPage ?? nextPage + 1
                    } catch {
                        if Task.isCancelled { return }
                        if self.handleUnauthorized(error, site: site) { return }
                        commentWarning = "正文已加载，评论未能完整加载：\(GIServiceError.message(error))"
                        break
                    }
                    guard !Task.isCancelled, self.epoch == session, value.generation == siteGeneration, self.visit?.id == visitID else { return }
                    guard let anchor = GIIssueLinks.commentID(visit.fragment), !comments.contains(where: { $0.id == anchor }) else { break }
                } while hasMore && comments.count < 1000
                guard !Task.isCancelled, self.epoch == session, value.generation == siteGeneration, self.visit?.id == visitID else { return }
                var seen = Set<Int64>(); comments = comments.filter { seen.insert($0.id).inserted }
                self.pages[route] = GIPage(issue: issue, comments: comments, nextCommentPage: nextPage, hasMoreComments: hasMore)
                self.touchCache(route)
                self.notice = commentWarning
                if let anchor = GIIssueLinks.commentID(visit.fragment), !comments.contains(where: { $0.id == anchor }) {
                    self.notice = "未找到指定评论，可能已删除或超出已加载范围。原链接已保留，可在平台网页打开。"
                }
            } catch {
                guard !Task.isCancelled, self.epoch == session, value.generation == siteGeneration, self.visit?.id == visitID else { return }
                if self.handleUnauthorized(error, site: site) { return }
                self.detailError = GIServiceError.message(error)
                // A failed permission recheck must not continue displaying a previously cached private page.
                self.pages[route] = nil
                if let service = error as? GIServiceError {
                    switch service {
                    case .forbidden, .missing: self.purgeRepository(route.repositoryURL)
                    default: break
                    }
                }
            }
            if self.epoch == session && value.generation == siteGeneration && self.visit?.id == visitID && !Task.isCancelled { self.loadingDetail = false }
        }
    }
    func moreComments() {
        guard enabled(), !loadingDetail, let visit, var page = currentPage, page.hasMoreComments,
              let value = sessions[visit.route.remote ?? .gitee], let client = value.api else { return }
        let siteGeneration = value.generation
        guard page.comments.count < 1000 else { notice = "已加载 1000 条评论。更多内容请在平台网页打开。"; return }
        detailTask?.cancel(); loadingDetail = true
        let session = epoch, visitID = visit.id
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.commentPage(visit.route, page: page.nextCommentPage)
                let extra = result.items
                guard !Task.isCancelled, self.epoch == session, value.generation == siteGeneration, self.visit?.id == visitID else { return }
                var ids = Set(page.comments.map(\.id))
                page.comments.append(contentsOf: extra.filter { ids.insert($0.id).inserted })
                page.nextCommentPage = result.nextPage ?? page.nextCommentPage + 1; page.hasMoreComments = result.nextPage != nil; page.revision = UUID()
                self.pages[visit.route] = page
            } catch {
                guard !Task.isCancelled, self.epoch == session, value.generation == siteGeneration, self.visit?.id == visitID else { return }
                if self.handleUnauthorized(error, site: visit.route.remote ?? .gitee) { return }
                self.notice = GIServiceError.message(error)
            }
            if self.epoch == session && value.generation == siteGeneration && self.visit?.id == visitID && !Task.isCancelled { self.loadingDetail = false }
        }
    }
    private func touchCache(_ route: GIIssueRoute) {
        cacheOrder.removeAll { $0 == route }; cacheOrder.append(route)
        while cacheOrder.count > 30 { pages[cacheOrder.removeFirst()] = nil }
    }

    /// Explicit synthetic preview: no Gitee requests, no writes to the stored credential or selection.
    func startDemo() {
        deactivate(); remote = .gitee
        Defaults[.enableGiteeReader] = true
        demoMode = true
        account = GIUser(id: -1, login: "demo", name: "离线演示 · 非真实项目")
        let repos = [GIRepository(id: -1, full_name: "toolisle-demo/workbench", name: "Workbench", description: "演示项目", html_url: nil),
                     GIRepository(id: -2, full_name: "toolisle-demo/shared", name: "Shared", description: "跨仓库跳转示例", html_url: nil)]
        repositories = repos; selectedRepositories = [repos[0]]
        items = [GIListItem(route: Self.demoA, issue: Self.demoIssue(Self.demoA))]
        lastSync = Date(); open(Self.demoA, fromList: true)
    }
    func setUXDemoCount(_ count: Int) {
        guard demoMode, ProcessInfo.processInfo.arguments.contains("--gitee-ux-probe") else { return }
        items = (0..<max(0, min(count, 20))).map { n in
            let route = n == 0 ? Self.demoA : GIIssueRoute(repository: Self.demoA.repository, number: "IDEMO\(n)")
            let issue = GIIssue(id: Int64(n + 1), number: route.number,
                title: n == 0 ? Self.demoIssue(Self.demoA).title : "离线演示 \(n + 1)：验证列表、筛选与窗口交互",
                state: "progressing", body: nil, html_url: route.url.absoluteString,
                user: account, updated_at: "2026-09-22T08:30:00+08:00", comments: 0)
            return GIListItem(route: route, issue: issue)
        }
    }
    /// Explicit synthetic UI regression only. Never changes credentials or saved project choices.
    func installLabelFixtures() {
        guard demoMode, ProcessInfo.processInfo.arguments.contains("--gitee-label-probe") else { return }
        selectedRepositories = [
            GIRepository(id: -1, full_name: Self.demoA.repository, name: "协作工作台 · 演示", description: nil, html_url: nil),
            GIRepository(id: -2, full_name: Self.demoB.repository, name: "共享组件 · 演示", description: nil, html_url: nil)]
        let many = (1...120).map { GIIssueLabel(name: "模块标签-\($0)", color: $0 % 2 == 0 ? "#5382C5" : "#B65E8A") }
        items = (0..<12).map { n in
            let route = n == 0 ? Self.demoA : (n == 6 ? Self.demoB : GIIssueRoute(repository: n < 6 ? Self.demoA.repository : Self.demoB.repository, number: "ITAG\(n)"))
            let state = ["open", "progressing", "closed"][n % 3]
            let labels = [GIIssueLabel(name: n % 2 == 0 ? "bug" : "文档", color: "#D26843"),
                          GIIssueLabel(name: "后端", color: "#5283CE"),
                          GIIssueLabel(name: "优先处理", color: "#BD8534")] + (n == 0 ? many : [many[n]])
            return GIListItem(route: route, issue: GIIssue(id: Int64(n + 1), number: route.number,
                title: n == 0 ? Self.demoIssue(Self.demoA).title : ["改进关联讨论的阅读体验", "补充接口错误反馈与说明", "修复列表选择后的焦点问题"][n % 3],
                state: state, body: nil, html_url: route.url.absoluteString, user: account,
                updated_at: "2026-09-22T08:30:00+08:00", comments: 0, labels: labels))
        }
    }
    static let demoA = GIIssueRoute(repository: "toolisle-demo/workbench", number: "IDEMOA")
    static let demoB = GIIssueRoute(repository: "toolisle-demo/shared", number: "IDEMOB")
    private func loadDemo(_ route: GIIssueRoute) {
        guard route == Self.demoA || route == Self.demoB else { detailError = "演示模式不请求网络。此目标不在演示数据中。"; return }
        guard pages[route] == nil else { return }
        let comments = [GIComment(id: 101, body: "这是演示评论。点击[关联 Issue B](\(Self.demoB.url.absoluteString)#note_202)可跨仓库定位到评论。", user: account, created_at: "2026-09-22T08:00:00+08:00"),
                        GIComment(id: 202, body: "### 定位成功\n这条评论用来验证带锚点的跳转。\n\n[返回 Issue A](\(Self.demoA.url.absoluteString))，也可使用窗口左上角后退按钮恢复原阅读位置。", user: account, created_at: "2026-09-22T08:30:00+08:00")]
        pages[route] = GIPage(issue: Self.demoIssue(route), comments: comments, nextCommentPage: 2, hasMoreComments: false)
    }
    static func demoIssue(_ route: GIIssueRoute) -> GIIssue {
        let body = route == demoA ? "## 在 Atoll 中连续阅读 Issue\n这是**离线演示数据**，用于验收布局与链接，未连接真实 Gitee 账户。\n\n### 关联阅读\n先向下滚动，再点击[另一个仓库的 Issue B](\(demoB.url.absoluteString)#note_202)。使用后退应恢复当前位置，左侧项目筛选不变。\n\n| 能力 | 状态 |\n| --- | --- |\n| 原版 Atoll | 保留 |\n| Markdown 表格、代码 | 支持 |\n| 本地文件读取 | 不在本期范围 |\n\n- [x] 单窗口阅读\n- [x] 关联 Issue 导航\n- [ ] 实际 Gitee 账户与多屏验收\n\n```swift\nlet destination = GIIssueRoute(repository: \"team/project\", number: \"IABC12\")\n// 代码中的 https://gitee.com/example/demo/issues/I123 不自动导航。\n```\n\n> 阅读内容使用稳定背景；原刘海窗口仍由 Atoll 管理。\n\n![演示图片](https://foruda.gitee.com/images/toolisle-fixture.png)\n\n### 阅读位置测试\n" + Array(repeating: "阅读正文和评论时，可选择并复制文字。后台任务不会抢占焦点或切换刘海页面。\n\n", count: 10).joined() + "[跨仓库跳转到 B 的评论](\(demoB.url.absoluteString)#note_202)\n\n[普通网页](https://gitee.com)在浏览器打开。" : "## 关联 Issue B\n这是另一个**未加入查看列表**的项目，点击关联链接只加载详情，不改变左侧列表，也不自动关注。\n\n[继续阅读 A](\(demoA.url.absoluteString))\n\n### 评论定位\n链接中的 `#note_202` 应滚动到下方对应评论。"
        return GIIssue(id: route == demoA ? 1 : 2, number: route.number,
                       title: route == demoA ? "Gitee Issue 阅读与关联跳转" : "共享模块：跨仓库问题跟踪",
                       state: "progressing", body: body, html_url: route.url.absoluteString,
                       user: GIUser(id: -1, login: "demo", name: "演示维护者"), updated_at: "2026-09-22T08:30:00+08:00", comments: 2)
    }
}
