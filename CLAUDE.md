# Agent Notes

This repo is a small zsh plugin that turns natural-language prompts into shell commands.

## Public Docs

- `README.md`: product pitch, quick install, usage
- `INSTALL.md`: install methods, providers, config
- `TROUBLESHOOTING.md`: setup and runtime issues
- `CONTRIBUTING.md`: contributor workflow

## Code Shape

- `zsh-ai.plugin.zsh`: loads modules
- `lib/config.zsh`: defaults and provider validation
- `lib/context.zsh`: directory, project, git, and OS context
- `lib/widget.zsh`: `# ...` comment flow and `#! ...` agent trigger
- `lib/utils.zsh`: prompt construction, provider routing, `zsh-ai`, `--agent` dispatch
- `lib/agent.zsh`: agent mode — text-protocol loop, stateless executor, confirm-each gate
- `lib/providers/`: provider modules

## Invariants

- zsh implementation, with `curl` and `perl` required
- `jq` stays optional
- single-shot modes put commands in the prompt before execution; agent mode
  (`#! ` / `zsh-ai --agent`) instead runs commands itself, gated by
  confirm-each-command — never remove that gate
- test both `# ...` and `zsh-ai "..."`
- provider changes need tests and docs

## Agent Mode

- `#! ` / `zsh-ai --agent` drives a mini-swe-agent-style loop: the model emits a
  fenced ` ```tool ``` ` block, we run it (fresh subshell, stateless) and feed back
  stdout/stderr + exit code; a reply with no block is the final answer.
- Gemini-only in v1 (`_zsh_ai_agent_available`); the multi-turn query is
  `_zsh_ai_agent_query_gemini`.

## Tests

```bash
./run-tests.zsh
./run-tests.zsh tests/providers
zsh tests/config.test.zsh
```

CI runs ShellCheck, but the workflow currently does not fail on ShellCheck output.

## Provider Work

Update `lib/config.zsh`, the provider module, `tests/providers/`, `README.md`, and `INSTALL.md`. Cover API errors, empty responses, and parsing with and without `jq`.
