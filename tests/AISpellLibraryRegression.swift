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
}
