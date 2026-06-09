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
# Locates the if-line that starts the webhook validation block
_WEBHOOK_GUARD_LINE = re.compile(
    r'if\s+\[\[\s+"\$\{?(?:OCTOPUS_)?WEBHOOK_URL\}?"\s+!=\s+https://\*',
    re.IGNORECASE,
)


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
            # Annotate the surviving guard line so the intent is clear
            def annotate_guard(m):
                return m.group(0).rstrip() + '  # harden: https-only (localhost removed — SSRF risk in containers)'
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
_SESSION_WRITE = re.compile(
    r'^(\s*)((?:(?:echo|printf)\s+[^|>\n]+|jq\s+[^|>\n]+))\s*(>>?)\s*'
    r'("?\$\{?[A-Za-z_]*(?:SESSION|session)[A-Za-z_]*(?:FILE|PATH|JSON)?\}?"?'
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

            replacement = (
                indent + '# harden: atomic write — prevents concurrent session corruption\n'
                + indent + '(flock -x 9; ' + cmd + ' ' + redir + ' "' + target + '") 9>"' + target + '.lock"'
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

f1 = fix1_setx_guards()
f2 = fix2_webhook_https_only()
f3 = fix3_session_locking()

write_report(f1, f2, f3)

if changed_files:
    commit_and_push()
    print('\nHardening committed and pushed to upstream-sync.')
else:
    print('\nNo changes needed.')
