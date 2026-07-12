#!/usr/bin/env zsh

# Configuration and validation for zsh-ai

# Set default values for configuration
: ${ZSH_AI_PROVIDER:="anthropic"}  # Default to anthropic for backwards compatibility
: ${ZSH_AI_OLLAMA_MODEL:="llama3.2"}  # Popular fast model
: ${ZSH_AI_OLLAMA_URL:="http://localhost:11434"}  # Default Ollama URL
: ${ZSH_AI_GEMINI_MODEL:="gemini-2.5-flash"}  # Fast Gemini 2.5 model
: ${ZSH_AI_OPENAI_MODEL:="gpt-5.4-mini"}  # Default to GPT-5.4 mini (gpt-5-mini is deprecated)
: ${ZSH_AI_OPENAI_URL:="https://api.openai.com/v1/chat/completions"}  # Default to OpenAI
: ${ZSH_AI_OPENAI_THINKING:=""}  # Configure thinking for supported models: 0 or 1, default unset/empty
: ${ZSH_AI_OPENAI_REASONING_EFFORT:=""}  # Configure reasoning effort for supported OpenAI-compatible models
: ${ZSH_AI_QWEN_MODEL:="qwen-flash"}  # Default to qwen-flash (fast, low-cost Qwen3 tier)
: ${ZSH_AI_QWEN_URL:="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"}  # Default to Qwen API
: ${ZSH_AI_ANTHROPIC_MODEL:="claude-haiku-4-5"}  # Default Anthropic model
: ${ZSH_AI_ANTHROPIC_URL:="https://api.anthropic.com/v1/messages"}  # Default Anthropic URL
: ${ZSH_AI_GROK_MODEL:="grok-4.3"}  # Default Grok model (provider sends reasoning_effort=none for speed)
: ${ZSH_AI_GROK_URL:="https://api.x.ai/v1/chat/completions"}  # Default Grok URL
: ${ZSH_AI_MISTRAL_MODEL:="mistral-small-latest"}  # Default Mistral model
: ${ZSH_AI_MISTRAL_URL:="https://api.mistral.ai/v1/chat/completions"}  # Default Mistral URL

# Inline trigger configuration
: ${ZSH_AI_COMMENT_HOOK:="true"}  # Set to false/off/no/0 to disable the inline trigger widget entirely
: ${ZSH_AI_TRIGGER:="# "}  # Prompt prefix that triggers AI (e.g. ",," instead of "# ")

# Active output-capture backend for ??: "tmux", "herdr", or "" (none).
# tmux wins when both are present (innermost multiplexer reads the real pane).
# herdr injects HERDR_PANE_ID into each managed pane's shell (HERDR_ACTIVE_* only
# reaches custom-command invocations, not the pane shell); accept either.
_zsh_ai_mux_backend() {
    if [[ -n "$TMUX" ]]; then
        echo "tmux"
    elif [[ "${HERDR_ENV:-}" == "1" && -n "${HERDR_PANE_ID:-${HERDR_ACTIVE_PANE_ID:-}}" ]]; then
        echo "herdr"
    fi
}

# Agent mode configuration
: ${ZSH_AI_AGENT_TRIGGER:="#! "}  # Inline prefix that launches the agent loop
: ${ZSH_AI_AGENT_MAX_STEPS:=15}   # Max tool calls before the loop stops
: ${ZSH_AI_AGENT_TIMEOUT:=30}     # Per-command timeout in seconds (best-effort)
: ${ZSH_AI_AGENT_MAX_OUTPUT:=4096}  # Max bytes of command output fed back to the model

# Return 0 if agent mode can run with the current configuration, 1 otherwise.
# v1 supports Gemini only.
_zsh_ai_agent_available() {
    if [[ "$ZSH_AI_PROVIDER" != "gemini" ]]; then
        echo "zsh-ai: agent mode currently supports the 'gemini' provider only (ZSH_AI_PROVIDER=$ZSH_AI_PROVIDER)." >&2
        return 1
    fi
    return 0
}

