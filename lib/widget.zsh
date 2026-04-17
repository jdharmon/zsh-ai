#!/usr/bin/env zsh

# ZLE widget and key binding for zsh-ai

# State variables populated by preexec/precmd hooks
_ZSH_AI_LAST_CMD=""
_ZSH_AI_LAST_EXIT=0
_ZSH_AI_LAST_OUTPUT=""
_ZSH_AI_PREEXEC_RUNNING=0

# preexec: record command and optionally start output capture
_zsh_ai_preexec() {
    _ZSH_AI_LAST_CMD="$1"
    _ZSH_AI_PREEXEC_RUNNING=1
    if [[ "${ZSH_AI_CAPTURE_OUTPUT:-0}" == "1" ]]; then
        _ZSH_AI_CAPTURE_FILE=$(mktemp)
        exec {_ZSH_AI_STDOUT_FD}>&1 {_ZSH_AI_STDERR_FD}>&2
        exec 1> >(tee -a "$_ZSH_AI_CAPTURE_FILE") 2>&1
    fi
}

# precmd: save exit code and finish output capture when a real command ran
_zsh_ai_precmd() {
    local last_exit=$?
    if [[ "$_ZSH_AI_PREEXEC_RUNNING" == "1" ]]; then
        _ZSH_AI_LAST_EXIT=$last_exit
        _ZSH_AI_PREEXEC_RUNNING=0
        if [[ -n "${_ZSH_AI_CAPTURE_FILE:-}" ]]; then
            exec 1>&$_ZSH_AI_STDOUT_FD 2>&$_ZSH_AI_STDERR_FD
            exec {_ZSH_AI_STDOUT_FD}>&- {_ZSH_AI_STDERR_FD}>&-
            _ZSH_AI_LAST_OUTPUT=$(tail -50 "$_ZSH_AI_CAPTURE_FILE" 2>/dev/null)
            rm -f "$_ZSH_AI_CAPTURE_FILE"
            _ZSH_AI_CAPTURE_FILE=""
        fi
    fi
}

