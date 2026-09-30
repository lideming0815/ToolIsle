#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DERIVED_DATA:?Set DERIVED_DATA to the application's successful Debug build directory}"
PRODUCTS="$DERIVED_DATA/Build/Products/Debug"
D=DynamicIsland/ToolIsleFeatures/Gitee
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
# Use the exact Defaults module/object built for the application, not a stand-in implementation.
test -f "$PRODUCTS/Defaults.o"
swiftc -I "$PRODUCTS" -F "$PRODUCTS" \
  "$D/GICore.swift" "$D/GIListPresentation.swift" "$D/GLAPI.swift" "$D/GHAPI.swift" "$D/GIStore.swift" \
  tests/GitLabStoreRegression.swift "$PRODUCTS/Defaults.o" -o "$OUT/store-regression"
"$OUT/store-regression"
