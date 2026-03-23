---
command: embrace
description: "Full Double Diamond workflow - Research → Define → Develop → Deliver"
aliases:
  - full-cycle
  - complete-workflow
---

# Embrace - Complete Double Diamond Workflow

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:embrace`, you MUST execute the full workflow below. You are PROHIBITED from:**
- Deciding the task is "too simple" for the workflow
- Doing the task directly instead of running the phases
- Skipping phases because you judge them unnecessary
- Substituting your own approach for the structured workflow

**The user chose `/octo:embrace` deliberately.** Respect that choice. Even for seemingly simple tasks, the workflow adds multi-provider research, structured definition, quality gates, and validation that the user wants. If the task truly doesn't benefit from the workflow, the user will tell you — do not make that judgment yourself.

**If you catch yourself thinking "this is straightforward, I'll just do it directly" — STOP. That is exactly the behavior this instruction prohibits.**

---

When the user invokes this command (e.g., `/octo:embrace <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting the embrace workflow, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure high-quality workflow execution:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's the scope of this project?",
      header: "Scope",
      multiSelect: false,
      options: [
        {label: "Small feature", description: "Single component or small addition"},
        {label: "Medium feature", description: "Multiple components or moderate complexity"},
        {label: "Large feature", description: "System-wide changes or new subsystem"},
        {label: "Full system", description: "Complete application or major architecture"}
      ]
    },
    {
      question: "What areas require the most attention?",
      header: "Focus Areas",
      multiSelect: true,
      options: [
        {label: "Architecture design", description: "System structure and design patterns"},
        {label: "Security", description: "Authentication, authorization, data protection"},
        {label: "Performance", description: "Speed, scalability, optimization"},
        {label: "User experience", description: "UI/UX and usability"}
      ]
    },
    {
      question: "What's your preferred level of autonomy?",
      header: "Autonomy",
      multiSelect: false,
      options: [
        {label: "Supervised (default)", description: "Review and approve after each phase"},
        {label: "Semi-autonomous", description: "Only intervene if quality gates fail"},
        {label: "Autonomous", description: "Run all 4 phases automatically"},
        {label: "Manual", description: "I'll guide each step explicitly"}
      ]
    },
    {
      question: "Should critical decisions be stress-tested with a Multi-LLM debate? (Claude + Codex + Gemini deliberate together)",
      header: "Multi-LLM Debate Gates",
      multiSelect: false,
      options: [
        {label: "Yes — Multi-LLM debate at Define→Develop gate", description: "Claude, Codex, and Gemini debate the chosen approach before implementing (recommended for Large/Full scope)"},
        {label: "Yes — Multi-LLM debate at both gates", description: "Three-model debate after Define AND before Deliver (maximum rigor, uses external API credits)"},
        {label: "No — skip Multi-LLM debates", description: "Standard workflow without multi-model debate checkpoints"},
        {label: "Only if disagreement detected", description: "Auto-trigger Multi-LLM debate when providers show significant divergence"}
      ]
    }
  ]
})
```

**After receiving answers:**
- Store the context for use across all 4 phases
- Set autonomy mode based on user preference
- Store debate gate preference for phase transitions
- Proceed with the embrace workflow incorporating this context

### Step 2: Check Provider Availability & Display Banner

**Check which AI providers are available and display the visual indicator banner:**

First, check availability:
```bash
codex_available=$(command -v codex &> /dev/null && echo "✓" || echo "✗ Not installed")
gemini_available=$(command -v gemini &> /dev/null && echo "✓" || echo "✗ Not installed")
```

Then output the banner:
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Full Double Diamond Workflow
🐙 Embrace: [Brief description of what's being built]

All Phases:
🔍 Discover - Multi-provider research
🎯 Define - Consensus building
🛠️ Develop - Implementation with quality gates
✅ Deliver - Final validation and review

Provider Availability:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Gemini CLI: [Available ✓ / Not installed ✗]
🟣 Perplexity: [Available ✓ / Not configured ✗]
🔵 Claude: Available ✓

Project Context:
Scope: [User's scope answer]
Focus: [User's focus areas]
Autonomy: [User's autonomy preference]
```

**If providers are missing:**
- Note in the banner which providers are unavailable
- Suggest running `/octo:setup` to configure missing providers
- Proceed with available providers only

### Step 3: Execute Workflow

**Run orchestrate.sh with the embrace command:**

