#!/usr/bin/env python3
"""
Applies deterministic security hardening patches to the upstream-sync branch.
Runs after the AI security review. Commits changes back to upstream-sync.

Exit codes: 0 = success (changed or no-op), 1 = fatal error
"""

import glob, os, re, subprocess, sys, textwrap

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

API_KEY_VARS = [
    'ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'GEMINI_API_KEY',
    'PERPLEXITY_API_KEY', 'OPENROUTER_API_KEY', 'QWEN_API_KEY',
    'COPILOT_GITHUB_TOKEN',
]

SHELL_GLOBS = [
    'hooks/*.sh', 'hooks/*.bash',
    '.claude-plugin/hooks/*.sh', '.claude-plugin/hooks/*.bash',
    '.claude/hooks/*.sh', '.claude/hooks/*.bash',
    'bin/*.sh', 'bin/*.bash',
    'scripts/*.sh', 'scripts/*.bash',
]

SETX_GUARD = '{ set +x; } 2>/dev/null  # harden: suppress key in bash traces'

changed_files = []
skipped = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def shell_files():
    seen = set()
    result = []
    for pattern in SHELL_GLOBS:
        for path in sorted(glob.glob(pattern)):
            if path not in seen:
                seen.add(path)
                result.append(path)
    return result


def read(path):
    return open(path).read()


def save(path, content):
    open(path, 'w').write(content)
    if path not in changed_files:
        changed_files.append(path)


# ---------------------------------------------------------------------------
# Fix 1: { set +x; } guards before API key assignments
# ---------------------------------------------------------------------------

def fix1_setx_guards():
    patched = []
    for path in shell_files():
        try:
            lines = read(path).split('\n')
        except Exception:
            continue

        new_lines = []
        file_changed = False

        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith('#'):
                new_lines.append(line)
                continue

            is_key_line = any(
                re.match(r'^\s*(export\s+)?' + re.escape(v) + r'\s*[=+?:]', line)
                for v in API_KEY_VARS
            )

            if is_key_line:
                prev = new_lines[-1].strip() if new_lines else ''
                if 'set +x' not in prev:
                    indent = ' ' * (len(line) - len(line.lstrip()))
                    new_lines.append(indent + SETX_GUARD)
                    file_changed = True

            new_lines.append(line)

        if file_changed:
            save(path, '\n'.join(new_lines))
            patched.append(path)

    return patched


# ---------------------------------------------------------------------------
# Fix 2: Require https-only for webhook URLs (remove localhost allowances)
# ---------------------------------------------------------------------------

# Matches one or two trailing && conditions that allow http://localhost or http://127.x
_LOCALHOST_COND = re.compile(
    r'\s*&&\s*"\$\{?(?:OCTOPUS_)?WEBHOOK_URL\}?"\s+!=\s+["\']?http://localhost[^\s\]]*["\']?',
    re.IGNORECASE,
)
_127_COND = re.compile(
    r'\s*&&\s*"\$\{?(?:OCTOPUS_)?WEBHOOK_URL\}?"\s+!=\s+["\']?http://127\.0\.0\.1[^\s\]]*["\']?',
    re.IGNORECASE,
)
# Locates the if-line that starts the webhook validation block.
# Anchored at line start with a captured indent (group 1) so the annotation can be
# placed on its own line above the `if` — appending it inline would land the comment
# inside the `[[ ]]`, where `#` is not a comment and breaks the conditional.
_WEBHOOK_GUARD_LINE = re.compile(
    r'^([ \t]*)(if\s+\[\[\s+"\$\{?(?:OCTOPUS_)?WEBHOOK_URL\}?"\s+!=\s+https://\*)',
    re.IGNORECASE | re.MULTILINE,
)

# Once the localhost code conditions are removed, an upstream comment like
# "... (localhost exempted for dev)" is false — the hardened guard rejects
# localhost too. Strip that stale localhost parenthetical from comment lines so
# the hardened output is self-consistent AND deterministic: otherwise the comment
# keeps diverging from fork main and re-conflicts on every sync merge.
_COMMENT_LOCALHOST_PAREN = re.compile(
    r'[ \t]*\([^)]*(?:localhost|127\.0\.0\.1)[^)]*\)', re.IGNORECASE
)


