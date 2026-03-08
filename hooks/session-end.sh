#!/usr/bin/env bash
# Claude Octopus — SessionEnd Hook (v8.41.0)
# Fires when a Claude Code session ends. Finalizes metrics,
# cleans up session artifacts, and persists key preferences
# to auto-memory for cross-session continuity.
#
# Hook event: SessionEnd
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SESSION_FILE="${HOME}/.claude-octopus/session.json"
METRICS_DIR="${HOME}/.claude-octopus/metrics"
MEMORY_DIR="${HOME}/.claude/projects"

# --- 1. Finalize session metrics ---
if [[ -d "$METRICS_DIR" ]]; then
    SUMMARY="${METRICS_DIR}/session-summary-$(date +%Y%m%d-%H%M%S).json"
    if command -v jq &>/dev/null && [[ -f "$SESSION_FILE" ]]; then
        jq '{
            session_end: (now | tostring),
            phase: (.current_phase // .phase // "none"),
            workflow: (.workflow // "none"),
            completed_phases: (.completed_phases // []) | length,
            total_agent_calls: (.total_agent_calls // 0)
        }' "$SESSION_FILE" > "$SUMMARY" 2>/dev/null || true
    fi
fi

# --- 2. Persist preferences to auto-memory ---
# When native auto-memory is available, write key preferences so
# the next session starts with user context pre-loaded.
if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    AUTONOMY=$(jq -r '.autonomy // empty' "$SESSION_FILE" 2>/dev/null)
    PROVIDERS=$(jq -r '.providers // empty' "$SESSION_FILE" 2>/dev/null)

    # Find the correct project memory directory
    # Priority: CLAUDE_PROJECT_DIR (set by CC) > CWD-based lookup > fallback scan
    TARGET_MEM_DIR=""

    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        # CC sets this to the project-specific config dir (e.g., ~/.claude/projects/-Users-foo-myproject/)
        TARGET_MEM_DIR="${CLAUDE_PROJECT_DIR}/memory"
    else
        # Derive from CWD: CC encodes paths as -Users-foo-myproject
        CWD_ENCODED=$(pwd | tr '/' '-' | sed 's/^-//')
        for candidate in "$MEMORY_DIR"/*"${CWD_ENCODED}"*/memory "$MEMORY_DIR"/*; do
            if [[ -d "$candidate" ]]; then
                TARGET_MEM_DIR="$candidate"
                # If candidate ends in /memory, use it directly; otherwise append
                [[ "$candidate" != */memory ]] && TARGET_MEM_DIR="${candidate}/memory"
                break
            fi
        done
    fi

    if [[ -n "$TARGET_MEM_DIR" && -n "$AUTONOMY" && "$AUTONOMY" != "null" ]]; then
        mkdir -p "$TARGET_MEM_DIR"
        OCTOPUS_MEM="${TARGET_MEM_DIR}/octopus-preferences.md"
        {
            echo "# Octopus User Preferences"
            echo ""
            echo "- Preferred autonomy: ${AUTONOMY}"
            [[ -n "$PROVIDERS" && "$PROVIDERS" != "null" ]] && echo "- Provider config: ${PROVIDERS}"
            echo "- Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$OCTOPUS_MEM"
    fi
fi

# --- 3. Clean up session artifacts ---
# Remove transient files but keep session.json for resume capability
rm -f "${HOME}/.claude-octopus/.octo/pre-compact-snapshot.json" 2>/dev/null || true
rm -f "${HOME}/.claude-octopus/.reload-signal" 2>/dev/null || true

# Session manager cleanup: retain 10 most recent sessions
if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/session-manager.sh" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/session-manager.sh" cleanup 2>/dev/null || true
fi

exit 0
