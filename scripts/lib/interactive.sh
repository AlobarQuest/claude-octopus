#!/usr/bin/env bash
# interactive.sh — Interactive mode initialization, error display, CI mode, preflight recovery
#
# Functions: init_interactive, OLD_init_interactive_impl, show_error,
#            preflight_with_recovery, init_ci_mode, ci_output
# Data:      ERROR_CODES array, CI_MODE, AUDIT_LOG
#
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════
# v4.3 FEATURE: INTERACTIVE SETUP WIZARD (DEPRECATED in v4.9)
# Use 'detect-providers' command instead for Claude Code integration
# ═══════════════════════════════════════════════════════════════════════════════

init_interactive() {
    echo ""
    echo -e "${YELLOW}⚠ WARNING: 'init_interactive' is deprecated and will be removed in v5.0${NC}"
    echo ""
    echo -e "${CYAN}The interactive setup wizard has been deprecated in favor of a simpler flow.${NC}"
    echo ""
    echo -e "${CYAN}New approach:${NC}"
    echo -e "  1. Run: ${GREEN}./scripts/orchestrate.sh detect-providers${NC}"
    echo -e "     This will check your current setup and give you clear next steps."
    echo ""
    echo -e "  2. Or use: ${GREEN}/claude-octopus:setup${NC} in Claude Code"
    echo -e "     This provides full setup instructions within Claude Code."
    echo ""
    echo -e "${CYAN}Why the change?${NC}"
    echo -e "  • Faster onboarding - you only need ONE provider (Codex OR Gemini)"
    echo -e "  • Clearer instructions - no confusing interactive prompts"
    echo -e "  • Works in Claude Code - no need to leave and run terminal commands"
    echo -e "  • Environment variables for API keys (more secure)"
    echo ""
    echo -e "${CYAN}Quick migration:${NC}"
    echo -e "  Instead of this wizard, just set environment variables in your shell profile:"
    echo -e "    ${GREEN}export OPENAI_API_KEY=\"sk-...\"${NC}  (for Codex)"
    echo -e "    ${GREEN}export GEMINI_API_KEY=\"AIza...\"${NC}  (for Gemini)"
    echo ""
    echo -e "  Then run: ${GREEN}./scripts/orchestrate.sh detect-providers${NC}"
    echo ""
    exit 1
}

