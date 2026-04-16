# Troubleshooting

## Common Issues

### API Key not found
```bash
zsh-ai: Warning: ANTHROPIC_API_KEY not set. Plugin will not function.
```
**Solution:** Either set your API key or switch to Ollama:
```bash
# Option 1: Set Anthropic API key
export ANTHROPIC_API_KEY="your-key"

# Option 2: Use Ollama instead
export ZSH_AI_PROVIDER="ollama"
```

### Ollama not running
```bash
Error: Ollama is not running at http://localhost:11434
```
**Solution:** Start Ollama with `ollama serve`

### JSON parsing errors
Install `jq` for better reliability:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

### `??` shows no output or explanation

If `??` produces no explanation, the most likely causes are:

1. **No previous command recorded** — `??` relies on the `preexec` hook tracking the last command. This hook is registered on the first prompt after the plugin loads. If you type `??` before running any other command, there's nothing to explain.

2. **API error** — Same as any other trigger; check your API key and provider config.

### `??` doesn't include command output

Output capture is off by default. Enable it with:
```bash
export ZSH_AI_CAPTURE_OUTPUT=1
```

Note: this tees all terminal output through a temp file. Interactive programs (vim, less, fzf) may behave unexpectedly with capture enabled.

## Need More Help?

If you're still experiencing issues:
1. Check that you have the latest version of zsh-ai
2. Verify your API keys are correct
3. [Open an issue](https://github.com/matheusml/zsh-ai/issues) with details about your setup