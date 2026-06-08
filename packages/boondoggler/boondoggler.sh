#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: boondoggler [OPTIONS] < PROMPT

Options:
  --model VALUE
  --approval-policy VALUE
  --ask-for-approval VALUE
  --sandbox VALUE
  --effort VALUE
  --reasoning-effort VALUE
  --personality VALUE
  --summary VALUE
  --thread-config-json JSON
  --profile VALUE
  --listen VALUE
  -h, --help
EOF
}

option_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "${value}" ]]; then
    printf 'boondoggler: %s requires a value\n' "${option}" >&2
    exit 2
  fi

  printf '%s\n' "${value}"
}

append_if_set() {
  local -n target_args="$1"
  local flag="$2"
  local value="$3"

  if [[ -n "${value}" ]]; then
    target_args+=("${flag}" "${value}")
  fi
}

ROOT="${ROOT:-$(pwd)}"
BOONDOGGLE_MODEL="${BOONDOGGLE_MODEL:-gpt-5.5}"
BOONDOGGLE_APPROVAL_POLICY="${BOONDOGGLE_APPROVAL_POLICY:-never}"
BOONDOGGLE_SANDBOX="${BOONDOGGLE_SANDBOX:-danger-full-access}"
BOONDOGGLE_EFFORT="${BOONDOGGLE_EFFORT:-}"
BOONDOGGLE_PERSONALITY="${BOONDOGGLE_PERSONALITY:-}"
BOONDOGGLE_SUMMARY="${BOONDOGGLE_SUMMARY:-}"
BOONDOGGLE_THREAD_CONFIG_JSON="${BOONDOGGLE_THREAD_CONFIG_JSON:-}"
BOONDOGGLE_PROFILE="${BOONDOGGLE_PROFILE:-}"
BOONDOGGLE_LISTEN="${BOONDOGGLE_LISTEN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      BOONDOGGLE_MODEL="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --model=*)
      BOONDOGGLE_MODEL="${1#*=}"
      shift
      ;;
    --approval-policy|--ask-for-approval)
      BOONDOGGLE_APPROVAL_POLICY="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --approval-policy=*|--ask-for-approval=*)
      BOONDOGGLE_APPROVAL_POLICY="${1#*=}"
      shift
      ;;
    --sandbox)
      BOONDOGGLE_SANDBOX="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --sandbox=*)
      BOONDOGGLE_SANDBOX="${1#*=}"
      shift
      ;;
    --effort|--reasoning-effort)
      BOONDOGGLE_EFFORT="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --effort=*|--reasoning-effort=*)
      BOONDOGGLE_EFFORT="${1#*=}"
      shift
      ;;
    --personality)
      BOONDOGGLE_PERSONALITY="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --personality=*)
      BOONDOGGLE_PERSONALITY="${1#*=}"
      shift
      ;;
    --summary)
      BOONDOGGLE_SUMMARY="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --summary=*)
      BOONDOGGLE_SUMMARY="${1#*=}"
      shift
      ;;
    --thread-config-json)
      BOONDOGGLE_THREAD_CONFIG_JSON="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --thread-config-json=*)
      BOONDOGGLE_THREAD_CONFIG_JSON="${1#*=}"
      shift
      ;;
    --profile)
      BOONDOGGLE_PROFILE="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --profile=*)
      BOONDOGGLE_PROFILE="${1#*=}"
      shift
      ;;
    --listen)
      BOONDOGGLE_LISTEN="$(option_value "$1" "${2:-}")"
      shift 2
      ;;
    --listen=*)
      BOONDOGGLE_LISTEN="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      if [[ $# -ne 0 ]]; then
        usage
        exit 2
      fi
      break
      ;;
    *)
      printf 'boondoggler: unsupported option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required for JSON escaping/parsing" >&2
  exit 1
fi

