#!/usr/bin/env zsh

# Load test helper
source "${0:A:h}/test_helper.zsh"

# Load required modules
source "$PLUGIN_DIR/lib/config.zsh"
source "$PLUGIN_DIR/lib/context.zsh"
source "$PLUGIN_DIR/lib/utils.zsh"
source "$PLUGIN_DIR/lib/agent.zsh"
source "$PLUGIN_DIR/lib/widget.zsh"

# Test functions

test_widget_initialization_registers_precmd_hook() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Track add-zsh-hook calls
    typeset -ga HOOK_CALLS
    HOOK_CALLS=()
    add-zsh-hook() {
        HOOK_CALLS+=("$1:$2:$3")
    }

    # Mock autoload
    autoload() {
        # No-op for testing
    }

    _zsh_ai_init_widget

    # Should have registered a precmd hook
    assert_equals "${HOOK_CALLS[1]}" "precmd:_zsh_ai_do_init:"

    teardown_test_env
}

test_widget_init_hook_registers_widget_and_removes_itself() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # Track add-zsh-hook calls
    typeset -ga HOOK_CALLS
    HOOK_CALLS=()
    add-zsh-hook() {
        HOOK_CALLS+=("$1:$2:$3")
    }

    # Mock autoload
    autoload() {
        # No-op for testing
    }

    # Mock ZLE functions
    typeset -gA MOCKED_WIDGETS
    zle() {
        case "$1" in
            "-N")
                MOCKED_WIDGETS[$2]="$3"
                ;;
        esac
    }

    # Initialize widget (registers the hook)
    _zsh_ai_init_widget

    # Simulate the precmd hook being called
    _zsh_ai_do_init

    # Should have registered the widget
    assert_equals "${MOCKED_WIDGETS[accept-line]}" "_zsh_ai_accept_line"

    # Should have registered the preexec/precmd hooks used for the ?? feature
    assert_contains "${HOOK_CALLS[*]}" "preexec:_zsh_ai_preexec:"
    assert_contains "${HOOK_CALLS[*]}" "precmd:_zsh_ai_precmd:"

    # Should have removed its own init hook (last call, with -d flag)
    assert_equals "${HOOK_CALLS[-1]}" "-d:precmd:_zsh_ai_do_init"

    teardown_test_env
}

test_normal_commands_execute_without_ai_processing() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    local ACCEPT_LINE_CALLED=0
    zle() {
        case "$1" in
            ".accept-line")
                ACCEPT_LINE_CALLED=1
                ;;
        esac
    }
    
    BUFFER="ls -la"
    _zsh_ai_accept_line
    
    assert_equals "$ACCEPT_LINE_CALLED" "1"
    
    teardown_test_env
}

test_multiline_ai_commands_execute_without_processing() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    local ACCEPT_LINE_CALLED=0
    zle() {
        case "$1" in
            ".accept-line")
                ACCEPT_LINE_CALLED=1
                ;;
        esac
    }
    
    BUFFER="# list files
and show details"
    _zsh_ai_accept_line
    
    assert_equals "$ACCEPT_LINE_CALLED" "1"
    
    teardown_test_env
}

test_ai_commands_starting_with_hash_are_processed() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Mock the query function
    _zsh_ai_query() {
        echo "ls -la"
    }
    
    # Mock kill to simulate process completion
    mock_command "kill" "" 1
    
    # Mock mktemp and cat
    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "ls -la" 0
    mock_command "rm" "" 0
    
    # Mock ZLE functions
    local RESET_PROMPT_CALLED=0
    zle() {
        case "$1" in
            "reset-prompt")
                RESET_PROMPT_CALLED=1
                ;;
        esac
    }
    
    BUFFER="# list all files"
    CURSOR=0
    
    _zsh_ai_accept_line
    
    # Buffer should be replaced with command
    assert_equals "$BUFFER" "ls -la"
    assert_equals "$CURSOR" "6"
    assert_equals "$RESET_PROMPT_CALLED" "1"
    
    teardown_test_env
}

