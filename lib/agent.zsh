#!/usr/bin/env zsh

# Agent mode for zsh-ai
#
# A minimal agentic loop in the mini-swe-agent style: the model replies in
# plain text containing a single fenced ```tool ...``` block, we extract and
# run that command, then feed the combined stdout/stderr and exit code back as
# the next turn. A reply with no ```tool block is treated as the final answer.
#
# Execution is stateless: each command runs in a fresh subshell, so cd/env do
# not persist between steps. The system prompt tells the model to write
# self-contained commands. Every command is gated by confirm-each-command.

# Build the agent system prompt: protocol rules + repo context.
_zsh_ai_agent_system_prompt() {
    local context=$(_zsh_ai_build_context)
    cat <<'EOF'
You are a command-line agent operating a zsh shell to accomplish the user's task.

PROTOCOL:
- To run a command, reply with EXACTLY ONE fenced code block tagged `tool`:
  ```tool
  <a single zsh command>
  ```
- After each command you will receive its combined stdout/stderr and exit code.
- Keep going, one command per turn, until the task is done.
- When you are finished, reply in plain text with NO ```tool block. That text
  is your final answer to the user.

IMPORTANT - the shell is STATELESS between commands:
- Each command runs in a fresh shell; cd, exported variables, and shell state
  do NOT carry over to the next command.
- Combine dependent steps in one command with && or ;, use absolute paths, and
  re-cd within the same command when you need a specific directory.

Prefer non-interactive, non-destructive commands. Do not launch interactive
programs (vim, less, ssh, top); they cannot be driven and will time out.
EOF
    printf '\nContext:\n%s\n' "$context"
}

# Extract the last ```tool ...``` block from an assistant reply.
# Prints the command (no trailing newline). Empty output => no block => the
# reply is a final answer.
_zsh_ai_agent_extract_action() {
    local reply="$1"
    printf '%s' "$reply" | perl -0777 -ne '
        my $m;
        while (/```tool[ \t]*\r?\n(.*?)```/gs) { $m = $1 }
        if (defined $m) { $m =~ s/\s+\z//; print $m }
    '
}

# Confirm-each-command gate. Returns 0 to run, 1 to decline.
# Honors a session-wide "always" (set by answering "a").
_zsh_ai_agent_confirm() {
    local cmd="$1"

    if [[ "$_ZSH_AI_AGENT_ALWAYS" == "1" ]]; then
        return 0
    fi

    print -P "%F{yellow}▶ run this command?%f"
    print -r -- "    $cmd"
    print -Pn "%F{yellow}[y]es / [n]o / [a]lways: %f"

    local ans
    read -k 1 -u 0 ans
    echo ""

    case "$ans" in
        y|Y) return 0 ;;
        a|A) _ZSH_AI_AGENT_ALWAYS=1; return 0 ;;
        *)   return 1 ;;
    esac
}

# Run a single command in a fresh subshell (stateless), with a best-effort
# timeout and output truncation. Prints the live output to the user and stores
# the model-facing observation in $_zsh_ai_agent_run_result.
_zsh_ai_agent_run() {
    local cmd="$1"
    local timeout="${ZSH_AI_AGENT_TIMEOUT:-30}"
    local max_output="${ZSH_AI_AGENT_MAX_OUTPUT:-4096}"

    local tmpfile=$(mktemp)
    setopt local_options no_monitor no_notify no_bg_nice

    # Run in a background subshell so a watchdog can enforce the timeout without
    # depending on timeout(1)/gtimeout, which are not guaranteed on macOS.
    ( eval "$cmd" ) > "$tmpfile" 2>&1 &
    local pid=$!

    local tenths=0
    local limit=$(( timeout * 10 ))
    local timed_out=0
    while kill -0 $pid 2>/dev/null; do
        if (( tenths >= limit )); then
            kill -TERM $pid 2>/dev/null
            sleep 0.2
            kill -KILL $pid 2>/dev/null
            timed_out=1
            break
        fi
        sleep 0.1
        (( tenths++ ))
    done

    local rc
    if (( timed_out )); then
        wait $pid 2>/dev/null
        rc=124
    else
        wait $pid 2>/dev/null
        rc=$?
    fi

    local output=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if (( timed_out )); then
        output="${output}"$'\n'"[command timed out after ${timeout}s]"
    fi

    # Show the user what ran.
    if [[ -n "$output" ]]; then
        print -r -- "$output"
    fi
    print -P "%F{242}[exit ${rc}]%f"

    # Truncate for the model: keep head + tail.
    local model_output="$output"
    if (( ${#model_output} > max_output )); then
        local half=$(( max_output / 2 ))
        local elided=$(( ${#model_output} - max_output ))
        model_output="${model_output[1,$half]}"$'\n'"... [${elided} bytes elided] ..."$'\n'"${model_output[-$half,-1]}"
    fi

    _zsh_ai_agent_run_result=$(printf '<returncode>%d</returncode>\n<output>\n%s\n</output>' "$rc" "$model_output")
}

# The agent loop. Drives request -> tool calls -> final answer.
_zsh_ai_agent_loop() {
    local request="$1"
    local max_steps="${ZSH_AI_AGENT_MAX_STEPS:-15}"

    typeset -ga _zsh_ai_agent_roles=()
    typeset -ga _zsh_ai_agent_texts=()
    local _ZSH_AI_AGENT_ALWAYS=0
    local _zsh_ai_agent_run_result=""

    _zsh_ai_agent_roles+=("user")
    _zsh_ai_agent_texts+=("$request")

    # Declare loop-body locals once: re-running `local` on an existing name in
    # the same scope makes zsh echo its value.
    local step=0 reply action observation
    while (( step < max_steps )); do
        (( step++ ))

        reply=$(_zsh_ai_agent_query_gemini)
        if [[ -z "$reply" || "$reply" == "Error:"* || "$reply" == "API Error:"* ]]; then
            print -P "%F{red}❌ ${reply:-No response from model}%f"
            return 1
        fi

        action=$(_zsh_ai_agent_extract_action "$reply")

        if [[ -z "$action" ]]; then
            # No tool block => final answer.
            print -r -- "$reply"
            return 0
        fi

        _zsh_ai_agent_roles+=("model")
        _zsh_ai_agent_texts+=("$reply")

        if _zsh_ai_agent_confirm "$action"; then
            _zsh_ai_agent_run "$action"
            observation="$_zsh_ai_agent_run_result"
        else
            observation=$'<returncode>1</returncode>\n<output>\nUser declined to run this command. Propose a different approach or ask for guidance.\n</output>'
        fi

        _zsh_ai_agent_roles+=("user")
        _zsh_ai_agent_texts+=("$observation")
    done

    print -P "%F{yellow}⚠ Reached the step limit (${max_steps}). Stopping.%f"
    return 1
}
