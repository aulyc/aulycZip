#!/bin/bash
set -euo pipefail

readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly benchmark_bytes="${AULYCZIP_BENCHMARK_BYTES:-209715200}"

cd "$project_root"
/usr/bin/time -l /usr/bin/env \
  AULYCZIP_RUN_BENCHMARKS=1 \
  AULYCZIP_BENCHMARK_BYTES="$benchmark_bytes" \
  swift test --filter ZipCoreBenchmarkTests
