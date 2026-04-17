#!/usr/bin/env zsh

# Load test helper
source "${0:A:h}/test_helper.zsh"

# Load required modules
source "$PLUGIN_DIR/lib/config.zsh"
source "$PLUGIN_DIR/lib/context.zsh"
source "$PLUGIN_DIR/lib/utils.zsh"
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

    # Should have removed the hook (second call with -d flag)
    assert_equals "${HOOK_CALLS[2]}" "-d:precmd:_zsh_ai_do_init"

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
    
    # Buffer should be cleared on error
    assert_equals "$BUFFER" ""
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
    
    # Buffer should be cleared
    assert_equals "$BUFFER" ""
    assert_contains "$printed_output" "Failed to generate command"
    
    teardown_test_env
}

test_uses_temporary_file_for_api_response() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"
    
    # Track mktemp calls
    local mktemp_called=0
    local temp_file="/tmp/test.tmp"
    mktemp() {
        mktemp_called=1
        echo "$temp_file"
    }
    
    # Mock cat and rm
    mock_command "cat" "echo 'Hello World'" 0
    local rm_called=0
    rm() {
        rm_called=1
    }
    
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
    
    assert_equals "$mktemp_called" "1"
    assert_equals "$rm_called" "1"
    
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

test_double_question_replaces_buffer_with_fix() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="test-key"

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

# Run tests
echo "Running widget tests..."
test_widget_initialization_registers_precmd_hook && echo "✓ Widget initialization registers precmd hook"
test_widget_init_hook_registers_widget_and_removes_itself && echo "✓ Widget init hook registers widget and removes itself"
test_normal_commands_execute_without_ai_processing && echo "✓ Normal commands execute without AI processing"
test_multiline_ai_commands_execute_without_processing && echo "✓ Multiline AI commands execute without processing"
test_ai_commands_starting_with_hash_are_processed && echo "✓ AI commands starting with # are processed"
test_handles_api_errors_gracefully && echo "✓ Handles API errors gracefully"
test_shows_loading_animation_during_api_call && echo "✓ Shows loading animation during API call"
test_preserves_original_buffer_during_animation && echo "✓ Preserves original buffer during animation"
test_handles_empty_api_response && echo "✓ Handles empty API response"
test_uses_temporary_file_for_api_response && echo "✓ Uses temporary file for API response"
test_handles_commands_with_special_characters && echo "✓ Handles commands with special characters"
test_ai_commands_starting_with_question_are_processed && echo "✓ AI commands starting with ? are processed"
test_multiline_question_commands_execute_without_processing && echo "✓ Multiline ? commands execute without processing"
test_question_prefix_buffer_cleared_on_error && echo "✓ ? prefix buffer cleared on error (avoids glob expansion)"
test_double_question_replaces_buffer_with_fix && echo "✓ ?? replaces buffer with fixed command"
test_double_question_with_query_processes_explanation && echo "✓ ?? with query prints explanation"
test_double_question_clears_buffer_when_no_fix && echo "✓ ?? clears buffer when no fix available"
test_double_question_handles_no_previous_command && echo "✓ ?? handles missing previous command"
test_preexec_records_last_command && echo "✓ preexec records last command"
test_precmd_saves_exit_code_when_preexec_ran && echo "✓ precmd saves exit code when preexec ran"
test_precmd_does_not_update_exit_code_without_preexec && echo "✓ precmd skips update when no preexec ran"