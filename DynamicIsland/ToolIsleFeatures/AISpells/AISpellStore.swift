// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

/// UI state for the saved prompt library. Failed loads leave the original file untouched
/// and disable mutation until a successful reload, rather than presenting a writable empty list.
@MainActor
final class AISpellStore: ObservableObject {
    static let shared = AISpellStore()

    @Published private(set) var spells: [AISpell] = []
    @Published private(set) var isReadOnly = true
    @Published var errorMessage: String?

    let fileURL: URL
    private var library: AISpellLibrary?

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ToolIsle/AISpells/library.json")
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        reload()
    }

    var categories: [String] { library?.categories ?? [] }

    func results(query: String = "", category: String? = nil, favoritesOnly: Bool = false) -> [AISpell] {
        library?.results(query: query, category: category, favoritesOnly: favoritesOnly) ?? []
    }

    func reload() {
        do {
            library = try AISpellLibrary(fileURL: fileURL)
            spells = library?.spells ?? []
            isReadOnly = false
            errorMessage = nil
        } catch {
            library = nil
            isReadOnly = true
            errorMessage = "无法打开 AI 咒语库，原文件未被覆盖。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ spell: AISpell) -> Bool {
        change { try $0.save(spell) }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        change { try $0.delete(id: id) }
    }

    @discardableResult
    func toggleFavorite(id: UUID) -> Bool {
        change { try $0.toggleFavorite(id: id) }
    }

    func exportData() -> Data? {
        guard let library else { return nil }
        do {
            let data = try library.exportData()
            errorMessage = nil
            return data
        } catch {
            errorMessage = "无法导出 AI 咒语：\(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func importData(_ data: Data) -> Int? {
        guard let library else { return nil }
        do {
            let added = try library.importData(data)
            spells = library.spells
            errorMessage = nil
            return added
        } catch {
            errorMessage = "导入失败，现有咒语未改变。\n\(error.localizedDescription)"
            return nil
        }
    }

    private func change(_ operation: (AISpellLibrary) throws -> Void) -> Bool {
        guard let library else { return false }
        do {
            try operation(library)
            spells = library.spells
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存失败，现有咒语未改变。\n\(error.localizedDescription)"
            return false
        }
    }
}
