#!/usr/bin/env bash
# tests/helpers/grep-octopus.sh
# Grep helper for decomposed orchestrate.sh — searches across the main file + all lib/ modules.
# Use this instead of grepping orchestrate.sh directly so tests survive function extraction.
#
# Usage:
#   source tests/helpers/grep-octopus.sh
#   grep_octopus "function_name()"              # returns 0 if found, 1 if not
#   grep_octopus_content "function_name()" -A 5 # outputs matching lines with context

_GREP_OCTOPUS_PROJECT_ROOT="${_GREP_OCTOPUS_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Search across orchestrate.sh + all lib/*.sh for a pattern (like grep -q)
# Returns 0 if found, 1 if not found
grep_octopus() {
    local pattern="$1"
    shift
    cat "$_GREP_OCTOPUS_PROJECT_ROOT/scripts/orchestrate.sh" \
        "$_GREP_OCTOPUS_PROJECT_ROOT/scripts/lib/"*.sh 2>/dev/null \
        | grep -c "$pattern" "$@" >/dev/null 2>&1
}

# Search with output — returns matching lines (like grep with content)
# Usage: grep_octopus_content "pattern" [-A N] [-B N] etc.
grep_octopus_content() {
    local pattern="$1"
    shift
    cat "$_GREP_OCTOPUS_PROJECT_ROOT/scripts/orchestrate.sh" \
        "$_GREP_OCTOPUS_PROJECT_ROOT/scripts/lib/"*.sh 2>/dev/null \
        | grep "$@" "$pattern"
}