def _strip_stale_localhost_comments(text):
    out = []
    for line in text.split('\n'):
        stripped = line.lstrip()
        # Only rewrite comment lines, and never our own "# harden:" annotation
        # (it legitimately says "(localhost removed …)").
        if stripped.startswith('#') and not stripped.startswith('# harden:'):
            line = _COMMENT_LOCALHOST_PAREN.sub('', line)
        out.append(line)
    return '\n'.join(out)


def fix2_webhook_https_only():
    patched = []
    for path in shell_files():
        try:
            content = read(path)
        except Exception:
            continue

        if 'WEBHOOK_URL' not in content:
            continue
        if 'localhost' not in content and '127.0.0.1' not in content:
            continue

        new_content = content
        did_change = False

        if _LOCALHOST_COND.search(new_content):
            new_content = _LOCALHOST_COND.sub('', new_content)
            did_change = True
        if _127_COND.search(new_content):
            new_content = _127_COND.sub('', new_content)
            did_change = True

        if did_change:
            # Drop the now-false localhost parenthetical from the descriptive
            # comment BEFORE adding our annotation (so the annotation's own
            # "(localhost removed …)" is never touched).
            new_content = _strip_stale_localhost_comments(new_content)
            # Annotate the surviving guard on its own line above the `if` so intent
            # is clear without injecting a comment into the `[[ ]]` conditional.
            def annotate_guard(m):
                indent = m.group(1)
                return (indent + '# harden: https-only (localhost removed — SSRF risk in containers)\n'
                        + indent + m.group(2))
            new_content = _WEBHOOK_GUARD_LINE.sub(annotate_guard, new_content, count=1)
            save(path, new_content)
            patched.append(path)
        elif _WEBHOOK_GUARD_LINE.search(content):
            # Has the guard but no localhost to remove — already tight or different pattern
            pass
        else:
            skipped.append((
                path,
                'webhook: WEBHOOK_URL present but validation pattern not recognized — verify manually',
            ))

    return patched


# ---------------------------------------------------------------------------
# Fix 3: flock on session.json writes
# ---------------------------------------------------------------------------

# Matches simple single-line writes:  cmd > "$SESSION_FILE"  or  cmd > "...session.json"
# The (?:\.[A-Za-z0-9_]+)* tail captures any extension on the redirect target (e.g.
# "${SESSION_FILE}.tmp") as part of group 4. Without it the match stopped at the
# closing brace, orphaning the `.tmp"` fragment and producing unbalanced quotes
# (`9>"${SESSION_FILE}.lock".tmp"`). NOTE: the write target may thus be a staging
# path; the lock name is derived separately (trailing .tmp stripped) so all writers
# of one session file share a single lock — see fix3_session_locking.
_SESSION_WRITE = re.compile(
    r'^(\s*)((?:(?:echo|printf)\s+[^|>\n]+|jq\s+[^|>\n]+))\s*(>>?)\s*'
    r'("?\$\{?[A-Za-z_]*(?:SESSION|session)[A-Za-z_]*(?:FILE|PATH|JSON)?\}?(?:\.[A-Za-z0-9_]+)*"?'
    r'|"[^"]*session\.json")',
    re.MULTILINE,
)

_FLOCK_ALREADY = re.compile(r'\bflock\b')


