#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The native AI spell interaction regression requires macOS, AppKit, and a GUI session." >&2
  exit 1
fi

SPELL_INTERACTION_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/toolisle-ai-spell-interaction.XXXXXX")"
trap 'rm -rf "$SPELL_INTERACTION_DIRECTORY"' EXIT
SPELL_INTERACTION_ARGUMENTS=()
if [[ $# -gt 0 ]]; then
  mkdir -p "$1"
  SPELL_INTERACTION_ARTIFACT_DIRECTORY="$(cd "$1" && pwd)"
  SPELL_INTERACTION_ARGUMENTS=(--snapshot "$SPELL_INTERACTION_ARTIFACT_DIRECTORY/ai-spells-quick-panel.png")
fi

swiftc -target "$(uname -m)-apple-macosx14.6" \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellLibrary.swift \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellStore.swift \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellsView.swift \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellEditor.swift \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellQuickView.swift \
  tests/AISpellQuickViewRegression.swift \
  -framework AppKit -framework SwiftUI \
  -o "$SPELL_INTERACTION_DIRECTORY/ai-spell-interaction"

"$SPELL_INTERACTION_DIRECTORY/ai-spell-interaction" "${SPELL_INTERACTION_ARGUMENTS[@]}"
