#!/usr/bin/env bash
# error-tracking.sh — Extracted from orchestrate.sh
# Functions: record_error, update_task_progress, get_active_form_verb

# ═══════════════════════════════════════════════════════════════════════════════
# UX ENHANCEMENTS: Feature 1 - Enhanced Spinner Verbs (v7.16.0)
# Dynamic task progress updates with context-aware verbs
# ═══════════════════════════════════════════════════════════════════════════════

# Update Claude Code task progress with activeForm
update_task_progress() {
    local task_id="$1"
    local active_form="$2"

    # Skip if task progress disabled or missing parameters
    if [[ "$TASK_PROGRESS_ENABLED" != "true" ]]; then
        log DEBUG "Task progress disabled - skipping update"
        return 0
    fi

    if [[ -z "$task_id" || -z "$active_form" ]]; then
        log DEBUG "Missing task_id or active_form - skipping update"
        return 0
    fi

    if [[ -z "${CLAUDE_CODE_CONTROL_PIPE:-}" ]]; then
        log DEBUG "CLAUDE_CODE_CONTROL_PIPE not set - skipping update"
        return 0
    fi

    if [[ ! -p "$CLAUDE_CODE_CONTROL_PIPE" ]]; then
        log WARN "CLAUDE_CODE_CONTROL_PIPE is not a pipe: $CLAUDE_CODE_CONTROL_PIPE"
        return 1
    fi

    # Write to control pipe for Claude Code to update spinner
    echo "TASK_UPDATE:${task_id}:activeForm:${active_form}" >> "$CLAUDE_CODE_CONTROL_PIPE" 2>/dev/null || {
        log WARN "Failed to write to control pipe"
        return 1
    }

    log DEBUG "Updated task $task_id: $active_form"
    return 0
}

# Get context-aware activeForm verb for agent + phase combination
get_active_form_verb() {
    local phase="$1"
    local agent="$2"
    local prompt_context="${3:-}"  # Optional: for even more specific verbs

    # Normalize phase name (aliases to canonical names)
    case "$phase" in
        probe) phase="discover" ;;
        grasp) phase="define" ;;
        tangle) phase="develop" ;;
        ink) phase="deliver" ;;
    esac

    # Normalize agent name (remove version suffixes)
    local agent_base
    agent_base=$(echo "$agent" | sed 's/-[0-9].*$//' | sed 's/:.*//')

    # Generate phase/agent-specific verb with emoji indicators
    local verb=""
    case "$phase" in
        discover)
            case "$agent_base" in
                codex*) verb="🔴 Researching technical patterns (Codex)" ;;
                gemini*) verb="🟡 Exploring ecosystem and options (Gemini)" ;;
                claude*) verb="🔵 Synthesizing research findings" ;;
                *) verb="🔍 Researching and exploring" ;;
            esac
            ;;
        define)
            case "$agent_base" in
                codex*) verb="🔴 Analyzing technical requirements (Codex)" ;;
                gemini*) verb="🟡 Clarifying scope and constraints (Gemini)" ;;
                claude*) verb="🔵 Building consensus on approach" ;;
                *) verb="🎯 Defining requirements" ;;
            esac
            ;;
        develop)
            case "$agent_base" in
                codex*) verb="🔴 Generating implementation code (Codex)" ;;
                gemini*) verb="🟡 Exploring alternative approaches (Gemini)" ;;
                claude*) verb="🔵 Integrating and validating solution" ;;
                *) verb="🛠️  Developing implementation" ;;
            esac
            ;;
        deliver)
            case "$agent_base" in
                codex*) verb="🔴 Analyzing code quality (Codex)" ;;
                gemini*) verb="🟡 Testing edge cases and security (Gemini)" ;;
                claude*) verb="🔵 Final review and recommendations" ;;
                *) verb="✅ Validating and testing" ;;
            esac
            ;;
        *)
            verb="Processing with $agent"
            ;;
    esac

    echo "$verb"
}

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: ERROR LEARNING LOOP (Veritas-inspired)
# Structured error capture with similar-error detection and repeat flagging.
# ═══════════════════════════════════════════════════════════════════════════════

record_error() {
    local agent="$1"
    local task="$2"
    local error_msg="$3"
    local exit_code="${4:-1}"
    local attempt_desc="${5:-}"

    local error_dir="${WORKSPACE_DIR}/.octo/errors"
    local error_file="$error_dir/error-log.md"
    mkdir -p "$error_dir"

    # Cap at 100 entries: count existing, trim oldest if needed
    if [[ -f "$error_file" ]]; then
        local entry_count
        entry_count=$(grep -c "^### ERROR |" "$error_file" 2>/dev/null || echo "0")
        if [[ "$entry_count" -ge 100 ]]; then
            # Remove first entry (everything up to second ### ERROR)
            local second_entry_line
            second_entry_line=$(grep -n "^### ERROR |" "$error_file" | sed -n '2p' | cut -d: -f1)
            if [[ -n "$second_entry_line" ]]; then
                tail -n +"$second_entry_line" "$error_file" > "${error_file}.tmp" && mv "${error_file}.tmp" "$error_file"
            fi
        fi
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Sanitize error message (truncate, remove control chars)
    local safe_error="${error_msg:0:500}"
    safe_error=$(echo "$safe_error" | tr -d '\000-\011\013-\037')

    cat >> "$error_file" << ERREOF

### ERROR | $timestamp | agent: $agent | exit_code: $exit_code
**Task:** ${task:0:200}
**Error:** $safe_error
**Attempt:** ${attempt_desc:-Initial attempt}
**Root Cause:** Pending analysis
**Prevention:** Pending
---
ERREOF

    log DEBUG "Recorded error: agent=$agent, exit_code=$exit_code"
}