# Deprecated steps from old interactive wizard - keeping helper functions for octopus-configure
OLD_init_interactive_impl() {
    local step=1
    local total_steps=7
    local issues=0

    # ─────────────────────────────────────────────────────────────────────────
    # Step 1: OpenAI API Key
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "${YELLOW}Step $step/$total_steps: OpenAI API Key${NC}"
    echo -e "  Required for Codex CLI (GPT-5.x models)"
    echo ""

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        local masked_key="${OPENAI_API_KEY:0:7}...${OPENAI_API_KEY: -4}"
        echo -e "  ${GREEN}✓${NC} Found: $masked_key"

        # Validate the key format
        if [[ "$OPENAI_API_KEY" =~ ^sk-[a-zA-Z0-9]{20,}$ ]]; then
            echo -e "  ${GREEN}✓${NC} Format looks valid"
        else
            echo -e "  ${YELLOW}⚠${NC} Format may be incorrect (expected sk-...)"
        fi
    else
        echo -e "  ${RED}✗${NC} OPENAI_API_KEY not set"
        echo ""
        echo -e "  ${CYAN}To fix:${NC}"
        echo -e "    1. Get your API key from: ${CYAN}https://platform.openai.com/api-keys${NC}"
        echo -e "    2. Add to your shell profile (~/.zshrc or ~/.bashrc):"
        echo -e "       ${GREEN}export OPENAI_API_KEY=\"sk-...\"${NC}"
        echo -e "    3. Run: ${CYAN}source ~/.zshrc${NC} (or restart your terminal)"
        echo ""
        read -p "  Press Enter to continue (or Ctrl+C to exit and fix)..."
        ((issues++)) || true
    fi
    echo ""
    ((step++)) || true

    # ─────────────────────────────────────────────────────────────────────────
    # Step 2: Gemini Authentication
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "${YELLOW}Step $step/$total_steps: Gemini Authentication${NC}"
    echo -e "  Required for Gemini CLI (analysis, synthesis, images)"
    echo ""

    # Check OAuth first (preferred)
    if [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
        echo -e "  ${GREEN}✓${NC} Gemini: OAuth authenticated"
        local auth_type
        auth_type=$(grep -o '"selectedType"[[:space:]]*:[[:space:]]*"[^"]*"' ~/.gemini/settings.json 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || echo "oauth")
        echo -e "      Type: $auth_type"
        # macOS keychain prompt warning for OAuth users
        if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
            echo -e "  ${GREEN}✓${NC} macOS keychain bypass active (file-based token storage)"
        fi
    elif [[ -n "${GEMINI_API_KEY:-}" ]]; then
        local masked_gemini="${GEMINI_API_KEY:0:7}...${GEMINI_API_KEY: -4}"
        echo -e "  ${GREEN}✓${NC} Gemini: API Key found: $masked_gemini"

        if [[ "$GEMINI_API_KEY" =~ ^AIza[a-zA-Z0-9_-]{30,}$ ]]; then
            echo -e "  ${GREEN}✓${NC} Format looks valid"
        else
            echo -e "  ${YELLOW}⚠${NC} Format may be incorrect (expected AIza...)"
        fi
    else
        echo -e "  ${RED}✗${NC} Gemini: Not authenticated"
        echo ""
        echo -e "  ${CYAN}Option 1 (Recommended):${NC} OAuth Login"
        echo -e "    Run: ${GREEN}gemini${NC}"
        echo -e "    Select 'Login with Google' and follow browser prompts"
        echo ""
        echo -e "  ${CYAN}Option 2:${NC} API Key"
        echo -e "    1. Get your API key from: ${CYAN}https://aistudio.google.com/apikey${NC}"
        echo -e "    2. Add to your shell profile (~/.zshrc or ~/.bashrc):"
        echo -e "       ${GREEN}export GEMINI_API_KEY=\"AIza...\"${NC}"
        echo -e "    3. Run: ${CYAN}source ~/.zshrc${NC} (or restart your terminal)"
        echo ""
        read -p "  Press Enter to continue (or Ctrl+C to exit and fix)..."
        ((issues++)) || true
    fi
    echo ""
    ((step++)) || true

    # ─────────────────────────────────────────────────────────────────────────
    # Step 3: CLI Tools
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "${YELLOW}Step $step/$total_steps: CLI Tools${NC}"
    echo -e "  Checking for required command-line tools"
    echo ""

    # Check Codex CLI
    if command -v codex &> /dev/null; then
        local codex_version
        codex_version=$(codex --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Codex CLI: $codex_version"
    else
        echo -e "  ${RED}✗${NC} Codex CLI not found"
        echo -e "    Install: ${CYAN}npm install -g @openai/codex${NC}"
        ((issues++)) || true
    fi

    # Check Gemini CLI
    if command -v gemini &> /dev/null; then
        local gemini_version
        gemini_version=$(gemini --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Gemini CLI: $gemini_version"
    else
        echo -e "  ${RED}✗${NC} Gemini CLI not found"
        echo -e "    Install: ${CYAN}npm install -g @google/gemini-cli${NC}"
        ((issues++)) || true
    fi

    # Check jq (optional)
    if command -v jq &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} jq: $(jq --version 2>/dev/null)"
    else
        echo -e "  ${YELLOW}○${NC} jq not found (optional, for JSON task files)"
        echo -e "    Install: ${CYAN}brew install jq${NC}"
    fi
    echo ""
    ((step++)) || true

    # ─────────────────────────────────────────────────────────────────────────
    # Step 4: Workspace Configuration
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "${YELLOW}Step $step/$total_steps: Workspace Configuration${NC}"
    echo ""

    local current_workspace="${CLAUDE_OCTOPUS_WORKSPACE:-$HOME/.claude-octopus}"
    echo -e "  Current workspace: ${CYAN}$current_workspace${NC}"

    if [[ -d "$current_workspace" ]]; then
        echo -e "  ${GREEN}✓${NC} Workspace exists"
    else
        echo -e "  ${YELLOW}○${NC} Workspace will be created"
    fi

    echo ""
    read -p "  Use this location? [Y/n]: " use_default

    if [[ "$(_lowercase "$use_default")" == "n" ]]; then
        read -p "  Enter new workspace path: " new_workspace
        if [[ -n "$new_workspace" ]]; then
            echo ""
            echo -e "  ${YELLOW}To use custom workspace, add to your shell profile:${NC}"
            echo -e "    ${GREEN}export CLAUDE_OCTOPUS_WORKSPACE=\"$new_workspace\"${NC}"
            current_workspace="$new_workspace"
        fi
    fi

    # Create workspace
    mkdir -p "$current_workspace/results" "$current_workspace/logs"
    echo -e "  ${GREEN}✓${NC} Workspace ready"
    echo ""
    ((step++)) || true

    # ─────────────────────────────────────────────────────────────────────────
    # Step 5: Shell Completion
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "${YELLOW}Step $step/$total_steps: Shell Completion${NC}"
    echo -e "  Tab completion for commands, agents, and options"
    echo ""

    local shell_type
    shell_type=$(basename "$SHELL")
    echo -e "  Detected shell: ${CYAN}$shell_type${NC}"
    echo ""

    read -p "  Install shell completion? [Y/n]: " install_completion

    if [[ "$(_lowercase "$install_completion")" != "n" ]]; then
        local script_path
        script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/orchestrate.sh"

        case "$shell_type" in
            bash)
                local bashrc="$HOME/.bashrc"
                local completion_line="eval \"\$($script_path completion bash)\""
                if ! grep -q "orchestrate.sh completion" "$bashrc" 2>/dev/null; then
                    echo "" >> "$bashrc"
                    echo "# Claude Octopus shell completion" >> "$bashrc"
                    echo "$completion_line" >> "$bashrc"
                    echo -e "  ${GREEN}✓${NC} Added to ~/.bashrc"
                    echo -e "  Run: ${CYAN}source ~/.bashrc${NC} to activate"
                else
                    echo -e "  ${GREEN}✓${NC} Already configured in ~/.bashrc"
                fi
                ;;
            zsh)
                local zshrc="$HOME/.zshrc"
                local completion_line="eval \"\$($script_path completion zsh)\""
                if ! grep -q "orchestrate.sh completion" "$zshrc" 2>/dev/null; then
                    echo "" >> "$zshrc"
                    echo "# Claude Octopus shell completion" >> "$zshrc"
                    echo "$completion_line" >> "$zshrc"
                    echo -e "  ${GREEN}✓${NC} Added to ~/.zshrc"
                    echo -e "  Run: ${CYAN}source ~/.zshrc${NC} to activate"
                else
                    echo -e "  ${GREEN}✓${NC} Already configured in ~/.zshrc"
                fi
                ;;
            fish)
                local fish_comp="$HOME/.config/fish/completions/orchestrate.sh.fish"
                mkdir -p "$(dirname "$fish_comp")"
                "$script_path" completion fish > "$fish_comp"
                echo -e "  ${GREEN}✓${NC} Saved to $fish_comp"
                ;;
            *)
                echo -e "  ${YELLOW}○${NC} Unknown shell. Manual setup required."
                echo -e "    Run: ${CYAN}$script_path completion bash${NC} (or zsh/fish)"
                ;;
        esac
    else
        echo -e "  ${YELLOW}○${NC} Skipped. Run later with: ${CYAN}orchestrate.sh completion${NC}"
    fi
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # Step 6: Mode Selection (Dev Work vs Knowledge Work)
    # ─────────────────────────────────────────────────────────────────────────
    init_step_mode_selection
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # Step 7: User Intent (v4.5)
    # ─────────────────────────────────────────────────────────────────────────
    init_step_intent
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # Step 8: Resource Configuration (v4.5)
    # ─────────────────────────────────────────────────────────────────────────
    init_step_resources
    echo ""

    # Save user configuration
    save_user_config "$USER_INTENT_PRIMARY" "$USER_INTENT_ALL" "$USER_RESOURCE_TIER" "$INITIAL_KNOWLEDGE_MODE"

    # ─────────────────────────────────────────────────────────────────────────
    # Summary
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}  🐙 All 8 tentacles are connected and ready! 🐙${NC}"
        echo ""
        if [[ -n "$USER_INTENT_PRIMARY" && "$USER_INTENT_PRIMARY" != "general" ]]; then
            echo -e "  ${CYAN}Configured for: $USER_INTENT_PRIMARY development${NC}"
        fi
        if [[ -n "$USER_RESOURCE_TIER" && "$USER_RESOURCE_TIER" != "standard" ]]; then
            echo -e "  ${CYAN}Resource tier: $USER_RESOURCE_TIER${NC}"
        fi
        echo ""
        echo -e "  Try these commands:"
        echo -e "    ${CYAN}orchestrate.sh preflight${NC}     - Verify everything works"
        echo -e "    ${CYAN}orchestrate.sh auto <prompt>${NC} - Smart task routing"
        echo -e "    ${CYAN}orchestrate.sh config${NC}        - Update preferences"
    else
        echo -e "${YELLOW}  🐙 $issues tentacle(s) need attention 🐙${NC}"
        echo ""
        echo -e "  Fix the issues above, then run:"
        echo -e "    ${CYAN}orchestrate.sh preflight${NC}     - Verify fixes"
        echo -e "    ${CYAN}orchestrate.sh init --interactive${NC} - Re-run wizard"
    fi
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# v4.3 FEATURE: CONTEXTUAL ERROR CODES AND RECOVERY
# Provides actionable error messages with unique codes
# ═══════════════════════════════════════════════════════════════════════════════

