#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/generate-icon.sh --check
swift test
swift build -c release --arch arm64