test_handles_api_errors_gracefully() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Mock the query function to return error
    _zsh_ai_query() {
        echo "Error: API connection failed"
    }
    
    # Mock kill to simulate process completion
    mock_command "kill" "" 1
    
    # Mock mktemp and cat
    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "Error: API connection failed" 0
    mock_command "rm" "" 0
    
    # Mock print to capture output
    local printed_output=""
    print() {
        printed_output="$printed_output$@\n"
    }
    
    # Mock ZLE functions
    zle() {
        case "$1" in
            "reset-prompt")
                ;;
        esac
    }
    
    BUFFER="# invalid query"
    
    _zsh_ai_accept_line
    
    # Buffer should be restored on error so the user can edit the query
    assert_equals "$BUFFER" "# invalid query"
    assert_contains "$printed_output" "Failed to generate command"
    assert_contains "$printed_output" "API connection failed"
    
    teardown_test_env
}

test_shows_loading_animation_during_api_call() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Mock the query function
    _zsh_ai_query() {
        echo "pwd"
    }
    
    # Mock kill to simulate running process then completion
    local kill_count=0
    kill() {
        kill_count=$((kill_count + 1))
        if [[ $kill_count -le 2 ]]; then
            return 0  # Process still running
        else
            return 1  # Process completed
        fi
    }
    
    # Mock mktemp and cat
    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "pwd" 0
    mock_command "rm" "" 0
    
    # Mock ZLE functions
    local REDISPLAY_COUNT=0
    zle() {
        case "$1" in
            "redisplay"|"-R")
                REDISPLAY_COUNT=$((REDISPLAY_COUNT + 1))
                ;;
            "reset-prompt")
                ;;
        esac
    }
    
    # Mock sleep
    mock_command "sleep" "" 0
    
    BUFFER="# show current directory"
    
    _zsh_ai_accept_line
    
    # Should have animated
    assert_greater_than "$REDISPLAY_COUNT" "0"
    
    teardown_test_env
}

test_preserves_original_buffer_during_animation() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Mock the query function
    _zsh_ai_query() {
        echo "git status"
    }
    
    # Mock kill to simulate process completion
    mock_command "kill" "" 1
    
    # Mock mktemp and cat
    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "git status" 0
    mock_command "rm" "" 0
    
    # Mock ZLE functions
    zle() {
        case "$1" in
            "reset-prompt")
                ;;
        esac
    }
    
    local original_buffer="# check git status"
    BUFFER="$original_buffer"
    
    _zsh_ai_accept_line
    
    # Final buffer should be the command
    assert_equals "$BUFFER" "git status"
    
    teardown_test_env
}

test_handles_empty_api_response() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Mock the query function to return empty
    _zsh_ai_query() {
        echo ""
    }
    
    # Mock kill to simulate process completion
    mock_command "kill" "" 1
    
    # Mock mktemp and cat
    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "" 0
    mock_command "rm" "" 0
    
    # Mock print to capture output
    local printed_output=""
    print() {
        printed_output="$printed_output$@\n"
    }
    
    # Mock ZLE functions
    zle() {
        case "$1" in
            "reset-prompt")
                ;;
        esac
    }
    
    BUFFER="# empty response"
    
    _zsh_ai_accept_line
    
    # Buffer should be restored on error so the user can edit the query
    assert_equals "$BUFFER" "# empty response"
    assert_contains "$printed_output" "Failed to generate command"
    
    teardown_test_env
}

test_uses_temporary_file_for_api_response() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Return a predictable temp path
    local temp_file="/tmp/test.tmp"
    mktemp() {
        echo "$temp_file"
    }
    
    # Mock cat and rm
    mock_command "cat" "echo 'Hello World'" 0
    mock_command "rm" "" 0
    
    # Mock the query function
    _zsh_ai_query() {
        echo "echo 'Hello World'"
    }
    
    # Mock kill to simulate process completion
    mock_command "kill" "" 1
    
    # Mock ZLE functions
    zle() {
        case "$1" in
            "reset-prompt")
                ;;
        esac
    }
    
    BUFFER="# say hello"
    
    _zsh_ai_accept_line
    
    assert_called "rm" "1"
    
    teardown_test_env
}

