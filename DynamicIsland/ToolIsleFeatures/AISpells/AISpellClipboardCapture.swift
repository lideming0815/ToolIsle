// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import UniformTypeIdentifiers

/// Capture reads an explicitly chosen text representation. It never copies the
/// item back to the pasteboard or uses an image/file's display name as a prompt.
enum AISpellClipboardCapture {
    /// HTML decoding uses AppKit's importer, like ClipboardManager's rich-text
    /// fallback. It can run WebKit internally and must remain on the main actor.
    @MainActor
    static func currentText(from pasteboard: NSPasteboard = .general) -> String? {
        let changeCount = pasteboard.changeCount
        let types = Set(pasteboard.types ?? [])
        let nonTextTypes: Set<NSPasteboard.PasteboardType> = [
            .fileURL, .png, .tiff,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        guard types.isDisjoint(with: nonTextTypes),
              !types.contains(where: { UTType($0.rawValue)?.conforms(to: .image) == true }) else { return nil }

        let text: String?
        if let plain = nonempty(pasteboard.string(forType: .string)) {
            text = plain
        } else if let rtf = pasteboard.data(forType: .rtf),
                  let richText = nonempty(NSAttributedString(rtf: rtf, documentAttributes: nil)?.string) {
            text = richText
        } else if let html = pasteboard.data(forType: .html),
                  let attributed = try? NSAttributedString(
                    data: html,
                    options: [.documentType: NSAttributedString.DocumentType.html,
                              .characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: nil),
                  let htmlText = nonempty(attributed.string) {
            text = htmlText
        } else {
            text = nonempty(pasteboard.string(forType: .URL))
        }
        // Do not combine representations if another application changes the
        // pasteboard while a rich-text fallback is being decoded.
        return pasteboard.changeCount == changeCount ? text : nil
    }

    static func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
