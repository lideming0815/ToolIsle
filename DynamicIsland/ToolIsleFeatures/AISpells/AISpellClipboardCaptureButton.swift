// ToolIsle AI spells. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Defaults
import SwiftUI

extension AISpellClipboardCapture {
    static func text(from item: ClipboardItem) -> String? {
        switch item.type {
        case .text, .url, .rtf:
            return nonempty(item.stringData)
        case .image, .file, .unknown:
            return nil
        }
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
