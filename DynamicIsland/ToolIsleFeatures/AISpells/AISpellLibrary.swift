// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum AISpellKind: String, Codable, CaseIterable, Identifiable {
    case prompt
    case context
    case combination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prompt: return "咒语"
        case .context: return "背景卡"
        case .combination: return "组合"
        }
    }

    var systemImage: String {
        switch self {
        case .prompt: return "wand.and.stars"
        case .context: return "doc.text"
        case .combination: return "square.stack.3d.up"
        }
    }
}

/// A saved, ordered snapshot. The source identifier is only used for an explicit
/// refresh in the editor; insertion never resolves a source or changes the saved text.
struct AISpellComponent: Codable, Equatable, Identifiable {
    let sourceID: UUID
    var title: String
    var content: String

    var id: UUID { sourceID }

    init(spell: AISpell) {
        sourceID = spell.id
        title = spell.title
        content = spell.content
    }

    static func combinedContent(of components: [AISpellComponent]) -> String {
        components.map(\.content).joined(separator: "\n\n")
    }
}

/// A deliberately saved prompt. Its content is copied verbatim, including whitespace.
struct AISpell: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    var category: String
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
    var kind: AISpellKind
    var components: [AISpellComponent]

    init(id: UUID = UUID(), title: String, content: String, category: String = "",
         isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date? = nil,
         kind: AISpellKind = .prompt, components: [AISpellComponent] = []) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.kind = kind
        self.components = components
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, category, isFavorite, createdAt, updatedAt, kind, components
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        content = try values.decode(String.self, forKey: .content)
        category = try values.decode(String.self, forKey: .category)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        kind = try values.decodeIfPresent(AISpellKind.self, forKey: .kind) ?? .prompt
        components = try values.decodeIfPresent([AISpellComponent].self, forKey: .components) ?? []
    }
}

enum AISpellLibraryError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidTitle
    case emptyContent
    case duplicateIdentifiers
    case spellNotFound
    case invalidCombination
    case libraryChangedDuringMigration

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
        case .invalidCombination:
            return "组合需要至少一个非空片段，不能重复选择片段或引用自身。普通咒语和背景卡不能包含组合片段。"
        case .libraryChangedDuringMigration:
            return "咒语库文件已被其他程序修改。请重新读取后再保存，现有文件未被覆盖。"
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
    private var legacyData: Data?

    /// Samples are installed only for a genuinely absent file, including on the first
    /// launch. Unreadable, corrupt, unsupported, and intentionally empty files are distinct.
    init(fileURL: URL, seedIfMissing: Bool = true) throws {
        self.fileURL = fileURL
        self.spells = []
        do {
            let data = try Data(contentsOf: fileURL)
            self.spells = try Self.decode(data)
            if try JSONDecoder().decode(Version.self, from: data).schemaVersion == 1 {
                legacyData = data
            }
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            try persist(seedIfMissing ? Self.examples : [])
        }
    }

    var categories: [String] {
        Array(Set(spells.map(\.category).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A duplicate hint must never change the captured body or conflate differently
    /// formatted prompts. Search remains forgiving; capture matching is exact.
    func matchingContent(_ content: String) -> AISpell? {
        spells.first { $0.content.utf8.elementsEqual(content.utf8) }
    }

    static func suggestedTitle(for content: String) -> String {
        let firstLine = content.components(separatedBy: .newlines)
            .lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return firstLine.map { String($0.prefix(40)) } ?? "新咒语"
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
                                createdAt: old.createdAt, updatedAt: Date(),
                                kind: candidate.kind, components: candidate.components)
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
        if let legacyData {
            guard try Data(contentsOf: fileURL) == legacyData else {
                throw AISpellLibraryError.libraryChangedDuringMigration
            }
            let backupName = "\(fileURL.deletingPathExtension().lastPathComponent)-schema1-\(UUID().uuidString).json"
            let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
            // Preserve the entire original document before the first schema upgrade.
            // A failed backup aborts the write; an existing backup is never replaced.
            try legacyData.write(to: backupURL, options: .withoutOverwriting)
        }
        try data.write(to: fileURL, options: .atomic)
        spells = updated
        legacyData = nil
    }

    private static func encode(_ spells: [AISpell]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(Document(schemaVersion: 2, spells: spells))
    }

    private static func decode(_ data: Data) throws -> [AISpell] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let version = try decoder.decode(Version.self, from: data).schemaVersion
        guard version == 1 || version == 2 else { throw AISpellLibraryError.unsupportedVersion(version) }
        let document = try decoder.decode(Document.self, from: data)
        guard Set(document.spells.map(\.id)).count == document.spells.count else {
            throw AISpellLibraryError.duplicateIdentifiers
        }
        return try document.spells.map { spell in
            let cleaned = try validated(spell)
            // A saved document contains both the editable snapshots and its insertion
            // text. Reject disagreement rather than silently discarding either value.
            if spell.kind == .combination && !spell.content.utf8.elementsEqual(cleaned.content.utf8) {
                throw AISpellLibraryError.invalidCombination
            }
            return cleaned
        }
    }

    private static func validated(_ spell: AISpell) throws -> AISpell {
        var cleaned = spell
        cleaned.title = spell.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.category = spell.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else { throw AISpellLibraryError.invalidTitle }
        if cleaned.kind == .combination {
            guard !cleaned.components.isEmpty,
                  Set(cleaned.components.map(\.sourceID)).count == cleaned.components.count,
                  cleaned.components.allSatisfy({ component in
                      component.sourceID != cleaned.id &&
                      !component.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      !component.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }) else { throw AISpellLibraryError.invalidCombination }
            cleaned.content = AISpellComponent.combinedContent(of: cleaned.components)
        } else if !cleaned.components.isEmpty {
            throw AISpellLibraryError.invalidCombination
        }
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
