// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Exercises the production reader against a private named pasteboard. This
/// regression never reads, clears, or writes the system's general pasteboard.
@main
@MainActor
struct AISpellClipboardCaptureRegression {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static var assertions = 0

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        guard try condition() else { throw Failure(description: message) }
    }

    static func main() {
        do {
            try run()
            print("PASS: \(assertions) native AI spell clipboard capture assertions; private named pasteboard only")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        // The HTML importer can use WebKit; initialize AppKit on the main thread
        // without showing a window or activating another application.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ToolIsle-AISpellCaptureTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let original = "  第一行：发现遗漏 🪄\n\n  Second line\t\n"
        try load([(.string, Data(original.utf8))], into: pasteboard)
        try expect(try readUnchanged(pasteboard) == original,
                   "Plain text keeps its exact leading spaces, blank lines, tabs, and trailing newline")

        try load([(.string, Data(" \t\r\n ".utf8))], into: pasteboard)
        try expect(try readUnchanged(pasteboard) == nil, "Whitespace-only text is not a spell")

        let url = "https://github.com/lideming0815/ToolIsle?tab=readme-ov-file#ai-spells"
        try load([(.URL, Data(url.utf8))], into: pasteboard)
        try expect(try readUnchanged(pasteboard) == url, "A URL-only representation is captured as text")

        let richBody = "  富文本正文\n保留完整内容。  "
        let rich = NSAttributedString(string: richBody)
        let rtf = try rich.data(from: NSRange(location: 0, length: rich.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try load([(.rtf, rtf)], into: pasteboard)
        try expect(try readUnchanged(pasteboard) == richBody, "RTF-only content is captured as complete plain text")

        let html = """
        <!doctype html><html><head><meta charset="utf-8"></head><body><b>背景：政府热线</b> &amp; AI<br><i>减少未知因素。</i></body></html>
        """
        try load([(.html, Data(html.utf8))], into: pasteboard)
        let htmlText = try readUnchanged(pasteboard)
        let htmlLines = htmlText?.components(separatedBy: .newlines).filter { !$0.isEmpty }
        try expect(htmlLines == ["背景：政府热线 & AI", "减少未知因素。"],
                   "HTML-only rich text decodes UTF-8 and entities, drops markup, and preserves the line break")

        // A plain representation is authoritative even when rich representations
        // contain a different styled body.
        try load([(.string, Data(original.utf8)), (.rtf, rtf), (.html, Data(html.utf8))], into: pasteboard)
        try expect(try readUnchanged(pasteboard) == original,
                   "Plain text has priority and is never replaced by a rich-text alternative")

        let fileURL = URL(fileURLWithPath: "/tmp/not-a-prompt.txt")
        pasteboard.declareTypes([.fileURL, .string], owner: nil)
        try expect(pasteboard.setString(fileURL.absoluteString, forType: .fileURL),
                   "Create a valid file URL representation on the named pasteboard")
        try expect(pasteboard.setString(fileURL.path, forType: .string),
                   "Give the named file URL fixture its accompanying path text")
        try expect(pasteboard.string(forType: .fileURL) == fileURL.absoluteString,
                   "The modern file URL fixture round-trips its URL string")
        try expect(try readUnchanged(pasteboard) == nil,
                   "A file URL representation must not capture its accompanying path")

        // The legacy filename list is a property list, not UTF-8 URL bytes.
        // NSPasteboardItem accepts UTI types and rejects this old named type;
        // use the legacy NSPasteboard declaration API that owns its encoding.
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pasteboard.declareTypes([filenamesType, .string], owner: nil)
        try expect(pasteboard.setPropertyList([fileURL.path], forType: filenamesType),
                   "Create a valid legacy filename property list on the named pasteboard")
        try expect(pasteboard.setString(fileURL.path, forType: .string),
                   "Give the legacy filename fixture its accompanying path text")
        try expect(pasteboard.types?.contains(filenamesType) == true,
                   "The legacy filename fixture declares the old type explicitly")
        try expect((pasteboard.propertyList(forType: filenamesType) as? [String]) == [fileURL.path],
                   "The legacy filename fixture round-trips its filename property list")
        try expect(try readUnchanged(pasteboard) == nil,
                   "A legacy filename representation must not capture its accompanying path")

        let imageRepresentations: [NSPasteboard.PasteboardType] = [
            .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif")
        ]
        for type in imageRepresentations {
            try load([(type, Data([0x01, 0x02, 0x03])),
                      (.string, Data("Image description is not a prompt".utf8))], into: pasteboard)
            try expect(try readUnchanged(pasteboard) == nil,
                       "An image representation must not capture its description: \(type.rawValue)")
        }

        pasteboard.clearContents()
        try expect(try readUnchanged(pasteboard) == nil, "An empty pasteboard has no capturable text")
    }

    private static func load(_ representations: [(NSPasteboard.PasteboardType, Data)],
                             into pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in representations {
            try expect(item.setData(data, forType: type), "Create named pasteboard fixture for \(type.rawValue)")
        }
        try expect(pasteboard.writeObjects([item]), "Write only the named pasteboard fixture")
    }

    /// No copy-back or cleanup is permitted in the production read path. Check
    /// every representation as well as the native mutation counter after reading.
    private static func readUnchanged(_ pasteboard: NSPasteboard) throws -> String? {
        let changeCount = pasteboard.changeCount
        let types = pasteboard.types ?? []
        let data = types.map { pasteboard.data(forType: $0) }
        let text = AISpellClipboardCapture.currentText(from: pasteboard)
        try expect(pasteboard.changeCount == changeCount, "Capture must not mutate pasteboard ownership or contents")
        try expect((pasteboard.types ?? []) == types, "Capture must preserve pasteboard representation types")
        try expect(types.map { pasteboard.data(forType: $0) } == data, "Capture must preserve all original data")
        return text
    }
}
