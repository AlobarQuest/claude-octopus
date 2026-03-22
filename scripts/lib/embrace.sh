#!/usr/bin/env bash
# lib/embrace.sh — Embrace/probe workflow coordination
# Extracted from orchestrate.sh
# Functions: get_dispatch_strategy, load_blind_spot_checklist

get_dispatch_strategy() {
    local prompt="$1"
    local workflow="${2:-auto}"
    local strategy="${OCTOPUS_DISPATCH_STRATEGY:-smart}"

    case "$strategy" in
        full)
            local all_p="claude-sonnet"
            command -v codex >/dev/null 2>&1 && all_p="codex,${all_p}"
            command -v gemini >/dev/null 2>&1 && all_p="gemini,${all_p}"
            echo "3:${all_p}:high"
            return 0 ;;
        minimal)
            if command -v gemini >/dev/null 2>&1; then echo "2:gemini,claude-sonnet:high"
            elif command -v codex >/dev/null 2>&1; then echo "2:codex,claude-sonnet:high"
            else echo "1:claude-sonnet:high"; fi
            return 0 ;;
    esac

    # Auto-detect workflow from prompt if not specified
    if [[ "$workflow" == "auto" ]]; then
        local p_lower
        p_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
        local _re_sec='security|vulnerabilit|cve|owasp|injection|xss|csrf'
        local _re_rev='review|code.review|pull.request|bug.*find|audit|quality'
        local _re_arch='architect|system.design|trade.?off|debate|compare|vs([[:space:]]|$)|versus'
        if [[ "$p_lower" =~ $_re_sec ]]; then
            workflow="security"
        elif [[ "$p_lower" =~ $_re_rev ]]; then
            workflow="review"
        elif [[ "$p_lower" =~ $_re_arch ]]; then
            workflow="architecture"
        else
            workflow="research"
        fi
    fi

    local has_codex=false has_gemini=false has_copilot=false
    command -v codex >/dev/null 2>&1 && has_codex=true
    command -v gemini >/dev/null 2>&1 && has_gemini=true
    command -v copilot >/dev/null 2>&1 && has_copilot=true

    case "$workflow" in
        review|security)
            # Each provider misses different bugs — all 3 essential
            if [[ "$has_codex" == true && "$has_gemini" == true && "$has_copilot" == true ]]; then
                echo "4:codex,gemini,copilot,claude-sonnet:high"
            elif [[ "$has_codex" == true && "$has_gemini" == true ]]; then
                echo "3:codex,gemini,claude-sonnet:high"
            elif [[ "$has_codex" == true ]]; then echo "2:codex,claude-sonnet:high"
            elif [[ "$has_gemini" == true ]]; then echo "2:gemini,claude-sonnet:high"
            else echo "1:claude-sonnet:medium"; fi ;;
        architecture)
            # Codex + Gemini maximize training bias diversity
            if [[ "$has_codex" == true && "$has_gemini" == true ]]; then
                echo "2:codex,gemini:high"
            elif [[ "$has_codex" == true ]]; then echo "2:codex,claude-sonnet:medium"
            elif [[ "$has_gemini" == true ]]; then echo "2:gemini,claude-sonnet:medium"
            else echo "1:claude-sonnet:low"; fi ;;
        research|*)
            # Gemini solo 64% vs multi-LLM 65% — 2 providers sufficient
            if [[ "$has_gemini" == true && "$has_copilot" == true ]]; then echo "3:gemini,copilot,claude-sonnet:high"
            elif [[ "$has_gemini" == true ]]; then echo "2:gemini,claude-sonnet:high"
            elif [[ "$has_codex" == true ]]; then echo "2:codex,claude-sonnet:medium"
            else echo "1:claude-sonnet:medium"; fi ;;
    esac
}

load_blind_spot_checklist() {
    local prompt="$1"
    local blind_spots_dir="${SCRIPT_DIR}/../config/blind-spots"
    local manifest="${blind_spots_dir}/manifest.json"

    [[ ! -f "$manifest" ]] && return

    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # Find matching domain files via manifest trigger keywords
    local matched_files
    matched_files=$(jq -r --arg p "$prompt_lower" '
        .domains[] |
        select([.trigger_keywords[] as $kw | $p | test($kw; "i")] | any) |
        .file
    ' "$manifest" 2>/dev/null | sort -u)

    [[ -z "$matched_files" ]] && return

    # Collect relevant blind spot prompts from matched domains
    local checklist=""
    while IFS= read -r domain_file; do
        [[ -z "$domain_file" ]] && continue
        local file="${blind_spots_dir}/${domain_file}"
        [[ ! -f "$file" ]] && continue

        local spots
        spots=$(jq -r --arg p "$prompt_lower" '
            .blind_spots[] |
            select([.trigger_keywords[] as $kw | $p | test($kw; "i")] | any) |
            .injection_prompt
        ' "$file" 2>/dev/null)

        while IFS= read -r spot; do
            [[ -z "$spot" ]] && continue
            checklist="${checklist}
- ${spot}"
        done <<< "$spots"
    done <<< "$matched_files"

    [[ -z "$checklist" ]] && return
    echo "$checklist"
}