# Return 0 if the inline trigger widget should be enabled, 1 otherwise
_zsh_ai_comment_hook_enabled() {
    case "${ZSH_AI_COMMENT_HOOK:l}" in
        false|off|no|0|disabled) return 1 ;;
        *) return 0 ;;
    esac
}

# Optional: Extend the system prompt with custom instructions
# ZSH_AI_PROMPT_EXTEND - Add custom instructions to the AI prompt without replacing the core prompt
# Example: export ZSH_AI_PROMPT_EXTEND="Always prefer ripgrep (rg) over grep. Use modern CLI tools when available."

# Provider validation
_zsh_ai_validate_config() {
    if [[ "$ZSH_AI_PROVIDER" != "anthropic" ]] && [[ "$ZSH_AI_PROVIDER" != "ollama" ]] && [[ "$ZSH_AI_PROVIDER" != "gemini" ]] && [[ "$ZSH_AI_PROVIDER" != "qwen" ]] && [[ "$ZSH_AI_PROVIDER" != "openai" ]] && [[ "$ZSH_AI_PROVIDER" != "grok" ]] && [[ "$ZSH_AI_PROVIDER" != "mistral" ]]; then
        echo "zsh-ai: Error: Invalid provider '$ZSH_AI_PROVIDER'. Use 'anthropic', 'ollama', 'gemini', 'openai', 'qwen', 'grok', or 'mistral'."
        return 1
    fi

    # Check requirements based on provider
    if [[ "$ZSH_AI_PROVIDER" == "anthropic" ]]; then
        if [[ -z "$ANTHROPIC_API_KEY" ]]; then
            echo "zsh-ai: Warning: ANTHROPIC_API_KEY not set. Plugin will not function."
            echo "zsh-ai: Set ANTHROPIC_API_KEY or use ZSH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$ZSH_AI_PROVIDER" == "gemini" ]]; then
        if [[ -z "$GEMINI_API_KEY" ]]; then
            echo "zsh-ai: Warning: GEMINI_API_KEY not set. Plugin will not function."
            echo "zsh-ai: Set GEMINI_API_KEY or use ZSH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$ZSH_AI_PROVIDER" == "openai" ]]; then
        # Only require API key when using the default OpenAI URL
        # Custom URLs (local servers, proxies) may not need authentication
        if [[ -z "$OPENAI_API_KEY" && -z "$ZSH_AI_OPENAI_API_KEY" && "$ZSH_AI_OPENAI_URL" == "https://api.openai.com/v1/chat/completions" ]]; then
            echo "zsh-ai: Warning: OPENAI_API_KEY not set. Plugin will not function."
            echo "zsh-ai: Set OPENAI_API_KEY or use ZSH_AI_PROVIDER=ollama for local models."
            return 1
        fi

        if [[ -n "$ZSH_AI_OPENAI_THINKING" && "$ZSH_AI_OPENAI_THINKING" != "0" && "$ZSH_AI_OPENAI_THINKING" != "1" ]]; then
            echo "zsh-ai: Error: ZSH_AI_OPENAI_THINKING must be 0, 1, or unset."
            return 1
        fi

    elif [[ "$ZSH_AI_PROVIDER" == "qwen" ]]; then
        if [[ -z "$QWEN_API_KEY" ]]; then
            echo "zsh-ai: Warning: QWEN_API_KEY not set. Plugin will not function."
            echo "zsh-ai: Set QWEN_API_KEY or use ZSH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$ZSH_AI_PROVIDER" == "grok" ]]; then
        if [[ -z "$XAI_API_KEY" ]]; then
            echo "zsh-ai: Warning: XAI_API_KEY not set. Plugin will not function."
            echo "zsh-ai: Set XAI_API_KEY or use ZSH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    elif [[ "$ZSH_AI_PROVIDER" == "mistral" ]]; then
        if [[ -z "$MISTRAL_API_KEY" ]]; then
            echo "zsh-ai: Warning: MISTRAL_API_KEY not set. Plugin will not function."
            echo "zsh-ai: Set MISTRAL_API_KEY or use ZSH_AI_PROVIDER=ollama for local models."
            return 1
        fi
    fi

    return 0
}