test_handles_commands_with_special_characters() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Mock the query function
    _zsh_ai_query() {
        echo "echo 'Hello, World!'"
    }
    
    # Mock kill to simulate process completion
    mock_command "kill" "" 1
    
    # Mock mktemp and cat
    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "echo 'Hello, World!'" 0
    mock_command "rm" "" 0
    
    # Mock ZLE functions
    zle() {
        case "$1" in
            "reset-prompt")
                ;;
        esac
    }
    
    BUFFER="# print greeting"
    
    _zsh_ai_accept_line
    
    assert_equals "$BUFFER" "echo 'Hello, World!'"
    
    teardown_test_env
}

test_init_widget_skips_registration_when_disabled() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    export ZSH_AI_COMMENT_HOOK="false"

    # Track add-zsh-hook calls
    typeset -ga HOOK_CALLS
    HOOK_CALLS=()
    add-zsh-hook() {
        HOOK_CALLS+=("$1:$2:$3")
    }
    autoload() { :; }

    _zsh_ai_init_widget

    # No precmd hook should have been registered
    assert_equals "${#HOOK_CALLS[@]}" "0"

    unset ZSH_AI_COMMENT_HOOK
    teardown_test_env
}

test_custom_trigger_is_processed() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    export ZSH_AI_TRIGGER=",,"

    # Echo back the query so we can verify the trigger prefix was stripped.
    # The widget runs this in a background subshell and reads its stdout from a
    # temp file, so we rely on a real temp file rather than mocking cat/mktemp.
    _zsh_ai_execute_command() {
        printf "query:%s" "$1"
    }

    mock_command "kill" "" 1

    local RESET_PROMPT_CALLED=0
    zle() {
        case "$1" in
            "reset-prompt") RESET_PROMPT_CALLED=1 ;;
        esac
    }

    BUFFER=",,list all files"
    CURSOR=0

    _zsh_ai_accept_line

    # Buffer holds the command produced from the query with the ",," stripped
    assert_equals "$BUFFER" "query:list all files"
    assert_equals "$RESET_PROMPT_CALLED" "1"

    export ZSH_AI_TRIGGER="# "
    teardown_test_env
}

test_default_hash_ignored_when_trigger_changed() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    export ZSH_AI_TRIGGER=",,"

    local ACCEPT_LINE_CALLED=0
    zle() {
        case "$1" in
            ".accept-line") ACCEPT_LINE_CALLED=1 ;;
        esac
    }

    # With a custom trigger, a leading "# " is a normal comment, not a query
    BUFFER="# list files"
    _zsh_ai_accept_line

    assert_equals "$ACCEPT_LINE_CALLED" "1"

    export ZSH_AI_TRIGGER="# "
    teardown_test_env
}

test_double_question_replaces_buffer_with_fix() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # ?? requires a tmux session; set a fake value to pass the guard
    export TMUX="fake-session"
    _ZSH_AI_LAST_CMD="git pussh origin main"
    _ZSH_AI_LAST_EXIT=128
    _ZSH_AI_LAST_OUTPUT=""

    mock_command "kill" "" 1

    mktemp() { echo "/tmp/test.tmp" }
    mock_command "cat" 'FIX: git push origin main /// You had a typo: "pussh" should be "push".' 0
    mock_command "rm" "" 0

    local RESET_PROMPT_CALLED=0
    zle() {
        case "$1" in
            "reset-prompt") RESET_PROMPT_CALLED=1 ;;
        esac
    }

    BUFFER="??"
    CURSOR=0

    _zsh_ai_accept_line

    assert_equals "$BUFFER" "git push origin main"
    assert_equals "$CURSOR" "20"
    assert_equals "$RESET_PROMPT_CALLED" "1"

    teardown_test_env
}