def fix3_session_locking():
    patched = []
    needs_manual = []

    for path in shell_files():
        try:
            content = read(path)
        except Exception:
            continue

        has_session_write = bool(re.search(
            r'session[._]?(json|file|path)', content, re.IGNORECASE
        )) and ('>' in content)

        if not has_session_write:
            continue
        if _FLOCK_ALREADY.search(content):
            continue  # already locked

        matches = list(_SESSION_WRITE.finditer(content))
        if not matches:
            needs_manual.append(path)
            continue

        new_content = content
        did_patch = False
        for m in reversed(matches):  # reverse so offsets stay valid
            indent = m.group(1)
            cmd = m.group(2).strip()
            redir = m.group(3)
            target = m.group(4).strip('"')

            # The lock must key off the *canonical* session file, not the write
            # target. Atomic-write hooks stage to "$SESSION_FILE.tmp" before mv'ing
            # into place; keying the lock on the staging path (".tmp.lock") gives
            # each such hook a different lock from hooks that write the session file
            # directly ("$SESSION_FILE.lock"), so flock stops serializing them at all.
            # Strip a trailing .tmp so every writer of a given session file shares one lock.
            lock_base = re.sub(r'\.tmp$', '', target)

            replacement = (
                indent + '# harden: atomic write — prevents concurrent session corruption\n'
                + indent + '(flock -x 9; ' + cmd + ' ' + redir + ' "' + target + '") 9>"' + lock_base + '.lock"'
            )
            new_content = new_content[:m.start()] + replacement + new_content[m.end():]
            did_patch = True

        if did_patch:
            save(path, new_content)
            patched.append(path)
        else:
            needs_manual.append(path)

    for path in needs_manual:
        skipped.append((
            path,
            'session.json: write pattern too complex to auto-patch — wrap with: '
            '`(flock -x 9; <write-cmd>) 9>"${SESSION_FILE}.lock"`',
        ))

    return patched


# ---------------------------------------------------------------------------
# Validation gate
# ---------------------------------------------------------------------------

def validate_shell_syntax():
    """`bash -n` every shell file we rewrote; abort before committing if any is broken.

    Fail closed: the hardening fixes rewrite shell textually, so a regex bug can
    emit invalid bash. A broken rewrite must never reach git — exit non-zero so the
    workflow step fails loudly instead of opening a PR that silently ships broken hooks.
    """
    broken = []
    for path in changed_files:
        if not path.endswith(('.sh', '.bash')):
            continue
        result = subprocess.run(['bash', '-n', path], capture_output=True, text=True)
        if result.returncode != 0:
            broken.append((path, result.stderr.strip()))

    if broken:
        print('\n❌ Hardening produced invalid bash — aborting without commit:\n',
              file=sys.stderr)
        for path, err in broken:
            print('  ' + path + ':\n    ' + err.replace('\n', '\n    '), file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------

def commit_and_push():
    if not changed_files:
        return
    subprocess.run(['git', 'add'] + changed_files, check=True)
    subprocess.run(
        ['git', 'commit', '-m',
         'security: auto-harden upstream code (set+x guards, webhook https-only, session flock)'],
        check=True,
    )
    subprocess.run(
        ['git', 'push', 'origin', 'upstream-sync', '--force'],
        check=True,
    )


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def write_report(f1, f2, f3):
    lines = ['## Security Hardening Report\n']

    all_patched = f1 + f2 + f3
    if all_patched:
        lines.append('The following fixes were **automatically committed** to this branch:\n')
        if f1:
            lines.append('**Fix 1 — `{ set +x; }` guards** — API keys suppressed in bash `set -x` traces')
            for f in f1:
                lines.append('  - `' + f + '`')
        if f2:
            lines.append('\n**Fix 2 — Webhook https-only** — localhost/127.0.0.1 allowances removed (SSRF risk in containers)')
            for f in f2:
                lines.append('  - `' + f + '`')
        if f3:
            lines.append('\n**Fix 3 — `flock` on session.json writes** — prevents concurrent hook corruption')
            for f in f3:
                lines.append('  - `' + f + '`')
    else:
        lines.append('No auto-patches applicable — upstream code matched no hardening patterns.\n')

    if skipped:
        lines.append('\n**Manual review required for these patterns:**')
        for path, reason in skipped:
            lines.append('  - `' + path + '`: ' + reason)

    report = '\n'.join(lines)
    open('/tmp/hardening_report.md', 'w').write(report)
    print(report)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    f1 = fix1_setx_guards()
    f2 = fix2_webhook_https_only()
    f3 = fix3_session_locking()

    write_report(f1, f2, f3)

    if changed_files:
        validate_shell_syntax()   # fail closed: never commit/push invalid bash
        commit_and_push()
        print('\nHardening committed and pushed to upstream-sync.')
    else:
        print('\nNo changes needed.')


# Guarded so the fix functions can be imported by test_security_harden.py
# without triggering the git operations in commit_and_push().
if __name__ == '__main__':
    main()
