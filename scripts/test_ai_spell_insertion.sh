#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift is required to run the AI spell insertion contract regressions." >&2
  exit 1
fi

SPELL_INSERTION_TEST_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/toolisle-ai-spell-insertion.XXXXXX")"
trap 'rm -rf -- "$SPELL_INSERTION_TEST_DIRECTORY"' EXIT
swiftc -module-cache-path "$SPELL_INSERTION_TEST_DIRECTORY/module-cache" \
  -strict-concurrency=complete -warnings-as-errors \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellInsertionCoordinator.swift \
  tests/AISpellInsertionRegression.swift \
  -o "$SPELL_INSERTION_TEST_DIRECTORY/insertion-regression"
"$SPELL_INSERTION_TEST_DIRECTORY/insertion-regression"