PROMPT="$(cat)"
PROMPT_LENGTH=${#PROMPT}

if [[ -z "${PROMPT//[[:space:]]/}" ]]; then
  echo "boondoggler: prompt must be provided on stdin" >&2
  exit 1
fi

if (( PROMPT_LENGTH > 4000 )); then
  echo "boondoggler: read ${PROMPT_LENGTH} characters from stdin; prompts over 4000 characters may be harder to inspect in logs" >&2
fi

REQ_ID=0
LAST_REQ_ID=""
THREAD_ID=""
GOAL_SENT=0
GOAL_REQUEST_ID=""
RESUME_SENT=0
GOAL_GET_REQUEST_ID=""
THREAD_LOGGED=0
PUBLISH_ATTEMPTED=0
GIT_PUBLISH_ON_GOAL_SUCCESS="${GIT_PUBLISH_ON_GOAL_SUCCESS:-1}"
GIT_PUBLISH_ON_GOAL_FAILURE="${GIT_PUBLISH_ON_GOAL_FAILURE:-1}"
GIT_PUBLISH_ON_UNEXPECTED_EXIT="${GIT_PUBLISH_ON_UNEXPECTED_EXIT:-1}"
GIT_COMMIT_MESSAGE="${GIT_COMMIT_MESSAGE:-Codex Goal Worktree State}"
CODEX_GLOBAL_ARGS=()
CODEX_APP_ARGS=()
CODEX_APP_PID=""

append_if_set CODEX_GLOBAL_ARGS --profile-v2 "${BOONDOGGLE_PROFILE}"
append_if_set CODEX_APP_ARGS --listen "${BOONDOGGLE_LISTEN}"

send_raw() {
  local msg="$1"
  if [[ "${BOONDOGGLE_DEBUG_RPC:-0}" == "1" ]]; then
    printf '>> %s\n' "${msg}" >&2
  fi
  printf '%s\n' "${msg}" >&"${CODEX_APP[1]}"
}

log_codex_event() {
  local line="$1"
  local error method message status summary

  error="$(jq -r 'try (.error.message // empty) catch empty' <<<"${line}" 2>/dev/null || true)"
  if [[ -n "${error}" ]]; then
    printf 'codex error: %s\n' "${error}" >&2
    return 0
  fi

  method="$(jq -r 'try (.method // empty) catch empty' <<<"${line}" 2>/dev/null || true)"
  if [[ -z "${method}" ]]; then
    if ! jq -e . >/dev/null 2>&1 <<<"${line}"; then
      printf 'codex: %s\n' "${line}"
    fi
    return 0
  fi

  case "${method}" in
    thread/goal/updated)
      status="$(jq -r 'try (.params.goal.status // empty) catch empty' <<<"${line}" 2>/dev/null || true)"
      [[ -n "${status}" ]] && printf 'goal: %s\n' "${status}"
      ;;
    turn/started)
      printf 'turn: started\n'
      ;;
    turn/completed)
      status="$(jq -r 'try (.params.turn.status // empty) catch empty' <<<"${line}" 2>/dev/null || true)"
      [[ -n "${status}" ]] && printf 'turn: %s\n' "${status}"
      ;;
    *)
      message="$(jq -r 'try (
        .params.message.content
        // .params.item.text
        // .params.item.content
        // .params.delta
        // empty
      ) catch empty
      | if type == "array" then map(
          if type == "object" then (.text // .content // empty) else tostring end
        ) | join("")
        elif type == "object" then (.text // .content // empty)
        else tostring
        end' <<<"${line}" 2>/dev/null || true)"
      if [[ -n "${message}" ]]; then
        summary="${message//$'\n'/$' '}"
        printf 'codex: %s\n' "${summary}"
      fi
      ;;
  esac
}

send() {
  local method="$1"
  local id payload params
  if [[ $# -ge 2 ]]; then
    params="$2"
  else
    params="{}"
  fi
  id="${REQ_ID}"
  REQ_ID=$((REQ_ID + 1))
  LAST_REQ_ID="${id}"
  payload="$(jq -cn --arg method "${method}" --argjson id "${id}" --argjson params "${params}" \
    '{method:$method,id:$id,params:$params}')"
  send_raw "${payload}"
}

notify() {
  local method="$1"
  local params payload
  if [[ $# -ge 2 ]]; then
    params="$2"
  else
    params="{}"
  fi
  payload="$(jq -cn --arg method "${method}" --argjson params "${params}" \
    '{method:$method,params:$params}')"
  send_raw "${payload}"
}

thread_config_payload() {
  local payload

  payload="$(jq -cn \
    --arg cwd "${ROOT}" \
    --arg model "${BOONDOGGLE_MODEL}" \
    --arg approvalPolicy "${BOONDOGGLE_APPROVAL_POLICY}" \
    --arg sandbox "${BOONDOGGLE_SANDBOX}" \
    '{
      cwd: $cwd,
      model: $model,
      approvalPolicy: $approvalPolicy,
      sandbox: $sandbox
    }')"

  if [[ -n "${BOONDOGGLE_THREAD_CONFIG_JSON}" ]]; then
    payload="$(jq -c --argjson overrides "${BOONDOGGLE_THREAD_CONFIG_JSON}" '. + $overrides' <<<"${payload}")"
  fi
  if [[ -n "${BOONDOGGLE_EFFORT}" ]]; then
    payload="$(jq -c --arg effort "${BOONDOGGLE_EFFORT}" '.effort = $effort' <<<"${payload}")"
  fi
  if [[ -n "${BOONDOGGLE_PERSONALITY}" ]]; then
    payload="$(jq -c --arg personality "${BOONDOGGLE_PERSONALITY}" '.personality = $personality' <<<"${payload}")"
  fi
  if [[ -n "${BOONDOGGLE_SUMMARY}" ]]; then
    payload="$(jq -c --arg summary "${BOONDOGGLE_SUMMARY}" '.summary = $summary' <<<"${payload}")"
  fi

  printf '%s\n' "${payload}"
}

resume_thread() {
  local payload

  payload="$(thread_config_payload | jq -c --arg threadId "${THREAD_ID}" '. + {threadId: $threadId}')"
  send thread/resume "${payload}"
  RESUME_SENT=1
}

ensure_git_safe_to_commit() {
  local cherry_pick_head merge_head rebase_apply rebase_merge unmerged_paths

  if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git worktree; skipping push" >&2
    return 1
  fi

  merge_head="$(git -C "${ROOT}" rev-parse --git-path MERGE_HEAD)"
  cherry_pick_head="$(git -C "${ROOT}" rev-parse --git-path CHERRY_PICK_HEAD)"
  rebase_merge="$(git -C "${ROOT}" rev-parse --git-path rebase-merge)"
  rebase_apply="$(git -C "${ROOT}" rev-parse --git-path rebase-apply)"
  if [[ -e "${merge_head}" || -e "${cherry_pick_head}" || -d "${rebase_merge}" || -d "${rebase_apply}" ]]; then
    echo "Git operation in progress; refusing to auto-commit/push" >&2
    return 1
  fi

  unmerged_paths="$(git -C "${ROOT}" diff --name-only --diff-filter=U)"
  if [[ -n "${unmerged_paths}" ]]; then
    echo "Unmerged paths present; refusing to auto-commit/push" >&2
    return 1
  fi
}

worktree_has_changes() {
  local untracked_paths

  if ! git -C "${ROOT}" diff --quiet; then
    return 0
  fi
  if ! git -C "${ROOT}" diff --cached --quiet; then
    return 0
  fi

  untracked_paths="$(git -C "${ROOT}" ls-files --others --exclude-standard)"
  [[ -n "${untracked_paths}" ]]
}

commit_worktree_state() {
  local run_status="${1:-unknown}"
  local exit_status="${2:-}"
  local body has_changes_status subject timestamp

  set +e
  worktree_has_changes
  has_changes_status=$?
  set -e
  if [[ "${has_changes_status}" -ne 0 ]]; then
    echo "No worktree changes to commit"
    return 0
  fi

  if ! git -C "${ROOT}" add -A; then
    echo "Failed to stage worktree state" >&2
    return 1
  fi

  if git -C "${ROOT}" diff --cached --quiet; then
    echo "No staged changes after git add"
    return 0
  fi

  subject="${GIT_COMMIT_MESSAGE}: status=${run_status}"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  body="$(printf 'Prompt: stdin (%s characters)\nStatus: %s\nExit Status: %s\nThread: %s\nUTC: %s\n' \
    "${PROMPT_LENGTH}" \
    "${run_status}" \
    "${exit_status:-n/a}" \
    "${THREAD_ID:-unknown}" \
    "${timestamp}")"

  if ! git -C "${ROOT}" commit -m "${subject}" -m "${body}"; then
    echo "Auto-commit failed; leaving staged changes in place" >&2
    return 1
  fi
}

push_current_branch() {
  local branch

  if ! branch="$(git -C "${ROOT}" symbolic-ref --quiet --short HEAD)"; then
    echo "Detached HEAD; refusing to auto-push" >&2
    return 1
  fi

  if git -C "${ROOT}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git -C "${ROOT}" push
    return $?
  fi

  if git -C "${ROOT}" remote get-url origin >/dev/null 2>&1; then
    git -C "${ROOT}" push -u origin "HEAD:${branch}"
    return $?
  fi

  echo "No upstream or origin remote; unable to push" >&2
  return 1
}

publish_worktree_state() {
  local run_status="${1:-unknown}"
  local exit_status="${2:-}"
  local commit_status push_status safe_status

  if [[ "${PUBLISH_ATTEMPTED}" -eq 1 ]]; then
    return 0
  fi
  PUBLISH_ATTEMPTED=1

  echo "Publishing worktree state for status '${run_status}'"

  set +e
  ensure_git_safe_to_commit
  safe_status=$?
  set -e
  if [[ "${safe_status}" -ne 0 ]]; then
    return 1
  fi

  set +e
  commit_worktree_state "${run_status}" "${exit_status}"
  commit_status=$?
  set -e
  if [[ "${commit_status}" -ne 0 ]]; then
    return 1
  fi

  set +e
  push_current_branch
  push_status=$?
  set -e
  if [[ "${push_status}" -ne 0 ]]; then
    echo "Git push failed" >&2
    return 1
  fi
}

publish_goal_success() {
  local run_status="${1:-unknown}"
  local exit_status="${2:-}"

  if [[ "${GIT_PUBLISH_ON_GOAL_SUCCESS}" != "1" ]]; then
    echo "GIT_PUBLISH_ON_GOAL_SUCCESS=${GIT_PUBLISH_ON_GOAL_SUCCESS}; skipping commit and push"
    return 0
  fi

  publish_worktree_state "${run_status}" "${exit_status}"
}

publish_goal_failure() {
  local run_status="${1:-unknown}"
  local exit_status="${2:-}"

  if [[ "${GIT_PUBLISH_ON_GOAL_FAILURE}" != "1" ]]; then
    echo "GIT_PUBLISH_ON_GOAL_FAILURE=${GIT_PUBLISH_ON_GOAL_FAILURE}; skipping commit and push"
    return 0
  fi

  publish_worktree_state "${run_status}" "${exit_status}"
}

finish_successfully() {
  local publish_status

  set +e
  publish_goal_success "complete" "0"
  publish_status=$?
  set -e
  if [[ "${publish_status}" -eq 0 ]]; then
    exit 0
  fi
  exit 1
}

finish_failed_goal() {
  local publish_status
  local status="$1"

  echo "Goal ended with status '${status}'" >&2
  set +e
  publish_goal_failure "${status}" "1"
  publish_status=$?
  set -e
  if [[ "${publish_status}" -ne 0 ]]; then
    exit 1
  fi
  exit 1
}

trap '
  status=$?

  if [[ "$status" -ne 0 && "$GIT_PUBLISH_ON_UNEXPECTED_EXIT" == "1" && "$PUBLISH_ATTEMPTED" -eq 0 ]]; then
    echo "Unexpected exit status $status; publishing partial worktree state" >&2
    publish_worktree_state "unexpected-exit" "$status" || true
  fi

  [[ -n "${CODEX_APP_PID:-}" ]] && kill "$CODEX_APP_PID" 2>/dev/null || true

  exit "$status"
' EXIT

coproc CODEX_APP { codex "${CODEX_GLOBAL_ARGS[@]}" app-server "${CODEX_APP_ARGS[@]}" 2>&1; }

initialize_payload="$(jq -cn '{
  clientInfo: {
    name: "boondoggler",
    title: "boondoggler - ToxicPine'\''s Favourite CLI Tool",
    version: "0.1.0"
  },
  capabilities: {experimentalApi: true}
}')"
send initialize "${initialize_payload}"
notify initialized '{}'
thread_start_payload="$(thread_config_payload)"
send thread/start "${thread_start_payload}"

while IFS= read -r line <&"${CODEX_APP[0]}"; do
  if [[ "${BOONDOGGLE_DEBUG_RPC:-0}" == "1" ]]; then
    printf '<< %s\n' "${line}" >&2
  fi
  log_codex_event "${line}"

  if [[ -z "${THREAD_ID}" ]]; then
    THREAD_ID="$(jq -r 'try (.result.thread.id // .params.thread.id // .params.threadId // empty)' <<<"${line}" 2>/dev/null || true)"
  fi

  if [[ -n "${THREAD_ID}" && "${THREAD_LOGGED}" -eq 0 ]]; then
    printf 'thread: %s\n' "${THREAD_ID}"
    THREAD_LOGGED=1
  fi

  if [[ -n "${THREAD_ID}" && "${GOAL_SENT}" -eq 0 ]]; then
    goal_set_payload="$(jq -cn --arg threadId "${THREAD_ID}" --arg objective "${PROMPT}" '{
      threadId: $threadId,
      objective: $objective,
      status: "active"
    }')"
    send thread/goal/set "${goal_set_payload}"
    GOAL_REQUEST_ID="${LAST_REQ_ID}"
    GOAL_SENT=1
  fi

  if [[ "${GOAL_SENT}" -eq 1 && "${RESUME_SENT}" -eq 0 ]]; then
    goal_ok="$(jq -r --argjson id "${GOAL_REQUEST_ID}" 'try (select(.id == $id and .result) | "yes") // empty' <<<"${line}" 2>/dev/null || true)"
    if [[ "${goal_ok}" == "yes" ]]; then
      resume_thread
    fi
  fi

  goal_status="$(jq -r --arg threadId "${THREAD_ID}" 'try (select(.method == "thread/goal/updated" and ((.params.threadId // .params.goal.threadId // "") == $threadId)) | (.params.goal.status // empty | ascii_downcase)) // empty' <<<"${line}" 2>/dev/null || true)"
  if [[ -n "${goal_status}" ]]; then
    case "${goal_status}" in
      complete)
        finish_successfully
        ;;
      blocked|budgetlimited|paused|usagelimited)
        finish_failed_goal "${goal_status}"
        ;;
      *)
        ;;
    esac
  fi

  turn_status="$(jq -r 'try (select(.method == "turn/completed") | (.params.turn.status // empty | ascii_downcase)) // empty' <<<"${line}" 2>/dev/null || true)"
  if [[ "${turn_status}" == "completed" && -n "${THREAD_ID}" && -z "${GOAL_GET_REQUEST_ID}" ]]; then
    goal_get_payload="$(jq -cn --arg threadId "${THREAD_ID}" '{threadId: $threadId}')"
    send thread/goal/get "${goal_get_payload}"
    GOAL_GET_REQUEST_ID="${LAST_REQ_ID}"
  elif [[ "${turn_status}" == "failed" || "${turn_status}" == "interrupted" ]]; then
    finish_failed_goal "${turn_status}"
  fi

  if [[ -n "${GOAL_GET_REQUEST_ID}" ]]; then
    goal_get_status="$(jq -r --argjson id "${GOAL_GET_REQUEST_ID}" 'try (select(.id == $id and .result.goal) | (.result.goal.status // empty | ascii_downcase)) // empty' <<<"${line}" 2>/dev/null || true)"
    if [[ -n "${goal_get_status}" ]]; then
      GOAL_GET_REQUEST_ID=""
      case "${goal_get_status}" in
        complete)
          finish_successfully
          ;;
        blocked|budgetlimited|paused|usagelimited)
          finish_failed_goal "${goal_get_status}"
          ;;
        *)
          ;;
      esac
    fi
  fi
done

finish_failed_goal "app-server-exited"