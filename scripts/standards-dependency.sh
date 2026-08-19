#!/bin/bash

require_standards_root() {
    local configured_root="${STANDARDS_ROOT:-}"
    if [[ -z "$configured_root" ]]; then
        echo "error: STANDARDS_ROOT is required; point it to a checkout of https://github.com/aulyc/codex-engineering-standards" >&2
        return 64
    fi
    if [[ ! -d "$configured_root" ]]; then
        echo "error: STANDARDS_ROOT is not a directory: $configured_root" >&2
        return 66
    fi

    STANDARDS_ROOT="$(cd "$configured_root" && pwd)"
    local relative_path
    for relative_path in "$@"; do
        if [[ ! -f "$STANDARDS_ROOT/$relative_path" ]]; then
            echo "error: central standards dependency is missing $relative_path under $STANDARDS_ROOT" >&2
            return 66
        fi
    done
    export STANDARDS_ROOT
}