test_double_question_with_query_processes_explanation() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    export TMUX="fake-session"
    _ZSH_AI_LAST_CMD="ls /nonexistent"
    _ZSH_AI_LAST_EXIT=1
    _ZSH_AI_LAST_OUTPUT=""

    mock_command "kill" "" 1

    mktemp() { echo "/tmp/test.tmp" }
    mock_command "cat" "The directory /nonexistent does not exist on this system." 0
    mock_command "rm" "" 0

    local printed_output=""
    print() { printed_output="$printed_output$@\n" }

    zle() {
        case "$1" in
            "reset-prompt") ;;
        esac
    }

    BUFFER="?? why did this fail"
    CURSOR=0

    _zsh_ai_accept_line

    assert_equals "$BUFFER" ""
    assert_contains "$printed_output" "does not exist"

    teardown_test_env
}

test_double_question_clears_buffer_when_no_fix() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    export TMUX="fake-session"
    _ZSH_AI_LAST_CMD="rm /etc/passwd"
    _ZSH_AI_LAST_EXIT=1
    _ZSH_AI_LAST_OUTPUT=""

    mock_command "kill" "" 1

    mktemp() { echo "/tmp/test.tmp" }
    mock_command "cat" "Permission denied: you do not have write access to /etc/passwd." 0
    mock_command "rm" "" 0

    zle() {
        case "$1" in
            "reset-prompt") ;;
        esac
    }

    BUFFER="??"

    _zsh_ai_accept_line

    assert_equals "$BUFFER" ""

    teardown_test_env
}

test_double_question_handles_no_previous_command() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    export TMUX="fake-session"
    _ZSH_AI_LAST_CMD=""
    _ZSH_AI_LAST_EXIT=0
    _ZSH_AI_LAST_OUTPUT=""

    mock_command "kill" "" 1

    mktemp() { echo "/tmp/test.tmp" }
    mock_command "cat" "Error: No previous command found" 0
    mock_command "rm" "" 0

    local printed_output=""
    print() { printed_output="$printed_output$@\n" }

    zle() {
        case "$1" in
            "reset-prompt") ;;
        esac
    }

    BUFFER="??"

    _zsh_ai_accept_line

    assert_equals "$BUFFER" ""
    assert_contains "$printed_output" "Failed to get explanation"

    teardown_test_env
}

test_preexec_records_last_command() {
    setup_test_env

    _ZSH_AI_LAST_CMD=""
    _ZSH_AI_PREEXEC_RUNNING=0

    _zsh_ai_preexec "git status"

    assert_equals "$_ZSH_AI_LAST_CMD" "git status"
    assert_equals "$_ZSH_AI_PREEXEC_RUNNING" "1"

    teardown_test_env
}

test_precmd_saves_exit_code_when_preexec_ran() {
    setup_test_env

    _ZSH_AI_PREEXEC_RUNNING=1
    _ZSH_AI_LAST_EXIT=0

    # Simulate a failed command by having $? = 1 via a subshell trick
    # We call _zsh_ai_precmd after a failing command
    (exit 42)
    _zsh_ai_precmd

    assert_equals "$_ZSH_AI_LAST_EXIT" "42"
    assert_equals "$_ZSH_AI_PREEXEC_RUNNING" "0"

    teardown_test_env
}

test_precmd_does_not_update_exit_code_without_preexec() {
    setup_test_env

    _ZSH_AI_PREEXEC_RUNNING=0
    _ZSH_AI_LAST_EXIT=99

    (exit 1)
    _zsh_ai_precmd

    # Should not update since no preexec ran
    assert_equals "$_ZSH_AI_LAST_EXIT" "99"

    teardown_test_env
}

test_ai_commands_starting_with_question_are_processed() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _zsh_ai_query() {
        echo "A file lists directory contents."
    }

    mock_command "kill" "" 1

    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "A file lists directory contents." 0
    mock_command "rm" "" 0

    local printed_output=""
    print() {
        printed_output="$printed_output$@\n"
    }

    local RESET_PROMPT_CALLED=0
    zle() {
        case "$1" in
            "reset-prompt")
                RESET_PROMPT_CALLED=1
                ;;
        esac
    }

    BUFFER="? list all files"
    CURSOR=0

    _zsh_ai_accept_line

    # Buffer should be cleared (not replaced with a command)
    assert_equals "$BUFFER" ""
    assert_equals "$CURSOR" "0"
    assert_equals "$RESET_PROMPT_CALLED" "1"
    assert_contains "$printed_output" "A file lists directory contents."

    teardown_test_env
}

