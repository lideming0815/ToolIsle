#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
D=DynamicIsland/ToolIsleFeatures/Gitee
for test in GiteeReaderRegression GiteeRepositoryPathRegression; do
  swiftc "$D/GICore.swift" "tests/$test.swift" -o "$OUT/$test"
  "$OUT/$test"
done
swiftc "$D/GICore.swift" "$D/GIListPresentation.swift" "$D/GLAPI.swift" tests/GitLabReaderRegression.swift -o "$OUT/gitlab"
"$OUT/gitlab"
swiftc "$D/GICore.swift" "$D/GHAPI.swift" tests/GitHubReaderRegression.swift -o "$OUT/github"
"$OUT/github"
swiftc "$D/GICore.swift" "$D/GIListPresentation.swift" tests/GiteeLabelsRegression.swift -o "$OUT/labels"
"$OUT/labels"
swiftc "$D/GICore.swift" "$D/GIListPresentation.swift" "$D/GINotchMetrics.swift" tests/GitReaderProjectionRegression.swift -o "$OUT/projection"
"$OUT/projection"
swiftc "$D/GINotchMetrics.swift" tests/GiteeUXMetricsRegression.swift -o "$OUT/metrics"
"$OUT/metrics"
python3 -m unittest tests.test_gitee_settings tests.test_gitee_checkless tests.test_gitee_reader_lifecycle
