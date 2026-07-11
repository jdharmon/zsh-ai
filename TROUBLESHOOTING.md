# Troubleshooting

Start with the direct command so errors are easy to see:

```bash
zsh-ai "show current date"
```

## API Key Missing

```bash
zsh-ai: Warning: ANTHROPIC_API_KEY not set. Plugin will not function.
```

Set the key for your provider:

```bash
export ANTHROPIC_API_KEY="your-key"
```

For permanent setup, put the key above the `zsh-ai` load line in a private `~/.zshrc`.

Or switch to Ollama:

```bash
export ZSH_AI_PROVIDER="ollama"
```

## Ollama Is Not Running

```bash
Error: Ollama is not running at http://localhost:11434
```

```bash
ollama serve
ollama pull llama3.2
```

## Nothing Happens With `#`

Reload your shell config:

```bash
source ~/.zshrc
```

Then test the explicit command:

```bash
zsh-ai "list files"
```

If that works, restart your terminal so the zle widget binding reloads.

## Pasting Code Breaks `#` Comments

If you paste code blocks that start with `# comment` lines, the inline hook can
intercept the first line and fire an unwanted query. Either change the trigger to
something you won't paste, or disable the hook and use `zsh-ai "..."` instead:

```bash
# Use a different trigger
export ZSH_AI_TRIGGER=",,"

# Or turn the inline hook off entirely
export ZSH_AI_COMMENT_HOOK="false"
```

See [INSTALL.md](INSTALL.md#inline-trigger) for details.

## JSON Parse Errors

Install `jq`:

```bash
brew install jq
```

Ubuntu or Debian:

```bash
sudo apt-get install jq
```

## Agent Mode Issues

**"agent mode currently supports the 'gemini' provider only"** — agent mode
(`#! ` or `zsh-ai --agent`) needs `ZSH_AI_PROVIDER=gemini` and `GEMINI_API_KEY`
set. Other providers fall back to the single-command modes.

**A command hangs, then reports `[exit 124]`** — that command hit
`ZSH_AI_AGENT_TIMEOUT` (default 30s). Interactive programs (`vim`, `less`,
`ssh`, `top`) can't be driven by the agent and will always time out; ask for a
non-interactive alternative, or raise the timeout for legitimately slow commands.

**A later step "forgot" a `cd` or exported variable** — each command runs in a
fresh shell, so state does not persist between steps. This is expected; the agent
is prompted to chain dependent steps into a single command (`cd dir && ...`).

## Still Stuck

Check the active provider and model:

```bash
zsh-ai
```

Then open an issue with your OS, zsh version, provider, install method, and exact error:

https://github.com/matheusml/zsh-ai/issues