# Custom widget to intercept Enter key
_zsh_ai_accept_line() {
    # Check for ?? trigger (explain/fix last command)
    if [[ "$BUFFER" == '??' ]] || [[ "${BUFFER:0:3}" == '?? ' ]]; then
        local user_query=""
        [[ "${BUFFER:0:3}" == '?? ' ]] && user_query="${BUFFER:3}"

        local saved_buffer="$BUFFER"
        local dots=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local frame=0
        local tmpfile=$(mktemp)
        setopt local_options no_monitor no_notify

        (_zsh_ai_execute_explain "$_ZSH_AI_LAST_CMD" "$_ZSH_AI_LAST_EXIT" "$_ZSH_AI_LAST_OUTPUT" "$user_query" > "$tmpfile" 2>/dev/null) &
        local pid=$!

        while kill -0 $pid 2>/dev/null; do
            BUFFER="$saved_buffer ${dots[$((frame % ${#dots[@]}))]}"
            zle redisplay
            ((frame++))
            zle -R && sleep 0.1
        done

        local response=$(cat "$tmpfile")
        rm -f "$tmpfile"

        if [[ -z "$response" ]] || [[ "$response" == "Error:"* ]]; then
            echo ""
            print -P "%F{red}❌ Failed to get explanation%f"
            [[ -n "$response" ]] && print -P "%F{red}$response%f"
            echo ""
            BUFFER=""
            CURSOR=0
        elif [[ "$response" == 'FIX: '* ]]; then
            local rest="${response#FIX: }"
            local fixed_cmd explanation
            if [[ "$rest" == *' /// '* ]]; then
                fixed_cmd="${rest%% /// *}"
                explanation="${rest#* /// }"
            else
                fixed_cmd="$rest"
                explanation=""
            fi
            echo ""
            [[ -n "$explanation" ]] && print -P "%F{cyan}${explanation}%f"
            echo ""
            BUFFER="$fixed_cmd"
            CURSOR=$#BUFFER
        else
            echo ""
            print -P "%F{cyan}${response}%f"
            echo ""
            BUFFER=""
            CURSOR=0
        fi

        zle reset-prompt
        return
    fi

    # Check if the line starts with "# " (command generation trigger)
    if [[ "$BUFFER" =~ ^'# ' ]]; then
        # Check if buffer contains newlines (multiline command)
        if [[ "$BUFFER" == *$'\n'* ]]; then
            # Multiline command detected - execute normally without AI processing
            zle .accept-line
            return
        fi

        # Extract the query (remove the 2-char prefix)
        local query="${BUFFER:2}"

        # Add a loading indicator with animation
        local saved_buffer="$BUFFER"

        # Animation frames - rotating dots
        local dots=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

        local frame=0

        # Create a temp file for the response
        local tmpfile=$(mktemp)

        # Disable job control notifications
        setopt local_options no_monitor no_notify

        # Start the API query in background using the shared function
        # Only redirect stdout to tmpfile, let stderr go to /dev/null to avoid mixing error output
        (_zsh_ai_execute_command "$query" > "$tmpfile" 2>/dev/null) &
        local pid=$!

        # Animate while waiting
        while kill -0 $pid 2>/dev/null; do
            BUFFER="$saved_buffer ${dots[$((frame % ${#dots[@]}))]}"
            zle redisplay
            ((frame++))
            # Use zsh's built-in sleep equivalent
            zle -R && sleep 0.1
        done

        # Get the response
        local cmd=$(cat "$tmpfile")
        local exit_code=$?
        rm -f "$tmpfile"

        if [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
            # Simply replace the buffer with the generated command
            BUFFER="$cmd"

            # Move cursor to end of line
            CURSOR=$#BUFFER
        else
            # Show error - keep it visible
            echo ""  # New line for better visibility
            print -P "%F{red}❌ Failed to generate command%f"
            if [[ -n "$cmd" ]]; then
                print -P "%F{red}$cmd%f"
            fi
            echo ""  # Extra line for readability

            BUFFER="$saved_buffer"
            CURSOR=$#BUFFER

            # Sleep briefly to ensure error is visible before prompt redraws
            sleep 0.5
        fi

        # Redraw the prompt
        zle reset-prompt

    # Check if the line starts with "? " (general question trigger)
    elif [[ "${BUFFER:0:2}" == '? ' ]]; then
        # Check if buffer contains newlines (multiline command)
        if [[ "$BUFFER" == *$'\n'* ]]; then
            # Multiline command detected - execute normally without AI processing
            zle .accept-line
            return
        fi

        # Extract the query (remove the 2-char prefix)
        local query="${BUFFER:2}"

        # Add a loading indicator with animation
        local saved_buffer="$BUFFER"

        # Animation frames - rotating dots
        local dots=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

        local frame=0

        # Create a temp file for the response
        local tmpfile=$(mktemp)

        # Disable job control notifications
        setopt local_options no_monitor no_notify

        # Start the API query in background using the question function
        (_zsh_ai_execute_question "$query" > "$tmpfile" 2>/dev/null) &
        local pid=$!

        # Animate while waiting
        while kill -0 $pid 2>/dev/null; do
            BUFFER="$saved_buffer ${dots[$((frame % ${#dots[@]}))]}"
            zle redisplay
            ((frame++))
            # Use zsh's built-in sleep equivalent
            zle -R && sleep 0.1
        done

        # Get the response
        local answer=$(cat "$tmpfile")
        rm -f "$tmpfile"

        if [[ -z "$answer" ]] || [[ "$answer" == "Error:"* ]] || [[ "$answer" == "API Error:"* ]]; then
            echo ""
            print -P "%F{red}❌ Failed to get answer%f"
            [[ -n "$answer" ]] && print -P "%F{red}$answer%f"
            echo ""
        else
            echo ""
            print -P "%F{cyan}${answer}%f"
            echo ""
        fi

        BUFFER=""
        CURSOR=0

        # Redraw the prompt
        zle reset-prompt
    else
        # Normal command - execute as usual
        zle .accept-line
    fi
}

# Create the widget and bind it
# Uses precmd hook to defer registration until ZLE is fully initialized
# This fixes the issue where zle -N fails silently during plugin sourcing
_zsh_ai_init_widget() {
    _zsh_ai_do_init() {
        zle -N accept-line _zsh_ai_accept_line
        add-zsh-hook preexec _zsh_ai_preexec
        add-zsh-hook precmd _zsh_ai_precmd
        add-zsh-hook -d precmd _zsh_ai_do_init
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _zsh_ai_do_init
}
