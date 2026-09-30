#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep the diagnostic outside ${parameter:?word}: an apostrophe in that word
# is parsed as shell syntax even inside the surrounding double quotes.
if [[ -z "${DERIVED_DATA:-}" ]]; then
  printf '%s\n' "Set DERIVED_DATA to the application's successful Debug build directory." >&2
  exit 2
fi
PRODUCTS="$DERIVED_DATA/Build/Products/Debug"
D=DynamicIsland/ToolIsleFeatures/Gitee
if [[ ! -f "$PRODUCTS/Defaults.o" ]]; then
  printf 'Missing built Defaults object: %s\n' "$PRODUCTS/Defaults.o" >&2
  exit 2
fi
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
# Use the exact Defaults module/object built for the application, not a stand-in implementation.
swiftc -I "$PRODUCTS" -F "$PRODUCTS" \
  "$D/GICore.swift" "$D/GIListPresentation.swift" "$D/GLAPI.swift" "$D/GHAPI.swift" "$D/GIStore.swift" \
  tests/GitLabStoreRegression.swift "$PRODUCTS/Defaults.o" -o "$OUT/store-regression"
"$OUT/store-regression"
