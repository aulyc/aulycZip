#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/generate-icon.sh --check
python3 -m py_compile scripts/release_tool.py
python3 -m unittest discover -s Tests -p 'test_*.py'
swift test
swift build -c release --arch arm64