# Error code registry (bash 3.2 compatible - uses regular array)
ERROR_CODES=(
    "E001:OPENAI_API_KEY not set:export OPENAI_API_KEY=\"sk-...\" && orchestrate.sh preflight:help api-setup"
    "E002:Gemini API key not set — set GEMINI_API_KEY or GOOGLE_API_KEY (if in ~/.bashrc, move to ~/.profile — bashrc is skipped in non-interactive shells):export GEMINI_API_KEY=\"AIza...\" && orchestrate.sh preflight:help api-setup"
    "E003:Codex CLI not found:npm install -g @openai/codex:help setup"
    "E004:Gemini CLI not found:npm install -g @google/gemini-cli:help setup"
    "E005:Workspace not initialized:orchestrate.sh init:help init"
    "E006:Agent spawn failed:Check API keys and network connection:help troubleshoot"
    "E007:Quality gate failed:Review output and retry with lower threshold (-q 60):help quality"
    "E008:Timeout exceeded:Increase timeout with -t 600 or break into smaller tasks:help timeout"
    "E009:Invalid agent type:Use: codex, codex-mini, gemini, gemini-fast:help agents"
    "E010:Task file parse error:Check JSON syntax with: jq . tasks.json:help tasks"
)

# Display contextual error with recovery steps
show_error() {
    local code="$1"
    local context="${2:-}"

    # Find error definition
    local error_def=""
    for entry in "${ERROR_CODES[@]}"; do
        if [[ "$entry" == "$code:"* ]]; then
            error_def="$entry"
            break
        fi
    done

    if [[ -z "$error_def" ]]; then
        # Unknown error code, show generic message
        echo -e "${RED}✗ Error: $context${NC}" >&2
        return 1
    fi

    # Parse error definition (code:message:fix:help)
    IFS=':' read -r err_code err_msg err_fix err_help <<< "$error_def"

    echo "" >&2
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${RED}║  ✗ Error $err_code                                              ║${NC}" >&2
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -e "  ${RED}$err_msg${NC}" >&2

    if [[ -n "$context" ]]; then
        echo -e "  ${YELLOW}Context: $context${NC}" >&2
    fi

    echo "" >&2
    echo -e "  ${GREEN}Fix this:${NC}" >&2
    echo -e "    $err_fix" >&2
    echo "" >&2
    echo -e "  ${CYAN}Learn more:${NC}" >&2
    echo -e "    orchestrate.sh $err_help" >&2
    echo "" >&2

    return 1
}

