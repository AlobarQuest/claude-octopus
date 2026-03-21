#!/usr/bin/env bash
# Tests for CC v2.1.77 feature detection sync
# Validates: 10 new SUPPORTS_* flags, v2.1.77 detection block, wiring, doctor checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH_MAIN="$PROJECT_ROOT/scripts/orchestrate.sh"
ORCH_LIB="$PROJECT_ROOT/scripts/lib/providers.sh"
# Combined search target (provider functions extracted to lib/ in v9.7.7)
ORCH=$(mktemp)
trap "rm -f "$ORCH"" EXIT
cat "$ORCH_LIB" "$ORCH_MAIN" > "$ORCH"
# Support grepping across orchestrate.sh + lib/*.sh
_ORCH_ALL_TMP=$(mktemp)
cat "$ORCH" "$PROJECT_ROOT/scripts/lib/"*.sh 2>/dev/null > "$_ORCH_ALL_TMP"
trap 'rm -f "$_ORCH_ALL_TMP"' EXIT

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── 1. Flag declarations exist ────────────────────────────────────────

echo "=== 1. Flag Declarations ==="

for flag in SUPPORTS_ALLOW_READ_SANDBOX SUPPORTS_COPY_INDEX \
            SUPPORTS_COMPOUND_BASH_PERMISSION_FIX SUPPORTS_RESUME_TRUNCATION_FIX \
            SUPPORTS_PRETOOLUSE_DENY_PRIORITY SUPPORTS_SENDMESSAGE_AUTO_RESUME \
            SUPPORTS_AGENT_NO_RESUME_PARAM SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER \
            SUPPORTS_BRANCH_COMMAND SUPPORTS_BG_BASH_5GB_KILL; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false in orchestrate.sh"
    fi
done

# ── 2. v2.1.77 detection block exists and sets all 10 flags ───────────

echo ""
echo "=== 2. Detection Block ==="

if grep -c 'version_compare.*2\.1\.77' "$ORCH" >/dev/null 2>&1; then
    pass "v2.1.77 detection block exists"
else
    fail "v2.1.77 detection block exists" "no version_compare for 2.1.77"
fi

v2177_block=$(grep -A20 'version_compare.*2\.1\.77' "$ORCH" | head -20)

for flag in SUPPORTS_ALLOW_READ_SANDBOX SUPPORTS_COPY_INDEX \
            SUPPORTS_COMPOUND_BASH_PERMISSION_FIX SUPPORTS_RESUME_TRUNCATION_FIX \
            SUPPORTS_PRETOOLUSE_DENY_PRIORITY SUPPORTS_SENDMESSAGE_AUTO_RESUME \
            SUPPORTS_AGENT_NO_RESUME_PARAM SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER \
            SUPPORTS_BRANCH_COMMAND SUPPORTS_BG_BASH_5GB_KILL; do
    if echo "$v2177_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.77 block sets: $flag"
    else
        fail "v2.1.77 block sets: $flag" "not found in v2.1.77 detection block"
    fi
done

# ── 3. Agent resume uses SendMessage ───────────────────────────────

echo ""
echo "=== 3. Agent Resume Migration ==="

# resume_agent() uses dispatch_method: "send_message" (not "resume")
if grep -c 'dispatch_method: "send_message"' "$ORCH" >/dev/null 2>&1; then
    pass "resume_agent uses dispatch_method send_message"
else
    fail "resume_agent dispatch_method" "expected send_message, not found"
fi

# Agent(resume:) NOT instructed in flow-develop.md
develop_skill="$PROJECT_ROOT/.claude/skills/flow-develop.md"
if [[ -f "$develop_skill" ]]; then
    old_resume_count="$(grep -c 'Agent.*resume=' "$develop_skill" 2>/dev/null)" || old_resume_count=0
    if [[ "$old_resume_count" -eq 0 ]]; then
        pass "flow-develop.md does NOT instruct Agent(resume=)"
    else
        fail "flow-develop.md still uses Agent(resume=)" "found $old_resume_count references"
    fi

    if grep -c 'SendMessage' "$develop_skill" >/dev/null 2>&1; then
        pass "flow-develop.md uses SendMessage for continuation"
    else
        fail "flow-develop.md SendMessage" "SendMessage not found in Step 3b"
    fi
fi

# ── 4. Doctor tips wired ───────────────────────────────────────────

echo ""
echo "=== 4. Doctor Tips ==="

for label in "plugin-validate" "allow-read-sandbox" "branch-command" "sendmessage-resume" "bg-bash-5gb"; do
    if grep -c "\"$label\"" "$ORCH" >/dev/null 2>&1; then
        pass "Doctor tip: $label"
    else
        fail "Doctor tip: $label" "not found in doctor checks"
    fi
done

# ── 5. Logging lines for new flags ───────────────────────────────

echo ""
echo "=== 5. Logging ==="

for label in "Allow Read Sandbox" "SendMessage Auto Resume" "Agent No Resume Param" \
             "Plugin Validate Frontmatter" "Branch Command" "BG Bash 5GB Kill"; do
    if grep -c "$label" "$ORCH" >/dev/null 2>&1; then
        pass "Logged: $label"
    else
        fail "Logged: $label" "not found in detection logging"
    fi
done

# ── 6. Resume command updated ────────────────────────────────────

echo ""
echo "=== 6. Resume Command ==="

resume_cmd="$PROJECT_ROOT/.claude/commands/resume.md"
if [[ -f "$resume_cmd" ]]; then
    if grep -c 'v2.1.77' "$resume_cmd" >/dev/null 2>&1; then
        pass "resume.md references v2.1.77"
    else
        fail "resume.md v2.1.77 note" "no v2.1.77 mention"
    fi

    if grep -c 'SendMessage' "$resume_cmd" >/dev/null 2>&1; then
        pass "resume.md mentions SendMessage"
    else
        fail "resume.md SendMessage" "no SendMessage reference"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS_COUNT/$TEST_COUNT passed, $FAIL_COUNT failed"
echo "═══════════════════════════════════════"

[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
