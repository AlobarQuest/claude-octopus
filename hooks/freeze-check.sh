#!/bin/bash
# Claude Octopus Freeze Mode Hook (v9.8.0)
# PreToolUse hook on Edit/Write that blocks file operations outside a frozen boundary.
# Activated by /octo:freeze command (writes directory to state file).
# Read, Bash, Glob, Grep are unaffected — investigation stays unrestricted.
# Returns JSON decision: {"decision":"allow"} or {"permissionDecision":"deny","message":"..."}
#
# Kill switch: OCTO_FREEZE_MODE=off — disables freeze boundary enforcement
set -euo pipefail

# Kill switch
[[ "${OCTO_FREEZE_MODE:-on}" == "off" ]] && { echo '{"decision":"allow"}'; exit 0; }

# Respect bypassPermissions mode — hooks must not override the user's CLI permission setting
for _sf in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "$HOME/.claude/settings.json"; do
    [[ -f "$_sf" ]] && grep -q '"bypassPermissions"' "$_sf" 2>/dev/null && { echo '{"decision":"allow"}'; exit 0; }
done

# Read tool input from stdin
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && INPUT='{}'

# Only gate Edit and Write tools
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# Check if freeze mode is active
STATE_FILE="/tmp/octopus-freeze-${CLAUDE_SESSION_ID:-$$}.txt"
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# Read freeze boundary
FREEZE_DIR=$(<"$STATE_FILE")
if [[ -z "$FREEZE_DIR" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# Extract file_path from input
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -z "$FILE_PATH" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# Resolve to absolute path if relative
if [[ "$FILE_PATH" != /* ]]; then
    FILE_PATH="$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && echo "$(pwd)/$(basename "$FILE_PATH")" || echo "$FILE_PATH")"
fi

# Ensure freeze_dir has trailing / to prevent prefix collisions (/src matching /src-old)
[[ "$FREEZE_DIR" != */ ]] && FREEZE_DIR="${FREEZE_DIR}/"

# Check if file is within the freeze boundary
if [[ "$FILE_PATH" == "${FREEZE_DIR}"* || "$FILE_PATH" == "${FREEZE_DIR%/}" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# File is outside boundary — block
echo "{\"permissionDecision\":\"deny\",\"message\":\"🔒 Edit blocked: ${FILE_PATH} is outside freeze boundary (${FREEZE_DIR%/}). Use /octo:unfreeze to remove restriction.\"}"
exit 0
