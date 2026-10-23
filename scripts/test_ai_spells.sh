#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift is required to run the AI spell library regressions." >&2
  exit 1
fi

SPELL_TEST_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/toolisle-ai-spells.XXXXXX")"
trap 'rm -rf "$SPELL_TEST_DIRECTORY"' EXIT
SPELL_TEST_SOURCES=(DynamicIsland/ToolIsleFeatures/AISpells/AISpellLibrary.swift)
SPELL_TEST_FLAGS=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  SPELL_TEST_SOURCES+=(DynamicIsland/ToolIsleFeatures/AISpells/AISpellStore.swift)
  SPELL_TEST_FLAGS=(-target "$(uname -m)-apple-macosx14.6")
fi
swiftc "${SPELL_TEST_FLAGS[@]}" "${SPELL_TEST_SOURCES[@]}" tests/AISpellLibraryRegression.swift \
  -o "$SPELL_TEST_DIRECTORY/ai-spells-regression"
"$SPELL_TEST_DIRECTORY/ai-spells-regression"
