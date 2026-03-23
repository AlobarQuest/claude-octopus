#!/usr/bin/env bash
# Tests for guard_output() function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SECURE="$PROJECT_ROOT/scripts/lib/secure.sh"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── guard_output function exists ────────────────────────────────────

if grep -q '^guard_output()' "$SECURE" 2>/dev/null; then
    pass "guard_output() defined in secure.sh"
else
    fail "guard_output() defined in secure.sh" "function not found"
fi

# ── guard_output has max_bytes threshold ────────────────────────────

if grep -A5 'guard_output()' "$SECURE" | grep -q 'max_bytes' 2>/dev/null; then
    pass "guard_output has max_bytes threshold"
else
    fail "guard_output has max_bytes threshold" "missing max_bytes"
fi

# ── guard_output uses secure_tempfile ───────────────────────────────

if grep -A15 'guard_output()' "$SECURE" | grep -q 'secure_tempfile' 2>/dev/null; then
    pass "guard_output uses secure_tempfile for overflow"
else
    fail "guard_output uses secure_tempfile for overflow" "missing secure_tempfile call"
fi

# ── guard_output has @file: pointer pattern ─────────────────────────

if grep -A15 'guard_output()' "$SECURE" | grep -q '@file:' 2>/dev/null; then
    pass "guard_output emits @file: pointer for oversize content"
else
    fail "guard_output emits @file: pointer for oversize content" "missing @file: pattern"
fi

# ── guard_output wired into aggregate_results ───────────────────────

if grep -c 'guard_output' <(grep -A200 'aggregate_results()' "$ALL_SRC" | head -200) >/dev/null 2>&1; then
    pass "guard_output wired into aggregate_results()"
else
    fail "guard_output wired into aggregate_results()" "not found in function body"
fi

# ── guard_output wired into synthesize_probe_results ────────────────

if grep -c 'guard_output' <(grep -A150 'synthesize_probe_results()' "$ALL_SRC" | head -200) >/dev/null 2>&1; then
    pass "guard_output wired into synthesize_probe_results()"
else
    fail "guard_output wired into synthesize_probe_results()" "not found in function body"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "output-guard: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