test_multiline_question_commands_execute_without_processing() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    local ACCEPT_LINE_CALLED=0
    zle() {
        case "$1" in
            ".accept-line")
                ACCEPT_LINE_CALLED=1
                ;;
        esac
    }

    BUFFER="? list files
and show details"
    _zsh_ai_accept_line

    assert_equals "$ACCEPT_LINE_CALLED" "1"

    teardown_test_env
}

test_question_prefix_buffer_cleared_on_error() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    _zsh_ai_query() {
        echo "Error: API connection failed"
    }

    mock_command "kill" "" 1

    mktemp() {
        echo "/tmp/test.tmp"
    }
    mock_command "cat" "Error: API connection failed" 0
    mock_command "rm" "" 0

    local printed_output=""
    print() {
        printed_output="$printed_output$@\n"
    }

    zle() {
        case "$1" in
            "reset-prompt")
                ;;
        esac
    }

    BUFFER="? invalid query"

    _zsh_ai_accept_line

    # Buffer must be cleared (not restored) to avoid ZSH glob expansion
    assert_equals "$BUFFER" ""
    assert_contains "$printed_output" "Failed to get answer"

    teardown_test_env
}

test_agent_trigger_runs_loop_with_query() {
    setup_test_env
    export ZSH_AI_PROVIDER="gemini"
    export GEMINI_API_KEY="test-key"

    # Capture how the loop is invoked, and keep it from doing real work.
    local LOOP_QUERY="__unset__"
    _zsh_ai_agent_available() { return 0; }
    _zsh_ai_agent_loop() { LOOP_QUERY="$1"; }
    # Silence the in-widget newline print.
    functions[print]=': '

    local RESET_PROMPT_CALLED=0
    zle() {
        case "$1" in
            "reset-prompt") RESET_PROMPT_CALLED=1 ;;
        esac
    }

    BUFFER="#! find large files"
    CURSOR=0
    _zsh_ai_accept_line

    unfunction print 2>/dev/null

    # The loop ran with the trigger stripped, the buffer was cleared, and the
    # internal "zsh-ai --agent" wrapper was never placed in the buffer.
    assert_equals "$LOOP_QUERY" "find large files"
    assert_equals "$BUFFER" ""
    assert_equals "$RESET_PROMPT_CALLED" "1"

    source "$PLUGIN_DIR/lib/agent.zsh"
    teardown_test_env
}

test_agent_trigger_empty_query_is_plain_line() {
    setup_test_env
    export ZSH_AI_PROVIDER="gemini"
    export GEMINI_API_KEY="test-key"

    local LOOP_CALLED=0
    _zsh_ai_agent_loop() { LOOP_CALLED=1; }

    local ACCEPT_LINE_CALLED=0
    zle() {
        case "$1" in
            ".accept-line") ACCEPT_LINE_CALLED=1 ;;
        esac
    }

    # "#! " with no query is just a comment line, not an agent launch.
    BUFFER="#! "
    _zsh_ai_accept_line

    assert_equals "$LOOP_CALLED" "0"
    assert_equals "$ACCEPT_LINE_CALLED" "1"

    source "$PLUGIN_DIR/lib/agent.zsh"
    teardown_test_env
}

# Run tests
echo "Running widget tests..."
test_mux_backend_detects_tmux() {
    setup_test_env
    export TMUX="fake-session"
    assert_equals "$(_zsh_ai_mux_backend)" "tmux"
    teardown_test_env
}

test_mux_backend_detects_herdr() {
    setup_test_env
    unset TMUX
    export HERDR_ENV="1"
    export HERDR_PANE_ID="w3:p7"
    assert_equals "$(_zsh_ai_mux_backend)" "herdr"
    teardown_test_env
}

