#!/usr/bin/env python3
"""Unit tests for security-harden.py — fix3 session.json flock lock-naming.

Regression guard. fix3 rewrites session-file writes to take a flock before
writing. The flock anchor MUST be derived from the *canonical* session file,
not from the write target — atomic-write hooks stage to "$SESSION_FILE.tmp"
before mv'ing into place, and keying the lock on that staging path emits
"${SESSION_FILE}.tmp.lock". That is a different file from the lock used by
hooks that write the session file directly ("$SESSION_FILE.lock"), and flock
only serializes processes holding the *same* file — so the two groups stop
excluding each other and the hardening silently no-ops on the very concurrency
it exists to guard.

This bug shipped twice (caught only at PR review). These tests pin the
invariant so the next tweak to the fix3 regex/replacement can't reintroduce it.

Dependency-free (stdlib unittest). Run:
    python3 .github/scripts/test_security_harden.py
"""

import importlib.util
import os
import re
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'security-harden.py')


def load_module():
    """Import security-harden.py. Safe because its main() is __name__-guarded."""
    spec = importlib.util.spec_from_file_location('security_harden', SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Normalize ${SESSION_FILE} and $SESSION_FILE to one form for lock comparison.
def _norm(name):
    return name.replace('${SESSION_FILE}', '$SESSION_FILE')


class Fix3LockNaming(unittest.TestCase):
    def setUp(self):
        self.mod = load_module()
        self.prev_cwd = os.getcwd()
        self.tmp = tempfile.mkdtemp()
        os.chdir(self.tmp)
        os.makedirs('hooks')

    def tearDown(self):
        os.chdir(self.prev_cwd)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _harden(self, files):
        # Reset module-level accumulators between runs (fix functions mutate globals).
        self.mod.changed_files.clear()
        self.mod.skipped.clear()
        for name, content in files.items():
            with open(os.path.join('hooks', name), 'w') as fh:
                fh.write(content)
        self.mod.fix3_session_locking()

    def _read(self, name):
        with open(os.path.join('hooks', name)) as fh:
            return fh.read()

    def _locks(self, name):
        return re.findall(r'9>"([^"]+)"', self._read(name))

    # --- the core invariant: lock keys off the canonical file, never the staging path ---

    def test_staged_tmp_write_locks_on_canonical_file(self):
        self._harden({
            'a.sh': 'jq ".x = 1" "$SESSION_FILE" > "${SESSION_FILE}.tmp" \\\n'
                    '    && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"\n',
        })
        self.assertEqual(self._locks('a.sh'), ['${SESSION_FILE}.lock'])

    def test_direct_write_locks_on_canonical_file(self):
        self._harden({'b.sh': 'printf \'{}\' > "$SESSION_FILE"\n'})
        self.assertEqual(self._locks('b.sh'), ['$SESSION_FILE.lock'])

    def test_no_lock_ever_keys_on_staging_path(self):
        # The exact regression: a ".tmp.lock" anchor must never be emitted.
        self._harden({'c.sh': 'jq ".q = .q[1:]" "$SESSION_FILE" > "${SESSION_FILE}.tmp"\n'})
        self.assertNotIn('.tmp.lock', self._read('c.sh'))

    def test_staged_and_direct_writers_share_one_lock(self):
        # The property that makes flock actually serialize: every writer of a
        # given session file must converge on an identical lock name.
        self._harden({
            'staged.sh': 'jq ".x = 1" "$SESSION_FILE" > "${SESSION_FILE}.tmp"\n',
            'direct.sh': 'printf \'{}\' > "${SESSION_FILE}"\n',
        })
        self.assertEqual(
            _norm(self._locks('staged.sh')[0]),
            _norm(self._locks('direct.sh')[0]),
        )

    # --- the write target itself must be preserved (staging path unchanged) ---

    def test_staged_write_target_preserved(self):
        self._harden({'a.sh': 'jq ".x = 1" "$SESSION_FILE" > "${SESSION_FILE}.tmp"\n'})
        out = self._read('a.sh')
        self.assertIn('> "${SESSION_FILE}.tmp")', out)  # still writes to the temp file

    # --- nothing the hardener emits may be invalid bash ---

    def test_hardened_output_is_valid_bash(self):
        files = {
            'a.sh': '#!/usr/bin/env bash\n'
                    'jq ".x = 1" "$SESSION_FILE" > "${SESSION_FILE}.tmp" \\\n'
                    '    && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"\n',
            'b.sh': '#!/usr/bin/env bash\nprintf \'{}\' > "$SESSION_FILE"\n',
            'c.sh': '#!/usr/bin/env bash\njq ".q = .q[1:]" "$SESSION_FILE" > "${SESSION_FILE}.tmp"\n',
        }
        self._harden(files)
        for name in files:
            result = subprocess.run(
                ['bash', '-n', os.path.join('hooks', name)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, '%s: %s' % (name, result.stderr))

    # --- the rewrite must actually take a lock ---

    def test_flock_is_applied(self):
        self._harden({'a.sh': 'jq ".x = 1" "$SESSION_FILE" > "${SESSION_FILE}.tmp"\n'})
        self.assertIn('flock -x 9', self._read('a.sh'))


class Fix2WebhookHttpsOnly(unittest.TestCase):
    # Mirrors upstream telemetry-webhook.sh: localhost-exempting guard + a comment
    # whose "(localhost exempted for dev)" becomes false once hardened. The hardener
    # must remove the code conditions AND normalize the stale comment so its output
    # is deterministic (== fork main) and stops re-conflicting every sync.
    UPSTREAM = (
        '#!/usr/bin/env bash\n'
        'WEBHOOK_URL="${OCTOPUS_WEBHOOK_URL:-}"\n'
        '# Reject non-HTTPS URLs to prevent credential leakage (localhost exempted for dev)\n'
        'if [[ "$WEBHOOK_URL" != https://* && "$WEBHOOK_URL" != http://localhost* '
        '&& "$WEBHOOK_URL" != http://127.0.0.1* ]]; then\n'
        '    echo continue\n'
        'fi\n'
    )

    def setUp(self):
        self.mod = load_module()
        self.prev_cwd = os.getcwd()
        self.tmp = tempfile.mkdtemp()
        os.chdir(self.tmp)
        os.makedirs('hooks')

    def tearDown(self):
        os.chdir(self.prev_cwd)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _harden(self, content):
        self.mod.changed_files.clear()
        self.mod.skipped.clear()
        with open('hooks/telemetry-webhook.sh', 'w') as fh:
            fh.write(content)
        self.mod.fix2_webhook_https_only()
        with open('hooks/telemetry-webhook.sh') as fh:
            return fh.read()

    def test_localhost_conditions_removed(self):
        out = self._harden(self.UPSTREAM)
        self.assertNotIn('http://localhost', out)
        self.assertNotIn('http://127.0.0.1', out)
        self.assertIn('if [[ "$WEBHOOK_URL" != https://* ]]; then', out)

    def test_stale_localhost_comment_normalized(self):
        # The regression that re-conflicted every sync: the descriptive comment
        # must lose its now-false localhost parenthetical.
        out = self._harden(self.UPSTREAM)
        self.assertIn('# Reject non-HTTPS URLs to prevent credential leakage\n', out)
        self.assertNotIn('localhost exempted for dev', out)

    def test_harden_annotation_not_clobbered(self):
        # The annotation legitimately contains "(localhost removed …)"; the comment
        # normalizer must NOT strip its parenthetical.
        out = self._harden(self.UPSTREAM)
        self.assertIn('# harden: https-only (localhost removed — SSRF risk in containers)', out)

    def test_output_is_valid_bash(self):
        out = self._harden(self.UPSTREAM)
        with open('hooks/out.sh', 'w') as fh:
            fh.write(out)
        result = subprocess.run(['bash', '-n', 'hooks/out.sh'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_idempotent_on_already_hardened(self):
        # Running the hardener on its own output must be a no-op (no double-strip,
        # no re-annotation) — already-hardened fork main must converge, not churn.
        once = self._harden(self.UPSTREAM)
        twice = self._harden(once)
        self.assertEqual(once, twice)


if __name__ == '__main__':
    import warnings
    # security-harden.py reads/writes via the open().read() idiom (no context
    # manager) and leaks handles to the gc — harmless here, but it floods the
    # test output with ResourceWarnings. Silence them so failures stay readable.
    warnings.simplefilter('ignore', ResourceWarning)
    unittest.main(verbosity=2)