# Check for common issues and provide contextual help
preflight_with_recovery() {
    local has_errors=false

    # Check OpenAI API Key
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        show_error "E001"
        has_errors=true
    fi

    # Check Gemini API Key (v9.2.1: try resolving from profile/.env first, check OAuth)
    # Accept GEMINI_API_KEY, GOOGLE_API_KEY, or OAuth creds
    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        resolve_provider_env "GEMINI_API_KEY" 2>/dev/null
    fi
    if [[ -z "${GOOGLE_API_KEY:-}" ]]; then
        resolve_provider_env "GOOGLE_API_KEY" 2>/dev/null
    fi
    if [[ -z "${GEMINI_API_KEY:-}" ]] && [[ -z "${GOOGLE_API_KEY:-}" ]] && [[ ! -f "$HOME/.gemini/oauth_creds.json" ]]; then
        show_error "E002"
        has_errors=true
    fi

    # Check Codex CLI
    if ! command -v codex &> /dev/null; then
        show_error "E003"
        has_errors=true
    fi

    # Check Gemini CLI
    if ! command -v gemini &> /dev/null; then
        show_error "E004"
        has_errors=true
    fi

    # Check workspace
    if [[ ! -d "${WORKSPACE_DIR:-$HOME/.claude-octopus}" ]]; then
        show_error "E005"
        has_errors=true
    fi

    if $has_errors; then
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# v4.4 FEATURE: CI/CD MODE AND AUDIT TRAILS
# Non-interactive execution for GitHub Actions and audit logging
# ═══════════════════════════════════════════════════════════════════════════════

CI_MODE="${CI:-false}"
AUDIT_LOG="${WORKSPACE_DIR:-$HOME/.claude-octopus}/audit.log"

# Initialize CI mode from environment
init_ci_mode() {
    # Detect CI environment
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
        CI_MODE=true
        AUTONOMY_MODE="autonomous"  # No prompts in CI
        log INFO "CI environment detected - running in autonomous mode"
    fi
}

# Write structured JSON output for CI consumption
ci_output() {
    local status="$1"
    local phase="$2"
    local message="$3"
    local output_file="${4:-}"

    if [[ "$CI_MODE" == "true" ]]; then
        local json_output
        json_output=$(cat << EOF
{
  "status": "$status",
  "phase": "$phase",
  "message": "$message",
  "timestamp": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)",
  "output_file": "$output_file"
}
EOF
)
        echo "$json_output"

        # Also set GitHub Actions outputs if available
        if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
            echo "status=$status" >> "$GITHUB_OUTPUT"
            echo "phase=$phase" >> "$GITHUB_OUTPUT"
            [[ -n "$output_file" ]] && echo "output_file=$output_file" >> "$GITHUB_OUTPUT"
        fi
    fi
}
