#!/usr/bin/env bash
# Tests for the periodic GitHub work queue reminder hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"

test_suite "GitHub work queue hook"

HOOK="$PROJECT_ROOT/hooks/github-work-queue-watch.sh"
HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"

test_case "hook exists and is executable"
if [[ -x "$HOOK" ]]; then
    test_pass
else
    test_fail "github-work-queue-watch.sh missing or not executable"
fi

test_case "hook is registered on UserPromptSubmit"
if jq -e '(.hooks // .) | .UserPromptSubmit[]?.hooks[]? | select(.command | contains("github-work-queue-watch.sh"))' "$HOOKS_JSON" >/dev/null; then
    test_pass
else
    test_fail "github-work-queue-watch.sh not registered in UserPromptSubmit hooks"
fi

test_case "hook is silent unless explicitly enabled"
output=$(HOME="$TEST_TMP_DIR/github-work-queue-default-off" "$HOOK" <<<'{"prompt":"what should we work on"}')
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "default hook output: $output"
fi

mock_bin="$TEST_TMP_DIR/github-work-queue-bin"
mock_home="$TEST_TMP_DIR/github-work-queue-home"
mkdir -p "$mock_bin" "$mock_home"
cat > "$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "auth" ]]; then
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "#370 Native provider allowlist - https://github.com/nyldn/claude-octopus/issues/370"
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  echo "#370 Native provider allowlist - https://github.com/nyldn/claude-octopus/issues/370"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo "#372 symlink self-loop - https://github.com/nyldn/claude-octopus/pull/372"
  exit 0
fi
exit 1
SH
chmod +x "$mock_bin/gh"

# FORK-OWNED, and it is NOT superseded -- restored 2026-09-06 after the v11.0.1 sync merge
# reverted it and turned Unit Tests red on ubuntu and macOS.
#
# `hooks/github-work-queue-watch.sh` proceeds only when the target checkout's remote matches
# `nyldn/claude-octopus`; on any fork it emits {"decision":"continue"} and both assertions below
# fail. Upstream's own version runs the hook against `$PROJECT_ROOT`, which is correct FOR
# UPSTREAM and permanently red in a fork -- the fix is upstream-shaped rather than wrong, and it
# is the one hunk of the sync where the fork's side had to survive.
#
# Build a dedicated fixture carrying that remote and target it through the hook's `.cwd` stdin
# override (still honoured -- `github-work-queue-watch.sh` reads `.cwd // .workspace`), so the
# test exercises the hook's logic wherever it runs. Upstream's OCTOPUS_GITHUB_WORK_QUEUE=on
# gating is NEW and is kept: this restores the fixture, not the old test.
fixture_repo="$TEST_TMP_DIR/github-work-queue-repo"
mkdir -p "$fixture_repo"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" remote add origin https://github.com/nyldn/claude-octopus.git

test_case "hook emits open issues and PRs as additional context"
output=$(HOME="$mock_home" PATH="$mock_bin:$PATH" OCTOPUS_GITHUB_WORK_QUEUE=on OCTOPUS_GITHUB_WORK_QUEUE_FORCE=1 OCTOPUS_GITHUB_WORK_QUEUE_ISSUE=370 "$HOOK" <<JSON
{"prompt":"what should we work on","cwd":"$fixture_repo"}
JSON
)
if assert_contains "$output" "additionalContext" "hook returns context" &&
   assert_contains "$output" "#370 Native provider allowlist" "hook includes focus issue" &&
   assert_contains "$output" "Open PRs" "hook includes open PR section" &&
   assert_contains "$output" "only push/comment/merge after the user asks" "hook stays non-destructive"; then
    test_pass
fi

test_case "hook debounces repeated checks"
debounce_home="$TEST_TMP_DIR/github-work-queue-debounce-home"
mkdir -p "$debounce_home"
first=$(HOME="$debounce_home" PATH="$mock_bin:$PATH" OCTOPUS_GITHUB_WORK_QUEUE=on "$HOOK" <<JSON
{"prompt":"first","cwd":"$fixture_repo"}
JSON
)
second=$(HOME="$debounce_home" PATH="$mock_bin:$PATH" OCTOPUS_GITHUB_WORK_QUEUE=on "$HOOK" <<JSON
{"prompt":"second","cwd":"$fixture_repo"}
JSON
)
if assert_contains "$first" "Open upstream work exists" "first run surfaces queue" &&
   assert_not_contains "$second" "Open upstream work exists" "second run is debounced"; then
    test_pass
fi

test_summary
