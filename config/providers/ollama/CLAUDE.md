# Ollama Provider Configuration

This file contains Ollama-specific instructions for Claude Octopus workflows.

## Provider Information

- **Provider**: Ollama (Local LLM)
- **Emoji**: (none — local provider, no cost indicator needed)
- **API Key**: None required — fully local
- **CLI Command**: `ollama`

## Detection

- CLI: `command -v ollama`
- Server health: `curl -s http://localhost:11434/api/tags`

If the CLI is installed but the server is not running, suggest: `ollama serve`

## Role Assignment

Ollama models serve as:
- **Research assistant** — local model for exploration and brainstorming
- **Implementation reviewer** — code review without API costs
- **Fallback** — when external providers are unavailable

## Model Selection

Use `ollama list` to detect available models. Prefer:
- `llama3.3` or `llama3.1` for general tasks
- `codellama` for code-specific tasks
- `mistral` as a lightweight alternative

## Usage Patterns

### Invoking Ollama

```bash
# Basic query
ollama run <model> "<prompt>"

# List available models
ollama list

# Pull a model
ollama pull llama3.3
```

### Ollama Strengths

Ollama excels at:
1. **Zero-Cost Iteration** — Unlimited queries with no API spend
2. **Offline Workflows** — No internet connection required
3. **Privacy-Sensitive Tasks** — All data stays on-device
4. **Rapid Prototyping** — Quick brainstorming without budget concerns
5. **Fallback Coverage** — Available when cloud providers are down or rate-limited

### When to Use Ollama

Use Ollama for:
- Exploration and brainstorming when cost matters
- Offline or air-gapped environments
- Privacy-sensitive code review
- Fallback when Codex/Gemini auth is expired or unavailable
- Local testing of prompt patterns before sending to cloud providers

## Dispatch Pattern

```bash
ollama run <model> "<prompt>"
```

## Cost

Zero — fully local, no API keys needed.

## Limitations

- Quality varies significantly by model size
- No streaming in CLI mode (batch output)
- Limited context window compared to cloud providers
- Not suitable for primary orchestration role
- Requires sufficient local hardware (RAM/GPU) for larger models
- Model download required before first use

## Timeout Configuration

Default timeout: 120 seconds (local models can be slower on first load)
Can be configured in orchestrate.sh:
```bash
OLLAMA_TIMEOUT=180  # 3 minutes for large models
```

## Error Handling

Common errors:
- `connection refused`: Ollama server not running — run `ollama serve`
- `model not found`: Model not pulled — run `ollama pull <model>`
- `out of memory`: Model too large for available RAM/VRAM — try a smaller model
- `Timeout`: Model loading on first run — increase timeout or use a smaller model

## Integration with Workflows

Ollama can be used in:
- **Discover Phase**: Local brainstorming and exploration
- **Develop Phase**: Code review without API costs
- **Fallback**: Any phase when cloud providers are unavailable
