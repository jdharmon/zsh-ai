#!/usr/bin/env zsh

# Load test helper
source "${0:A:h}/test_helper.zsh"

# Load modules under test
source "$PLUGIN_DIR/lib/config.zsh"
source "$PLUGIN_DIR/lib/context.zsh"
source "$PLUGIN_DIR/lib/utils.zsh"
source "$PLUGIN_DIR/lib/providers/gemini.zsh"
source "$PLUGIN_DIR/lib/agent.zsh"

# Restore functions that individual tests replace with mocks.
_restore_agent() {
    source "$PLUGIN_DIR/lib/providers/gemini.zsh"
    source "$PLUGIN_DIR/lib/agent.zsh"
}

# ---- protocol parser: _zsh_ai_agent_extract_action ----

test_extract_action_with_block() {
    setup_test_env
    local reply=$'Let me check.\n```tool\ngit status --porcelain\n```\n'
    assert_equals "$(_zsh_ai_agent_extract_action "$reply")" "git status --porcelain"
    teardown_test_env
}

test_extract_action_no_block_is_final_answer() {
    setup_test_env
    assert_equals "$(_zsh_ai_agent_extract_action "All done. 5 files found.")" ""
    teardown_test_env
}

test_extract_action_takes_last_block() {
    setup_test_env
    local reply=$'```tool\nfirst\n```\nthinking\n```tool\nsecond\n```'
    assert_equals "$(_zsh_ai_agent_extract_action "$reply")" "second"
    teardown_test_env
}

# ---- executor: _zsh_ai_agent_run ----

test_executor_reports_exit_code() {
    setup_test_env
    _ZSH_AI_AGENT_ALWAYS=1
    _zsh_ai_agent_run "exit 7" >/dev/null
    assert_contains "$_zsh_ai_agent_run_result" "<returncode>7</returncode>"
    teardown_test_env
}

test_executor_is_stateless() {
    setup_test_env
    local here=$(pwd)
    _zsh_ai_agent_run "cd /tmp" >/dev/null
    _zsh_ai_agent_run "pwd" >/dev/null
    # A later command still runs in the original directory, not /tmp.
    assert_contains "$_zsh_ai_agent_run_result" "$here"
    teardown_test_env
}

test_executor_truncates_output() {
    setup_test_env
    ZSH_AI_AGENT_MAX_OUTPUT=100
    _zsh_ai_agent_run 'printf "%0.sX" {1..500}' >/dev/null
    assert_contains "$_zsh_ai_agent_run_result" "bytes elided"
    teardown_test_env
}

test_executor_times_out() {
    setup_test_env
    ZSH_AI_AGENT_TIMEOUT=1
    _zsh_ai_agent_run "sleep 5" >/dev/null
    assert_contains "$_zsh_ai_agent_run_result" "<returncode>124</returncode>"
    teardown_test_env
}

# ---- confirm gate: _zsh_ai_agent_confirm ----

test_confirm_yes_runs() {
    setup_test_env
    _ZSH_AI_AGENT_ALWAYS=0
    _zsh_ai_agent_confirm "ls" >/dev/null <<< "y"
    assert_equals "$?" "0"
    teardown_test_env
}

test_confirm_no_declines() {
    setup_test_env
    _ZSH_AI_AGENT_ALWAYS=0
    _zsh_ai_agent_confirm "rm -rf /" >/dev/null <<< "n"
    assert_equals "$?" "1"
    teardown_test_env
}

test_confirm_always_shortcircuits() {
    setup_test_env
    _ZSH_AI_AGENT_ALWAYS=1
    _zsh_ai_agent_confirm "anything" >/dev/null
    assert_equals "$?" "0"
    teardown_test_env
}

# ---- loop: _zsh_ai_agent_loop ----

