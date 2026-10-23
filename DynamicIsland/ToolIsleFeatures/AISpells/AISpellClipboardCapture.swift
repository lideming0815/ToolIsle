// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Capture reads an explicitly chosen text representation. It never copies the
/// item back to the pasteboard or uses an image/file's display name as a prompt.
enum AISpellClipboardCapture {
    static func text(from item: ClipboardItem) -> String? {
        switch item.type {
        case .text, .url, .rtf:
            return nonempty(item.stringData)
        case .image, .file, .unknown:
            return nil
        }
    }

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
        } else {
            text = nonempty(pasteboard.string(forType: .URL))
        }
        // Do not combine representations if another application changes the
        // pasteboard while a rich-text fallback is being decoded.
        return pasteboard.changeCount == changeCount ? text : nil
    }

    private static func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// Shared by the clipboard's different presentation modes. Rows keep their copy
/// gesture on the content area, outside this button, so capture cannot also copy.
@MainActor
struct AISpellClipboardCaptureButton: View {
    let item: ClipboardItem
    var beforeCapture: () -> Void = {}
    @Default(.enableAISpells) private var isEnabled

    var body: some View {
        if let content = AISpellClipboardCapture.text(from: item) {
            Button {
                beforeCapture()
                AISpellPanelController.shared.captureClipboardText(content)
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .disabled(!isEnabled)
            .help(isEnabled ? "存为 AI 咒语" : "请先在设置中启用 AI 咒语")
            .accessibilityLabel("存为 AI 咒语")
            .accessibilityIdentifier("clipboard-save-ai-spell-\(item.id.uuidString)")
        }
    }
}
