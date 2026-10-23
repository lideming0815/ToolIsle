#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The native AI spell clipboard capture regression requires macOS and AppKit." >&2
  exit 1
fi

SPELL_CAPTURE_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/toolisle-ai-spell-capture.XXXXXX")"
trap 'rm -rf "$SPELL_CAPTURE_DIRECTORY"' EXIT

swiftc -target "$(uname -m)-apple-macosx14.6" \
  DynamicIsland/ToolIsleFeatures/AISpells/AISpellClipboardCapture.swift \
  tests/AISpellClipboardCaptureRegression.swift \
  -framework AppKit -framework UniformTypeIdentifiers \
  -o "$SPELL_CAPTURE_DIRECTORY/ai-spell-capture"

"$SPELL_CAPTURE_DIRECTORY/ai-spell-capture"
