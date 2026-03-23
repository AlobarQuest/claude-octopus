---
name: octopus-security-audit
aliases:
  - security
  - security-audit
description: OWASP compliance, vulnerability scanning, and adversarial red team testing
trigger: |
  Use this skill when the user says "security audit this code", "find vulnerabilities in X",
  "red team review", "pentest this API", or "check for OWASP issues".
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
invocation: human_only
---

# Security Audit Skill

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Security Audit`

Invokes the security-auditor persona for thorough security analysis during the `ink` (deliver) phase. Supports both quick OWASP scanning and full adversarial red/blue team testing.

## Usage

```bash
# Quick scan via security-auditor persona
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn security-auditor "Scan for SQL injection vulnerabilities"

# Adversarial red team via squeeze workflow
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze "Security audit the authentication module"

# Via auto-routing (detects security intent)
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "security audit the payment processing module"
```

## Capabilities

- OWASP Top 10 vulnerability detection
- SQL injection and XSS scanning
- Authentication/authorization review
- Secrets and credential detection
- Dependency vulnerability assessment
- Security configuration review

## Persona Reference

This skill wraps the `security-auditor` persona defined in:
- `agents/personas/security-auditor.md`
- CLI: `codex-review`
- Model: `gpt-5.2-codex`
- Phases: `ink`
- Expertise: `owasp`, `vulnerability-scanning`, `security-review`

## Example Prompts

```
"Scan for hardcoded credentials in the codebase"
"Check for CSRF vulnerabilities in form handlers"
"Review the API authentication implementation"
"Red team review the payment API"
```

---

## Adversarial Mode (squeeze workflow)

For comprehensive security testing, use the squeeze workflow which runs a 4-phase adversarial cycle:

1. **Blue Team** (Defense): Codex reviews code, identifies attack surface, proposes defenses
2. **Red Team** (Attack): Gemini attempts to break defenses, generates exploit PoCs
3. **Remediation** (Fix): Codex patches all vulnerabilities found
4. **Validation** (Verify): Gemini re-tests, confirms fixes or fails

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze "[user's security request]"
```

### OWASP Top 10 Coverage

- Broken Access Control
- Cryptographic Failures
- Injection
- Insecure Design
- Security Misconfiguration
- Vulnerable Components
- Authentication Failures
- Software Integrity Failures
- Logging & Monitoring Failures
- Server-Side Request Forgery

### Additional Attack Patterns

- Race conditions, business logic flaws
- Denial of service, information disclosure
- Client-side attacks (XSS, CSRF)

### Advanced Options

```bash
# Focus on specific vulnerabilities
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze --principles security "Audit for auth bypass only"

# Loop until all vulnerabilities fixed
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze --loop --quality 100 "Zero tolerance audit"
```

### When to Use Adversarial Mode

| Aspect | Quick Scan (spawn) | Adversarial (squeeze) |
|--------|-------------------|----------------------|
| Speed | 1-2 min | 5-10 min |
| Depth | Single perspective | Blue + Red team |
| Output | Issue list | Exploit PoCs + fixes |
| Best for | Pre-commit checks | Pre-deployment review |

## When NOT to Use This

- Production systems (use real pentest tools)
- Compliance audits (use certified auditors)
- Legal verification (consult security lawyers)

**Do use for**: pre-commit security checks, development-phase testing, architecture security review, CI/CD security gates.
