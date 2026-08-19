#!/bin/bash
set -euo pipefail

readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly benchmark_bytes="${AULYCZIP_BENCHMARK_BYTES:-209715200}"

cd "$project_root"
AULYCZIP_RUN_BENCHMARKS=1 \
  AULYCZIP_BENCHMARK_BYTES="$benchmark_bytes" \
  swift test -c release --filter ZipCoreBenchmarkTests
