#!/usr/bin/env zsh

# Utility functions for zsh-ai

# Function to get the standardized system prompt for all providers
_zsh_ai_get_system_prompt() {
    # Allow callers to override the entire system prompt (used by explain mode)
    if [[ -n "${_ZSH_AI_SYSTEM_PROMPT_OVERRIDE:-}" ]]; then
        echo "$_ZSH_AI_SYSTEM_PROMPT_OVERRIDE"
        return
    fi

    local context="$1"
    local base_prompt="You are a zsh command generator. Generate syntactically correct zsh commands based on the user's natural language request.\n\nIMPORTANT RULES:\n1. Output ONLY the raw command - no explanations, no markdown, no backticks\n2. For arguments containing spaces or special characters, use single quotes\n3. Use double quotes only when variable expansion is needed\n4. Properly escape special characters within quotes\n\nExamples:\n- echo 'Hello World!' (spaces require quotes)\n- echo \"Current user: \$USER\" (variable expansion needs double quotes)\n- grep 'pattern with spaces' file.txt\n- find . -name '*.txt' (glob patterns in quotes)"

    # Add custom prompt extension if provided
    if [[ -n "$ZSH_AI_PROMPT_EXTEND" ]]; then
        echo "${base_prompt}\n\n${ZSH_AI_PROMPT_EXTEND}\n\nContext:\n$context"
    else
        echo "${base_prompt}\n\nContext:\n$context"
    fi
}

# System prompt for the ?? explain/fix trigger
_zsh_ai_get_explain_system_prompt() {
    echo "You are a ZSH command analyzer. Given a command, its exit code, any captured output, and an optional user question, analyze what happened.\n\nRESPONSE FORMAT:\n- If the error is fixable by the user (typo, wrong flag, wrong argument, bad syntax): respond on a SINGLE LINE using exactly this format:\n  FIX: <corrected command> /// <brief explanation (1-2 sentences)>\n- For all other cases (permission denied, file not found, network error, successful command, ambiguous error): respond with a plain explanation only - no FIX: prefix, no /// separator.\n- No markdown formatting. No code fences. No backticks. Everything on one line."
}

# Execute an explain/fix query using the explain system prompt
_zsh_ai_execute_explain() {
    local last_cmd="$1"
    local last_exit="$2"
    local last_output="$3"
    local user_query="$4"

    if [[ -z "$last_cmd" ]]; then
        echo "Error: No previous command found"
        return 1
    fi

    # Build the message with actual newlines so JSON escaping handles them correctly
    local message="Last command: ${last_cmd}"$'\n'"Exit code: ${last_exit}"
    if [[ -n "$last_output" ]]; then
        message="${message}"$'\n'"Output:"$'\n'"${last_output}"
    fi
    if [[ -n "$user_query" ]]; then
        message="${message}"$'\n\n'"User question: ${user_query}"
    fi

    _ZSH_AI_SYSTEM_PROMPT_OVERRIDE=$(_zsh_ai_get_explain_system_prompt)
    local response=$(_zsh_ai_query "$message")
    unset _ZSH_AI_SYSTEM_PROMPT_OVERRIDE

    echo "$response"
}

# Function to properly escape strings for JSON
_zsh_ai_escape_json() {
    # Use printf and perl for reliable JSON escaping
    printf '%s' "$1" | perl -0777 -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g; s/\f/\\f/g; s/\x08/\\b/g; s/[\x00-\x07\x0B\x0E-\x1F]//g'
}

# Main query function that routes to the appropriate provider
_zsh_ai_query() {
    local query="$1"

    if [[ "$ZSH_AI_PROVIDER" == "ollama" ]]; then
        # Check if Ollama is running first
        if ! _zsh_ai_check_ollama; then
            echo "Error: Ollama is not running at $ZSH_AI_OLLAMA_URL"
            echo "Start Ollama with: ollama serve"
            return 1
        fi
        _zsh_ai_query_ollama "$query"
    elif [[ "$ZSH_AI_PROVIDER" == "gemini" ]]; then
        _zsh_ai_query_gemini "$query"
    elif [[ "$ZSH_AI_PROVIDER" == "openai" ]]; then
        _zsh_ai_query_openai "$query"
    elif [[ "$ZSH_AI_PROVIDER" == "qwen" ]]; then
        _zsh_ai_query_qwen "$query"
    elif [[ "$ZSH_AI_PROVIDER" == "grok" ]]; then
        _zsh_ai_query_grok "$query"
    elif [[ "$ZSH_AI_PROVIDER" == "mistral" ]]; then
        _zsh_ai_query_mistral "$query"
    else
        _zsh_ai_query_anthropic "$query"
    fi
}

# Shared function to handle AI command execution
_zsh_ai_execute_command() {
    local query="$1"
    local cmd=$(_zsh_ai_query "$query")
    
    if [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
        echo "$cmd"
        return 0
    else
        # Return error
        echo "$cmd"
        return 1
    fi
}

# Optional: Add a helper function for users who prefer explicit commands
zsh-ai() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: zsh-ai \"your natural language command\""
        echo "Example: zsh-ai \"find all python files modified today\""
        echo ""
        echo "Current provider: $ZSH_AI_PROVIDER"
        if [[ "$ZSH_AI_PROVIDER" == "ollama" ]]; then
            echo "Ollama model: $ZSH_AI_OLLAMA_MODEL"
        elif [[ "$ZSH_AI_PROVIDER" == "gemini" ]]; then
            echo "Gemini model: $ZSH_AI_GEMINI_MODEL"
        elif [[ "$ZSH_AI_PROVIDER" == "openai" ]]; then
            echo "OpenAI model: $ZSH_AI_OPENAI_MODEL"
        elif [[ "$ZSH_AI_PROVIDER" == "qwen" ]]; then
            echo "Qwen model: $ZSH_AI_QWEN_MODEL"
        elif [[ "$ZSH_AI_PROVIDER" == "grok" ]]; then
            echo "Grok model: $ZSH_AI_GROK_MODEL"
        elif [[ "$ZSH_AI_PROVIDER" == "mistral" ]]; then
            echo "Mistral model: $ZSH_AI_MISTRAL_MODEL"
        fi
        return 1
    fi
    
    local query="$*"
    
    # Animation frames - rotating dots (same as widget)
    local dots=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local frame=0
    
    # Create a temp file for the response
    local tmpfile=$(mktemp)
    
    # Disable job control notifications (same as widget)
    setopt local_options no_monitor no_notify

    # Start the API query in background
    (_zsh_ai_execute_command "$query" > "$tmpfile" 2>/dev/null) &
    local pid=$!
    
    # Animate while waiting
    while kill -0 $pid 2>/dev/null; do
        echo -ne "\r${dots[$((frame % ${#dots[@]}))]} "
        ((frame++))
        sleep 0.1
    done
    
    # Clear the line
    echo -ne "\r\033[K"
    
    # Get the response and exit code
    wait $pid
    local exit_code=$?
    local cmd=$(cat "$tmpfile")
    rm -f "$tmpfile"
    
    if [[ $exit_code -eq 0 ]] && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
        # Put the command in the ZLE buffer (same as # method)
        print -z "$cmd"
    else
        # Show error with better visibility
        echo ""  # Blank line for spacing
        print -P "%F{red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%f"
        print -P "%F{red}❌ Failed to generate command%f"
        if [[ -n "$cmd" ]]; then
            print -P "%F{red}$cmd%f"
        fi
        print -P "%F{red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%f"
        echo ""  # Blank line for spacing
        return 1
    fi
}
