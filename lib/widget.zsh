#!/usr/bin/env zsh

# ZLE widget and key binding for zsh-ai

# State variables populated by preexec/precmd hooks
_ZSH_AI_LAST_CMD=""
_ZSH_AI_LAST_EXIT=0
_ZSH_AI_LAST_OUTPUT=""
_ZSH_AI_PREEXEC_RUNNING=0
_ZSH_AI_CAPTURE_BEFORE=0

# Echo "<max_offset_from_bottom> <viewport_rows>" for the current herdr pane.
# max_offset_from_bottom is the scrollback-depth analog of tmux's #{history_size};
# viewport_rows is the #{pane_height} analog. Parse with jq when present, else perl
# (jq stays optional; perl is a hard dependency).
_zsh_ai_herdr_scroll() {
    local pane="${HERDR_PANE_ID:-$HERDR_ACTIVE_PANE_ID}"
    local json
    json=$(herdr pane get "$pane" 2>/dev/null) || return 1
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r '.result.pane.scroll | "\(.max_offset_from_bottom) \(.viewport_rows)"' 2>/dev/null
    else
        echo "$json" | perl -ne 'print "$1 $2\n" if /"max_offset_from_bottom":(\d+).*?"viewport_rows":(\d+)/s'
    fi
}

# preexec: snapshot the scrollback baseline for the active capture backend
_zsh_ai_capture_baseline() {
    case "$(_zsh_ai_mux_backend)" in
        tmux)  tmux display-message -p '#{history_size}' 2>/dev/null ;;
        herdr) _zsh_ai_herdr_scroll 2>/dev/null | cut -d' ' -f1 ;;
    esac
}

# precmd: return up to ~50 lines of the last command's output for the active backend.
# $1 is the baseline captured in preexec.
_zsh_ai_capture_output() {
    local before="$1" n
    case "$(_zsh_ai_mux_backend)" in
        tmux)
            local after height
            after=$(tmux display-message -p '#{history_size}' 2>/dev/null)
            height=$(tmux display-message -p '#{pane_height}' 2>/dev/null)
            n=$(( after - before + height ))
            tmux capture-pane -p -S -${n} 2>/dev/null | head -50
            ;;
        herdr)
            local metric after rows
            metric=$(_zsh_ai_herdr_scroll 2>/dev/null)
            after=${metric%% *}; rows=${metric##* }
            if [[ -n "$after" && -n "$rows" && "$after" == <-> && "$rows" == <-> ]]; then
                n=$(( after - before + rows ))
                (( n < rows )) && n=$rows      # saturation floor -> visible screen
                (( n > 200 )) && n=200         # token-budget ceiling
                (( n <= 0 )) && n=50
            else
                n=50                            # metric unavailable -> fixed window
            fi
            herdr pane read "${HERDR_PANE_ID:-$HERDR_ACTIVE_PANE_ID}" --source recent --lines "$n" --format text 2>/dev/null | tail -200
            ;;
    esac
}

# preexec: record command and snapshot the scrollback baseline
_zsh_ai_preexec() {
    _ZSH_AI_LAST_CMD="$1"
    _ZSH_AI_PREEXEC_RUNNING=1
    _ZSH_AI_CAPTURE_BEFORE=$(_zsh_ai_capture_baseline)
}

# precmd: save exit code and capture output from the active backend's pane buffer
_zsh_ai_precmd() {
    local last_exit=$?
    if [[ "$_ZSH_AI_PREEXEC_RUNNING" == "1" ]]; then
        _ZSH_AI_LAST_EXIT=$last_exit
        _ZSH_AI_PREEXEC_RUNNING=0
        _ZSH_AI_LAST_OUTPUT=$(_zsh_ai_capture_output "$_ZSH_AI_CAPTURE_BEFORE")
    fi
}

# Custom widget to intercept Enter key
_zsh_ai_accept_line() {
    local trigger="${ZSH_AI_TRIGGER:-# }"

    # Check for ?? trigger (explain/fix last command)
    if [[ "$BUFFER" == '??' ]] || [[ "${BUFFER:0:3}" == '?? ' ]]; then
        if [[ -z "$(_zsh_ai_mux_backend)" ]]; then
            echo ""
            print -P "%F{yellow}?? requires tmux or herdr — run your shell inside a tmux or herdr session to use this feature.%f"
            echo ""
            BUFFER=""
            CURSOR=0
            zle reset-prompt
            return
        fi

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

    # Check if the line starts with the configured trigger (command generation trigger)
    if [[ "$BUFFER" == "$trigger"* ]]; then
        # Check if buffer contains newlines (multiline command)
        if [[ "$BUFFER" == *$'\n'* ]]; then
            # Multiline command detected - execute normally without AI processing
            zle .accept-line
            return
        fi

        # Extract the query (remove the trigger prefix)
        local query="${BUFFER#"$trigger"}"

        # Add a loading indicator with animation
        local saved_buffer="$BUFFER"

        # Animation frames - rotating dots
        local dots=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

        local frame=0

        # Create a temp file for the response
        local tmpfile=$(mktemp)

        # Disable job control notifications
        setopt local_options no_monitor no_notify no_bg_nice

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

        # Reap the background job so it doesn't linger in the job table
        wait $pid 2>/dev/null
        local exit_code=$?

        # Get the response
        local cmd=$(cat "$tmpfile")
        rm -f "$tmpfile"

        if [[ $exit_code -eq 0 ]] && [[ -n "$cmd" ]] && [[ "$cmd" != "Error:"* ]] && [[ "$cmd" != "API Error:"* ]]; then
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

        # Detect color support
        local use_colors=0
        local _n_colors
        _n_colors=$(tput colors 2>/dev/null)
        [[ -n "$_n_colors" ]] && [[ $_n_colors -ge 8 ]] && use_colors=1

        # Create a temp file for the response
        local tmpfile=$(mktemp)

        # Disable job control notifications
        setopt local_options no_monitor no_notify

        # Start the API query in background using the question function
        (_zsh_ai_execute_question "$query" "$use_colors" > "$tmpfile" 2>/dev/null) &
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
            print -- "$answer"
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
    # Respect the toggle: when disabled, never intercept accept-line so the
    # inline trigger (default "# ") behaves like a normal shell comment.
    _zsh_ai_comment_hook_enabled || return

    _zsh_ai_do_init() {
        zle -N accept-line _zsh_ai_accept_line
        add-zsh-hook preexec _zsh_ai_preexec
        add-zsh-hook precmd _zsh_ai_precmd
        add-zsh-hook -d precmd _zsh_ai_do_init
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _zsh_ai_do_init
}