Use the Bash tool to execute:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh embrace "<user's prompt>"
```

**What happens:**
1. **Probe Phase** - Multi-provider research via spawn_agent() calls to Codex/Gemini
2. **Grasp Phase** - Consensus building with run_agent_sync()
3. **🐙 Define→Develop Debate Gate** (if enabled) — see Step 3b
4. **Tangle Phase** - Implementation with quality gates
5. **🐙 Develop→Deliver Debate Gate** (if "both gates" selected) — see Step 3c
6. **Ink Phase** - Final validation and delivery

**Autonomy handling:**
- Supervised mode: Pauses after each phase for approval
- Semi-autonomous: Auto-proceeds unless quality gate fails
- Autonomous: Runs all 4 phases without intervention

**Results saved to:**
- `~/.claude-octopus/results/probe-synthesis-<timestamp>.md`
- `~/.claude-octopus/results/grasp-consensus-<timestamp>.md`
- `~/.claude-octopus/results/tangle-validation-<timestamp>.md`
- `~/.claude-octopus/results/delivery-<timestamp>.md`

### Step 3b: Define→Develop Debate Gate

**When the user selected debate gates ("at Define→Develop gate", "at both gates", or "only if disagreement detected"):**

After the Grasp (Define) phase completes and before Tangle (Develop) begins:

1. **Read the grasp consensus** from `~/.claude-octopus/results/grasp-consensus-*.md`
2. **Run a 1-round quick debate** challenging the chosen approach:

```
🐙 **DEBATE GATE** — Stress-testing the Define→Develop transition
🐙 Question: "Given this consensus, what are the biggest risks if we proceed? What alternatives were dismissed too quickly?"
```

Use the debate skill with these parameters:
- `--rounds 1 --debate-style adversarial --max-words 200`
- Pass the grasp consensus as `--context-file`
- Each provider argues against the consensus to surface blind spots

3. **Evaluate debate outcome:**
   - If all providers agree the approach is sound → proceed to Develop
   - If significant risks surface → present findings to user with AskUserQuestion:

```javascript
AskUserQuestion({
  questions: [{
    question: "The debate gate surfaced concerns about the chosen approach. How should we proceed?",
    header: "Debate Gate Result",
    multiSelect: false,
    options: [
      {label: "Proceed anyway", description: "Accept the risks and continue to Develop"},
      {label: "Revise approach", description: "Adjust the plan based on debate findings, then continue"},
      {label: "Run deeper debate", description: "Run a thorough 3-round debate before deciding"},
      {label: "Stop and review", description: "Pause the workflow for manual review"}
    ]
  }]
})
```

4. **"Only if disagreement detected" mode:** Skip the debate if the grasp consensus score was ≥85%. Only trigger when providers showed significant divergence during Define.

### Step 3c: Develop→Deliver Debate Gate

**Only runs when user selected "at both gates".**

After Tangle (Develop) completes, before Ink (Deliver):

1. **Read the tangle validation** from `~/.claude-octopus/results/tangle-validation-*.md`
2. **Run a 1-round collaborative debate** on implementation quality:

```
🐙 **DEBATE GATE** — Validating implementation before delivery
🐙 Question: "Review this implementation. What would you change before shipping? What edge cases are missing?"
```

Use: `--rounds 1 --debate-style collaborative --max-words 200`

3. **Present any non-trivial findings** to user before proceeding to Deliver.

### Step 3d: Auto Code Review & E2E Verification (MANDATORY)

**After the Develop phase completes (and any debate gates), BEFORE presenting results, launch two verification agents in parallel:**

**Agent 1 — Code Review (Sonnet):**
```
Agent(
  model: "sonnet",
  subagent_type: "feature-dev:code-reviewer",
  run_in_background: true,
  description: "Code review: embrace deliver",
  prompt: "Review all code changes from this embrace workflow session. Check git diff for changed files. Focus on bugs, security, logic errors, and adherence to project conventions. Report only high-confidence issues."
)
```

**Agent 2 — E2E Verification (Sonnet):**
```
Agent(
  model: "sonnet",
  run_in_background: true,
  description: "E2E test: embrace deliver",
  prompt: "Run the project's test suite and verify no regressions. Check that new files are properly integrated. Report tests passed/failed and any integration issues."
)
```

**After both agents complete**, include their findings in the results presentation below. Flag any HIGH-confidence review issues or test failures prominently.

WHY: Every embrace workflow produces code changes. Automated review by a different model (Sonnet) catches issues the implementation agents missed. Running tests catches regressions before the user ships.

### Step 4: Present Results & Interactive Next Steps

**CRITICAL: After orchestrate.sh completes, you MUST present results AND ask the user what to do next. Do NOT end the session silently.**

1. Read the result files from `~/.claude-octopus/results/` and present a concise synthesis
2. Include code review and E2E verification findings from Step 3d
3. **Always ask what to do next using AskUserQuestion:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "The embrace workflow has completed all 4 phases. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Review phase outputs in detail", description: "Walk through each phase's findings and deliverables"},
        {label: "Refine the implementation", description: "Make adjustments based on the results"},
        {label: "Run another iteration", description: "Re-run specific phases with updated context"},
        {label: "Start a new task", description: "Move on to something else"},
        {label: "Export results", description: "Save a summary document of the workflow output"}
      ]
    }
  ]
})
```

**You are PROHIBITED from ending the conversation or session after the workflow completes without asking the user this question.** The user expects an interactive handoff, not a silent exit.

## Usage

```bash
/octo:embrace        # Full workflow with natural language
```

## What is Embrace?

**Embrace** 🐙 runs all four phases of the Double Diamond methodology in sequence:

1. **Discover** - Multi-perspective research (Codex + Gemini)
2. **Define** - Consensus building on problem/approach
3. **Develop** - Implementation with quality validation
4. **Deliver** - Final quality gates and output

## Natural Language Examples

Just describe what you want to build:

```
"Build a complete user authentication system"
"Create a caching layer from research to delivery"
"Design and implement a payment processing feature"
```

Claude will automatically use the embrace workflow for complex features that need thorough exploration.

## Autonomy Modes

You can configure how much human oversight you want:

- **Supervised** (default) - Approval required after each phase
- **Semi-autonomous** - Approval only when quality gates fail
- **Autonomous** - Runs all 4 phases automatically

Set in `/octo:setup` or use orchestrate.sh flags:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh embrace --autonomy supervised "your prompt"
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh embrace --autonomy autonomous "your prompt"
```

## When to Use Embrace

Use embrace for:
- Complex features requiring research → implementation
- High-stakes projects needing validation
- Features where you want multiple AI perspectives
- When you need structured quality gates

## Quality Gates

The tangle (develop) phase includes automatic quality validation:
- 75% consensus threshold
- Security checks
- Best practices verification
- Performance considerations

If quality gates fail in semi-autonomous mode, you'll be prompted to review.

## Learn More

- `/octo:discover` - Run just the research phase
- `/octo:define` - Run just the definition phase
- `/octo:develop` - Run just the development phase
- `/octo:deliver` - Run just the delivery/review phase
