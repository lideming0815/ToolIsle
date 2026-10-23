// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main
struct AISpellLibraryRegression {
    private static var assertions = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    private static func expectThrows(_ message: String, _ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure(message)
        } catch {
            assertions += 1
        }
    }

    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolIsle-AISpellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("first/library.json")
        let library = try AISpellLibrary(fileURL: file)
        expect(library.spells.count == 4, "A new library contains the four editable user examples")
        let originalID = library.spells[0].id
        let content = "  请保留缩进。\n\n```swift\nlet value = 1\n```\n"
        let custom = AISpell(title: "架构复盘", content: content, category: "编程")
        try library.save(custom)

        let reopened = try AISpellLibrary(fileURL: file)
        expect(reopened.spells.count == 5, "Saving a spell survives reopening the library")
        expect(reopened.spells.first(where: { $0.id == custom.id })?.content == content,
               "Multiline prompt content round-trips byte for byte, including whitespace")
        expect(reopened.spells.contains(where: { $0.id == originalID }),
               "Existing sample identifiers survive restart")

        for spell in reopened.spells { try reopened.delete(id: spell.id) }
        let intentionallyEmpty = try AISpellLibrary(fileURL: file)
        expect(intentionallyEmpty.spells.isEmpty, "Deleting all spells does not reinstall the samples")

        let searchable = try AISpellLibrary(fileURL: directory.appendingPathComponent("search/library.json"),
                                            seedIfMissing: false)
        let architecture = AISpell(title: "  Café 架构  ",
                                   content: "Design Review\n" + String(repeating: "正文", count: 600) + "\n最大的遗漏是什么？",
                                   category: "  编程  ")
        let writing = AISpell(title: "写作", content: "检查报告中的表达", category: "写作")
        try searchable.save(architecture)
        try searchable.save(writing)
        expect(searchable.results(query: "CAFE design 编程").map(\.id) == [architecture.id],
               "Search is accent/case insensitive and all terms match across fields")
        expect(searchable.results(query: "遗漏").map(\.id) == [architecture.id],
               "Search includes complete multiline content beyond any preview")
        expect(searchable.results(query: "架构 报告").isEmpty, "Every search term must match the same spell")
        expect(searchable.results(category: "编程").map(\.id) == [architecture.id], "Categories filter exact normalized values")
        expect(Set(searchable.categories) == Set(["编程", "写作"]), "Category metadata is trimmed and available to filters")
        try searchable.toggleFavorite(id: architecture.id)
        expect(searchable.results().first?.id == architecture.id, "Favorites appear before ordinary prompts")
        expect(searchable.results(favoritesOnly: true).map(\.id) == [architecture.id], "Favorite filtering excludes other prompts")
        expect(searchable.results(category: "写作", favoritesOnly: true).isEmpty, "Category and favorite filters compose")
        let reopenedSearch = try AISpellLibrary(fileURL: searchable.fileURL)
        expect(reopenedSearch.results(favoritesOnly: true).map(\.id) == [architecture.id], "Favorite choice survives restart")

        let beforeInvalidEdit = searchable.spells
        expectThrows("A blank title must fail") {
            try searchable.save(AISpell(id: architecture.id, title: " \n ", content: "replacement"))
        }
        expectThrows("A whitespace-only body must fail") {
            try searchable.save(AISpell(title: "empty", content: " \n\t"))
        }
        expect(searchable.spells == beforeInvalidEdit, "Invalid edits leave all saved prompts intact")
        expectThrows("Deleting an unknown identifier must fail without modifying the library") {
            try searchable.delete(id: UUID())
        }

        let backupSource = try AISpellLibrary(fileURL: directory.appendingPathComponent("backup/library.json"),
                                             seedIfMissing: false)
        try backupSource.save(architecture)
        let fresh = AISpell(title: "新的咒语", content: "备份中独有的内容", category: "迁移")
        try backupSource.save(fresh)
        let backup = try backupSource.exportData()
        var localEdit = searchable.spells.first(where: { $0.id == architecture.id })!
        localEdit.content = "本地修改，导入旧备份时必须保留。"
        try searchable.save(localEdit)
        let importedCount = try searchable.importData(backup)
        expect(importedCount == 1, "Merge imports only identifiers absent from the local library")
        expect(searchable.spells.first(where: { $0.id == architecture.id })?.content == localEdit.content,
               "An old backup cannot replace newer local edits with the same identity")
        expect(searchable.spells.first(where: { $0.id == fresh.id })?.content == fresh.content,
               "A newly imported prompt is available verbatim")
        let repeatedCount = try searchable.importData(backup)
        expect(repeatedCount == 0, "Importing the same backup twice is idempotent")
        let afterImport = try AISpellLibrary(fileURL: searchable.fileURL)
        expect(afterImport.spells.count == 3, "Merged prompts persist after reopening")

        let snapshot = searchable.spells
        for invalidData in [Data("invalid JSON".utf8), Data(#"{"schemaVersion":99}"#.utf8)] {
            expectThrows("Invalid or future-version backups must fail") {
                _ = try searchable.importData(invalidData)
            }
            expect(searchable.spells == snapshot, "Failed imports must not partially modify the library")
        }
        var duplicateBackup = try JSONSerialization.jsonObject(with: backup) as! [String: Any]
        let exportedSpells = duplicateBackup["spells"] as! [[String: Any]]
        duplicateBackup["spells"] = [exportedSpells[0], exportedSpells[0], exportedSpells[1]]
        let duplicateData = try JSONSerialization.data(withJSONObject: duplicateBackup)
        expectThrows("Duplicate identifiers invalidate the entire import") {
            _ = try searchable.importData(duplicateData)
        }
        expect(searchable.spells == snapshot, "Invalid backups do not import even their otherwise valid records")

        for (name, bytes) in [("corrupt.json", Data("not a saved prompt document".utf8)),
                              ("future.json", Data(#"{"schemaVersion":99,"otherData":"preserve me"}"#.utf8))] {
            let invalidFile = directory.appendingPathComponent(name)
            try bytes.write(to: invalidFile)
            expectThrows("Existing invalid files must not be replaced with samples") {
                _ = try AISpellLibrary(fileURL: invalidFile)
            }
            let preserved = try Data(contentsOf: invalidFile)
            expect(preserved == bytes, "The original invalid or future-version file is preserved exactly")
        }

        let writeDirectory = directory.appendingPathComponent("write-failure", isDirectory: true)
        let writeFile = writeDirectory.appendingPathComponent("library.json")
        let protectedLibrary = try AISpellLibrary(fileURL: writeFile, seedIfMissing: false)
        let protected = AISpell(title: "不能丢失", content: "旧数据")
        try protectedLibrary.save(protected)
        let preservedDirectory = directory.appendingPathComponent("preserved", isDirectory: true)
        try FileManager.default.moveItem(at: writeDirectory, to: preservedDirectory)
        // A file where the parent directory belonged reliably produces a write failure,
        // even when this regression is run by an account that ignores chmod restrictions.
        try Data("block directory creation".utf8).write(to: writeDirectory)
        expectThrows("Failed disk writes must be reported") {
            try protectedLibrary.save(AISpell(id: protected.id, title: "new title", content: "new body"))
        }
        expect(protectedLibrary.spells.first?.content == "旧数据", "Write failure does not publish unsaved changes")
        try FileManager.default.removeItem(at: writeDirectory)
        try FileManager.default.moveItem(at: preservedDirectory, to: writeDirectory)
        let afterFailure = try AISpellLibrary(fileURL: writeFile)
        expect(afterFailure.spells.first?.title == "不能丢失", "The last successfully saved library remains readable")

        try verifyLegacyMigration(in: directory)
        try verifyClipboardCapture(in: directory)
        try verifyCombinationSnapshots(in: directory)

        #if os(macOS)
        // This compiles the actual observable Store on macOS without linking the whole
        // application. It never opens the user's Application Support file or defaults.
        let storeFile = directory.appendingPathComponent("store/library.json")
        _ = try AISpellLibrary(fileURL: storeFile, seedIfMissing: false)
        let store = AISpellStore(fileURL: storeFile)
        expect(!store.isReadOnly && store.spells.isEmpty, "The Store opens an intentionally empty library")
        expect(store.save(AISpell(title: "Store 内容", content: "已保存")), "The Store reports successful saves")
        expect(store.spells.count == 1, "The Store publishes saved results")
        let storeSnapshot = store.spells
        expect(store.importData(Data("not a backup".utf8)) == nil, "The Store reports an invalid import")
        expect(store.spells == storeSnapshot && store.errorMessage != nil,
               "Failed Store imports preserve the visible saved state and explain the error")
        expect(store.matchingContent("已保存")?.title == "Store 内容",
               "Capture duplicate hints work through the observable Store")
        let storeContext = AISpell(title: "Store 背景", content: "当前项目背景", kind: .context)
        expect(store.save(storeContext), "The Store saves a context card")
        let storeCombination = AISpell(title: "Store 组合", content: "", kind: .combination,
                                       components: [AISpellComponent(spell: storeContext),
                                                    AISpellComponent(spell: storeSnapshot[0])])
        expect(store.save(storeCombination), "The Store saves a combination through the same public interface")
        store.reload()
        expect(store.spells.first { $0.id == storeCombination.id }?.content == "当前项目背景\n\n已保存",
               "Store reload publishes the generated insertion text")

        let blockedFile = directory.appendingPathComponent("blocked-store.json")
        let originalBytes = Data("do not replace me".utf8)
        try originalBytes.write(to: blockedFile)
        let blockedStore = AISpellStore(fileURL: blockedFile)
        expect(blockedStore.isReadOnly && blockedStore.errorMessage != nil,
               "Load failure is read-only and visibly reported")
        expect(!blockedStore.save(AISpell(title: "不能覆盖", content: "不能覆盖")),
               "A failed load cannot create a fresh writable library over the original")
        let bytesAfterBlockedEdit = try Data(contentsOf: blockedFile)
        expect(bytesAfterBlockedEdit == originalBytes, "Read-only edits leave the original file untouched")
        let recoveryData = store.exportData()!
        try recoveryData.write(to: blockedFile)
        blockedStore.reload()
        expect(!blockedStore.isReadOnly && blockedStore.errorMessage == nil,
               "Reload can recover after the original file has been repaired")
        expect(blockedStore.spells.first?.content == "已保存", "Recovery publishes the repaired library")
        #endif

        print("PASS: \(assertions) AI spell library assertions")
    }

    private static func verifyLegacyMigration(in directory: URL) throws {
        let migrationDirectory = directory.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        let file = migrationDirectory.appendingPathComponent("library.json")
        // A literal document produced by the previous schema, without new optional fields.
        let original = Data(#"{"schemaVersion":1,"spells":[{"id":"C9AD3029-C360-41F9-9B80-A29E07F636BD","title":"既有咒语","content":"  旧正文\n保持换行。\n","category":"项目","isFavorite":true,"createdAt":1700000000000,"updatedAt":1700000001000}]}"#.utf8)
        try original.write(to: file)
        let library = try AISpellLibrary(fileURL: file)
        let afterOpening = try Data(contentsOf: file)
        expect(afterOpening == original, "Opening a legacy library must not rewrite it")
        let legacy = library.spells[0]
        expect(legacy.kind == .prompt && legacy.components.isEmpty, "Legacy records become ordinary prompts")
        expect(legacy.content == "  旧正文\n保持换行。\n", "Legacy body and whitespace stay unchanged")
        let context = AISpell(title: "项目背景", content: "Java 8\nSpring Boot", kind: .context)
        try library.save(context)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        expect(saved["schemaVersion"] as? Int == 2, "The first mutation writes the new document version")
        let backups = try FileManager.default.contentsOfDirectory(at: migrationDirectory, includingPropertiesForKeys: nil)
            .filter { $0 != file }
        expect(backups.count == 1, "The first legacy mutation creates one migration backup")
        let backupBytes = try Data(contentsOf: backups[0])
        expect(backupBytes == original, "The migration backup contains the exact old bytes")
        try library.toggleFavorite(id: context.id)
        let afterSecondSave = try FileManager.default.contentsOfDirectory(at: migrationDirectory, includingPropertiesForKeys: nil)
        expect(afterSecondSave.count == 2, "Ordinary later saves do not create more migration backups")
        let reopened = try AISpellLibrary(fileURL: file)
        expect(reopened.spells.first(where: { $0.id == legacy.id }) == legacy, "Migration preserves all existing record fields")
        expect(reopened.spells.first(where: { $0.id == context.id })?.kind == .context, "Context type survives reopening")

        let changedFile = migrationDirectory.appendingPathComponent("externally-edited.json")
        try original.write(to: changedFile)
        let staleLibrary = try AISpellLibrary(fileURL: changedFile)
        let externallyEdited = Data(#"{"schemaVersion":1,"spells":[]}"#.utf8)
        try externallyEdited.write(to: changedFile)
        expectThrows("Migration must not overwrite a newer document written by another app") {
            try staleLibrary.save(AISpell(title: "新咒语", content: "不能覆盖外部修改"))
        }
        let preservedExternalEdit = try Data(contentsOf: changedFile)
        expect(preservedExternalEdit == externallyEdited, "Migration detects an external edit and leaves those bytes intact")
    }

    private static func verifyClipboardCapture(in directory: URL) throws {
        let library = try AISpellLibrary(fileURL: directory.appendingPathComponent("capture/library.json"),
                                        seedIfMissing: false)
        let copied = "\n  标题第一行 🧩\n\n保留缩进和空行。\n"
        expect(AISpellLibrary.suggestedTitle(for: copied) == "标题第一行 🧩",
               "Capture suggests the first nonempty line without changing the body")
        expect(AISpellLibrary.suggestedTitle(for: " \n\t ") == "新咒语",
               "Blank capture uses a safe title suggestion")
        let longTitle = String(repeating: "👩🏽‍💻", count: 45)
        expect(AISpellLibrary.suggestedTitle(for: longTitle).count == 40,
               "Title suggestions limit characters without splitting a Unicode grapheme")
        let spell = AISpell(title: AISpellLibrary.suggestedTitle(for: copied), content: copied)
        try library.save(spell)
        expect(library.matchingContent(copied)?.id == spell.id, "Capture identifies an exact existing body")
        expect(library.matchingContent(copied.trimmingCharacters(in: .whitespacesAndNewlines)) == nil,
               "Duplicate matching does not silently trim or normalize prompt whitespace")
        expect(library.matchingContent("unrelated") == nil, "Different content remains a new capture")
        let reopened = try AISpellLibrary(fileURL: library.fileURL)
        expect(reopened.matchingContent(copied)?.content == copied, "Captured content persists verbatim")
    }

    private static func verifyCombinationSnapshots(in directory: URL) throws {
        let library = try AISpellLibrary(fileURL: directory.appendingPathComponent("combinations/library.json"),
                                        seedIfMissing: false)
        var context = AISpell(title: "热线项目", content: "背景：Java 8\n保持已确认口径。\n", kind: .context)
        let prompt = AISpell(title: "检查遗漏", content: "  请检查最大的遗漏。\n")
        try library.save(context)
        try library.save(prompt)
        var combination = AISpell(title: "热线技术评审", content: "此正文由片段生成",
                                  category: "技术评审", kind: .combination,
                                  components: [AISpellComponent(spell: context), AISpellComponent(spell: prompt)])
        try library.save(combination)
        combination = library.spells.first { $0.id == combination.id }!
        let expectedOriginal = "背景：Java 8\n保持已确认口径。\n\n\n  请检查最大的遗漏。\n"
        expect(combination.content == expectedOriginal,
               "Combination text preserves each body and adds exactly two newlines between snapshots")
        expect(library.results(query: "热线 遗漏").map(\.id) == [combination.id],
               "Search includes the final combined body and the saved combination title")

        context.content = "背景已更新：Java 17"
        try library.save(context)
        expect(library.spells.first { $0.id == combination.id }?.content == expectedOriginal,
               "Editing a context does not silently change a saved combination")
        try library.delete(id: context.id)
        let reopened = try AISpellLibrary(fileURL: library.fileURL)
        expect(reopened.spells.first { $0.id == combination.id }?.content == expectedOriginal,
               "Deleting a source leaves a saved combination usable after reopening")
        try reopened.toggleFavorite(id: combination.id)
        let favorite = reopened.spells.first { $0.id == combination.id }!
        expect(favorite.isFavorite && favorite.kind == .combination && favorite.components == combination.components,
               "Favoriting preserves combination type, ordered snapshots, and original source identities")

        combination = favorite
        combination.components[0] = AISpellComponent(spell: context)
        try reopened.save(combination)
        let expectedRefreshed = "背景已更新：Java 17\n\n  请检查最大的遗漏。\n"
        expect(reopened.spells.first { $0.id == combination.id }?.content == expectedRefreshed,
               "Explicitly replacing a source snapshot updates the final saved text")
        combination.components.reverse()
        try reopened.save(combination)
        let reordered = reopened.spells.first { $0.id == combination.id }!
        expect(reordered.content == "  请检查最大的遗漏。\n\n\n背景已更新：Java 17",
               "Changing component order changes insertion text in that order")

        let target = try AISpellLibrary(fileURL: directory.appendingPathComponent("combined-import/library.json"),
                                       seedIfMissing: false)
        var conflictingPrompt = prompt
        conflictingPrompt.content = "本机同 ID 的另一版正文"
        try target.save(conflictingPrompt)
        let imported = try target.importData(reopened.exportData())
        expect(imported == 1, "Import keeps existing identities and adds the saved combination")
        let importedCombination = target.spells.first { $0.id == reordered.id }!
        expect(importedCombination.id == reordered.id && importedCombination.kind == .combination &&
               importedCombination.title == reordered.title && importedCombination.category == reordered.category &&
               importedCombination.isFavorite == reordered.isFavorite && importedCombination.content == reordered.content &&
               importedCombination.components == reordered.components,
               "Import and export preserve the combination even when source IDs are absent or differ locally")
        expect(target.spells.first { $0.id == prompt.id }?.content == conflictingPrompt.content,
               "Combination import does not replace local source content")
        let reloadedTarget = try AISpellLibrary(fileURL: target.fileURL)
        let restoredCombination = reloadedTarget.spells.first { $0.id == reordered.id }!
        expect(restoredCombination.content == reordered.content && restoredCombination.components == reordered.components &&
               restoredCombination.kind == .combination && restoredCombination.isFavorite,
               "An imported combination remains identical after restarting")

        let beforeInvalid = target.spells
        let invalidCandidates = [
            AISpell(title: "没有片段", content: "不能作为组合", kind: .combination),
            AISpell(title: "重复片段", content: "", kind: .combination,
                    components: [AISpellComponent(spell: prompt), AISpellComponent(spell: prompt)]),
            AISpell(title: "空片段", content: "", kind: .combination,
                    components: [AISpellComponent(spell: AISpell(title: "空", content: " \n "))]),
            AISpell(id: prompt.id, title: "引用自己", content: "", kind: .combination,
                    components: [AISpellComponent(spell: prompt)]),
            AISpell(title: "普通咒语不能含片段", content: "原文", components: [AISpellComponent(spell: prompt)]),
            AISpell(title: "背景卡不能含片段", content: "背景", kind: .context,
                    components: [AISpellComponent(spell: prompt)])
        ]
        for invalid in invalidCandidates {
            expectThrows("An invalid snapshot combination must not be saved") { try target.save(invalid) }
        }
        expect(target.spells == beforeInvalid, "Rejected combinations leave all saved records unchanged")

        var malformed = try JSONSerialization.jsonObject(with: target.exportData()) as! [String: Any]
        var records = malformed["spells"] as! [[String: Any]]
        let combinationIndex = records.firstIndex { ($0["kind"] as? String) == "combination" }!
        records[combinationIndex]["content"] = "不匹配的正文不能悄悄丢弃"
        malformed["spells"] = records
        let malformedData = try JSONSerialization.data(withJSONObject: malformed)
        expectThrows("Inconsistent combination snapshots in a backup must be rejected") {
            _ = try target.importData(malformedData)
        }
        expect(target.spells == beforeInvalid, "An invalid combination backup cannot partially import data")
    }
}
