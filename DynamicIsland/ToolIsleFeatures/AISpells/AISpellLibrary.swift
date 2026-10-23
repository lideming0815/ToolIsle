// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A deliberately saved prompt. Its content is copied verbatim, including whitespace.
struct AISpell: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    var category: String
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, content: String, category: String = "",
         isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum AISpellLibraryError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidTitle
    case emptyContent
    case duplicateIdentifiers
    case spellNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "无法读取版本 \(version) 的咒语库。原文件已保留，请使用兼容版本打开。"
        case .invalidTitle:
            return "请为咒语填写标题。"
        case .emptyContent:
            return "咒语内容不能为空。"
        case .duplicateIdentifiers:
            return "咒语文件包含重复标识，未导入任何内容。"
        case .spellNotFound:
            return "这条咒语已不存在，请重新选择。"
        }
    }
}

/// Owns the independent, versioned prompt file. Changes become visible only after an
/// atomic write succeeds; clipboard history settings and cleanup never enter this module.
final class AISpellLibrary {
    private struct Document: Codable {
        let schemaVersion: Int
        let spells: [AISpell]
    }

    private struct Version: Decodable {
        let schemaVersion: Int
    }

    let fileURL: URL
    private(set) var spells: [AISpell]

    /// Samples are installed only for a genuinely absent file, including on the first
    /// launch. Unreadable, corrupt, unsupported, and intentionally empty files are distinct.
    init(fileURL: URL, seedIfMissing: Bool = true) throws {
        self.fileURL = fileURL
        self.spells = []
        do {
            self.spells = try Self.decode(Data(contentsOf: fileURL))
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            try persist(seedIfMissing ? Self.examples : [])
        }
    }

    var categories: [String] {
        Array(Set(spells.map(\.category).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Space-separated terms all have to match, across the title, category, and complete
    /// content. Favorite ordering stays stable while searching or filtering a category.
    func results(query: String = "", category: String? = nil, favoritesOnly: Bool = false) -> [AISpell] {
        let terms = Self.searchable(query).split(whereSeparator: { $0.isWhitespace })
        return spells.filter { spell in
            guard !favoritesOnly || spell.isFavorite else { return false }
            guard category == nil || spell.category == category else { return false }
            let searchable = Self.searchable([spell.title, spell.category, spell.content].joined(separator: "\n"))
            return terms.allSatisfy { searchable.contains($0) }
        }.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Insert a new prompt or update the same identity. Body text is never trimmed.
    func save(_ spell: AISpell) throws {
        var candidate = try Self.validated(spell)
        var updated = spells
        if let index = updated.firstIndex(where: { $0.id == spell.id }) {
            let old = updated[index]
            candidate = AISpell(id: old.id, title: candidate.title, content: candidate.content,
                                category: candidate.category, isFavorite: candidate.isFavorite,
                                createdAt: old.createdAt, updatedAt: Date())
            updated[index] = candidate
        } else {
            candidate.updatedAt = Date()
            updated.append(candidate)
        }
        try persist(updated)
    }

    func delete(id: UUID) throws {
        guard spells.contains(where: { $0.id == id }) else { throw AISpellLibraryError.spellNotFound }
        try persist(spells.filter { $0.id != id })
    }

    func toggleFavorite(id: UUID) throws {
        guard var spell = spells.first(where: { $0.id == id }) else { throw AISpellLibraryError.spellNotFound }
        spell.isFavorite.toggle()
        try save(spell)
    }

    func exportData() throws -> Data {
        try Self.encode(spells)
    }

    /// Validate the entire backup before changing anything. Matching identities retain
    /// the local version, so importing an old backup cannot replace newer edits.
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let incoming = try Self.decode(data)
        let existingIDs = Set(spells.map(\.id))
        let additions = incoming.filter { !existingIDs.contains($0.id) }
        if !additions.isEmpty { try persist(spells + additions) }
        return additions.count
    }

    private func persist(_ updated: [AISpell]) throws {
        let data = try Self.encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        spells = updated
    }

    private static func encode(_ spells: [AISpell]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(Document(schemaVersion: 1, spells: spells))
    }

    private static func decode(_ data: Data) throws -> [AISpell] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let version = try decoder.decode(Version.self, from: data).schemaVersion
        guard version == 1 else { throw AISpellLibraryError.unsupportedVersion(version) }
        let document = try decoder.decode(Document.self, from: data)
        guard Set(document.spells.map(\.id)).count == document.spells.count else {
            throw AISpellLibraryError.duplicateIdentifiers
        }
        return try document.spells.map(validated)
    }

    private static func validated(_ spell: AISpell) throws -> AISpell {
        var cleaned = spell
        cleaned.title = spell.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.category = spell.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else { throw AISpellLibraryError.invalidTitle }
        guard !cleaned.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AISpellLibraryError.emptyContent
        }
        return cleaned
    }

    private static func searchable(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static var examples: [AISpell] {
        [
            AISpell(title: "发现遗漏与不确定性",
                    content: "关于当前情况，最大的遗漏是什么，我没有意识到什么？眼下你最没有把握的事情是什么？",
                    category: "思考复盘"),
            AISpell(title: "补充身份与背景",
                    content: "\"Giving it context on who you are and what.\"\n“赋予它背景，说明你是谁以及你是什么",
                    category: "上下文"),
            AISpell(title: "减少编程中的未知因素",
                    content: "\"The best agentic coders are good have relatively few unknowns.\"\n“优秀的智能程序员往往未知因素相对较少。”",
                    category: "编程"),
            AISpell(title: "追问更深层的问题",
                    content: "在我们反复讨论过的所有问题中，有没有一个更深层次的问题，是我一直在围着它打转，却始终没有真正问出口的？",
                    category: "思考复盘")
        ]
    }
}