test_mux_backend_prefers_tmux_over_herdr() {
    setup_test_env
    export TMUX="fake-session"
    export HERDR_ENV="1"
    export HERDR_PANE_ID="w3:p7"
    assert_equals "$(_zsh_ai_mux_backend)" "tmux"
    teardown_test_env
}

test_mux_backend_empty_when_neither() {
    setup_test_env
    unset TMUX HERDR_ENV HERDR_PANE_ID
    assert_equals "$(_zsh_ai_mux_backend)" ""
    teardown_test_env
}

test_herdr_scroll_parses_metric() {
    setup_test_env
    export HERDR_PANE_ID="w3:p7"
    herdr() {
        [[ "$1 $2" == "pane get" ]] && \
            echo '{"id":"cli:pane:get","result":{"pane":{"pane_id":"w3:p7","scroll":{"max_offset_from_bottom":139,"offset_from_bottom":0,"viewport_rows":45}},"type":"pane_info"}}'
    }
    # Uses jq when present, else perl; both must yield the same result
    assert_equals "$(_zsh_ai_herdr_scroll)" "139 45"
    unfunction herdr
    teardown_test_env
}

test_herdr_scroll_perl_fallback_when_no_jq() {
    setup_test_env
    export HERDR_PANE_ID="w3:p7"
    herdr() {
        echo '{"result":{"pane":{"scroll":{"max_offset_from_bottom":139,"offset_from_bottom":0,"viewport_rows":45}}}}'
    }
    # Force the perl branch by making `command -v jq` fail (jq stays optional)
    command() {
        [[ "$1" == "-v" && "$2" == "jq" ]] && return 1
        builtin command "$@"
    }
    assert_equals "$(_zsh_ai_herdr_scroll)" "139 45"
    unfunction herdr
    unfunction command
    teardown_test_env
}

test_capture_output_herdr_reads_delta_window() {
    setup_test_env
    unset TMUX
    export HERDR_ENV="1"
    export HERDR_PANE_ID="w3:p7"
    herdr() {
        if [[ "$1 $2" == "pane get" ]]; then
            echo '{"result":{"pane":{"scroll":{"max_offset_from_bottom":139,"offset_from_bottom":0,"viewport_rows":45}}}}'
        elif [[ "$1 $2" == "pane read" ]]; then
            printf 'cat: foo.txt: No such file or directory\n'
        fi
    }
    local out="$(_zsh_ai_capture_output 100)"
    assert_contains "$out" "No such file or directory"
    unfunction herdr
    teardown_test_env
}

test_capture_output_herdr_falls_back_when_no_metric() {
    setup_test_env
    unset TMUX
    export HERDR_ENV="1"
    export HERDR_PANE_ID="w3:p7"
    herdr() {
        # pane get returns an error (no scroll) -> metric empty -> fixed window
        if [[ "$1 $2" == "pane get" ]]; then
            echo '{"error":{"code":"pane_not_found","message":"x"}}'
        elif [[ "$1 $2" == "pane read" ]]; then
            printf 'fallback output line\n'
        fi
    }
    local out="$(_zsh_ai_capture_output 0)"
    assert_contains "$out" "fallback output line"
    unfunction herdr
    teardown_test_env
}

test_double_question_works_under_herdr() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    # herdr pane instead of tmux passes the ?? guard
    unset TMUX
    export HERDR_ENV="1"
    export HERDR_PANE_ID="w3:p7"
    _ZSH_AI_LAST_CMD="git pussh origin main"
    _ZSH_AI_LAST_EXIT=128
    _ZSH_AI_LAST_OUTPUT=""

    mock_command "kill" "" 1
    mktemp() { echo "/tmp/test.tmp" }
    mock_command "cat" 'FIX: git push origin main /// You had a typo: "pussh" should be "push".' 0
    mock_command "rm" "" 0

    local RESET_PROMPT_CALLED=0
    zle() {
        case "$1" in
            "reset-prompt") RESET_PROMPT_CALLED=1 ;;
        esac
    }

    BUFFER="??"
    CURSOR=0
    _zsh_ai_accept_line

    assert_equals "$BUFFER" "git push origin main"
    assert_equals "$RESET_PROMPT_CALLED" "1"

    teardown_test_env
}