test_loop_runs_tool_then_finishes() {
    setup_test_env
    local cf=$(mktemp); echo 0 > "$cf"
    _zsh_ai_agent_query_gemini() {
        local n=$(cat "$cf"); n=$((n + 1)); echo "$n" > "$cf"
        if [[ $n -eq 1 ]]; then
            printf 'Counting.\n```tool\necho hi\n```\n'
        else
            echo "Final answer: done."
        fi
    }
    _zsh_ai_agent_confirm() { return 0; }

    local out=$(_zsh_ai_agent_loop "do it" 2>&1)
    local rc=$?
    local calls=$(cat "$cf"); rm -f "$cf"

    assert_equals "$rc" "0"
    assert_contains "$out" "Final answer: done."
    assert_equals "$calls" "2"
    _restore_agent
    teardown_test_env
}

test_loop_decline_does_not_run_command() {
    setup_test_env
    export ZSH_AI_AGENT_MAX_STEPS=1
    _zsh_ai_agent_query_gemini() { printf '```tool\necho SHOULD_NOT_RUN\n```\n'; }
    _zsh_ai_agent_confirm() { return 1; }
    local RAN=0
    _zsh_ai_agent_run() { RAN=1; }

    _zsh_ai_agent_loop "go" >/dev/null 2>&1

    assert_equals "$RAN" "0"
    assert_contains "${_zsh_ai_agent_texts[-1]}" "declined"
    unset ZSH_AI_AGENT_MAX_STEPS
    _restore_agent
    teardown_test_env
}

test_loop_respects_step_cap() {
    setup_test_env
    export ZSH_AI_AGENT_MAX_STEPS=3
    local cf=$(mktemp); echo 0 > "$cf"
    _zsh_ai_agent_query_gemini() {
        local n=$(cat "$cf"); echo $((n + 1)) > "$cf"
        printf '```tool\necho x\n```\n'
    }
    _zsh_ai_agent_confirm() { return 0; }
    _zsh_ai_agent_run() { :; }

    _zsh_ai_agent_loop "never ends" >/dev/null 2>&1
    local rc=$?
    local calls=$(cat "$cf"); rm -f "$cf"

    assert_equals "$rc" "1"
    assert_equals "$calls" "3"
    unset ZSH_AI_AGENT_MAX_STEPS
    _restore_agent
    teardown_test_env
}

# ---- gating: _zsh_ai_agent_available ----

test_agent_available_rejects_non_gemini() {
    setup_test_env
    export ZSH_AI_PROVIDER="anthropic"
    _zsh_ai_agent_available 2>/dev/null
    assert_equals "$?" "1"
    teardown_test_env
}

test_agent_available_accepts_gemini() {
    setup_test_env
    export ZSH_AI_PROVIDER="gemini"
    _zsh_ai_agent_available 2>/dev/null
    assert_equals "$?" "0"
    teardown_test_env
}

# Run tests
echo "Running agent mode tests..."
run_test "Extract action from tool block" test_extract_action_with_block
run_test "No tool block means final answer" test_extract_action_no_block_is_final_answer
run_test "Extract takes the last tool block" test_extract_action_takes_last_block
run_test "Executor reports exit code" test_executor_reports_exit_code
run_test "Executor is stateless between commands" test_executor_is_stateless
run_test "Executor truncates large output" test_executor_truncates_output
run_test "Executor enforces timeout" test_executor_times_out
run_test "Confirm y runs command" test_confirm_yes_runs
run_test "Confirm n declines command" test_confirm_no_declines
run_test "Confirm always short-circuits" test_confirm_always_shortcircuits
run_test "Loop runs a tool then finishes" test_loop_runs_tool_then_finishes
run_test "Loop decline does not run command" test_loop_decline_does_not_run_command
run_test "Loop respects step cap" test_loop_respects_step_cap
run_test "Agent unavailable for non-gemini provider" test_agent_available_rejects_non_gemini
run_test "Agent available for gemini provider" test_agent_available_accepts_gemini
finish_tests