test_double_question_requires_a_multiplexer() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

    unset TMUX HERDR_ENV HERDR_PANE_ID
    _ZSH_AI_LAST_CMD="git status"

    local printed_output=""
    print() { printed_output="$printed_output$@\n" }
    local EXPLAIN_CALLED=0
    _zsh_ai_execute_explain() { EXPLAIN_CALLED=1 }
    zle() { : }

    BUFFER="??"
    _zsh_ai_accept_line

    assert_equals "$BUFFER" ""
    assert_equals "$EXPLAIN_CALLED" "0"
    assert_contains "$printed_output" "requires tmux or herdr"

    teardown_test_env
}

run_test "Widget initialization registers precmd hook" test_widget_initialization_registers_precmd_hook
run_test "Widget init hook registers widget and removes itself" test_widget_init_hook_registers_widget_and_removes_itself
run_test "Normal commands execute without AI processing" test_normal_commands_execute_without_ai_processing
run_test "Multiline AI commands execute without processing" test_multiline_ai_commands_execute_without_processing
run_test "AI commands starting with # are processed" test_ai_commands_starting_with_hash_are_processed
run_test "Handles API errors gracefully" test_handles_api_errors_gracefully
run_test "Shows loading animation during API call" test_shows_loading_animation_during_api_call
run_test "Preserves original buffer during animation" test_preserves_original_buffer_during_animation
run_test "Handles empty API response" test_handles_empty_api_response
run_test "Uses temporary file for API response" test_uses_temporary_file_for_api_response
run_test "Handles commands with special characters" test_handles_commands_with_special_characters
run_test "Init widget skips registration when disabled" test_init_widget_skips_registration_when_disabled
run_test "Custom trigger is processed" test_custom_trigger_is_processed
run_test "Default '# ' ignored when trigger changed" test_default_hash_ignored_when_trigger_changed
run_test "AI commands starting with ? are processed" test_ai_commands_starting_with_question_are_processed
run_test "Multiline ? commands execute without processing" test_multiline_question_commands_execute_without_processing
run_test "? prefix buffer cleared on error (avoids glob expansion)" test_question_prefix_buffer_cleared_on_error
run_test "?? replaces buffer with fixed command" test_double_question_replaces_buffer_with_fix
run_test "?? with query prints explanation" test_double_question_with_query_processes_explanation
run_test "?? clears buffer when no fix available" test_double_question_clears_buffer_when_no_fix
run_test "?? handles missing previous command" test_double_question_handles_no_previous_command
run_test "preexec records last command" test_preexec_records_last_command
run_test "precmd saves exit code when preexec ran" test_precmd_saves_exit_code_when_preexec_ran
run_test "precmd skips update when no preexec ran" test_precmd_does_not_update_exit_code_without_preexec
run_test "mux backend detects tmux" test_mux_backend_detects_tmux
run_test "mux backend detects herdr" test_mux_backend_detects_herdr
run_test "mux backend prefers tmux over herdr" test_mux_backend_prefers_tmux_over_herdr
run_test "mux backend empty when neither" test_mux_backend_empty_when_neither
run_test "herdr scroll parses metric" test_herdr_scroll_parses_metric
run_test "herdr scroll perl fallback when no jq" test_herdr_scroll_perl_fallback_when_no_jq
run_test "capture output herdr reads delta window" test_capture_output_herdr_reads_delta_window
run_test "capture output herdr falls back when no metric" test_capture_output_herdr_falls_back_when_no_metric
run_test "?? works under herdr" test_double_question_works_under_herdr
run_test "?? requires tmux or herdr" test_double_question_requires_a_multiplexer
run_test "Agent trigger runs loop with stripped query" test_agent_trigger_runs_loop_with_query
run_test "Agent trigger with empty query is a plain line" test_agent_trigger_empty_query_is_plain_line
finish_tests
