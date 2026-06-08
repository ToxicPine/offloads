#!/usr/bin/env bash
set -Eeuo pipefail

subscribed=0
route=""

usage() {
  cat >&2 <<'EOF'
usage:
  vusperize [options] -- <command...>

options:
  --route NAME             Hermes webhook route name. Default: generated.
  --deliver TARGET         Optional delivery target, e.g. telegram/discord/slack.
  --deliver-chat-id ID     Optional chat/channel ID for the delivery target.
  --deliver-only           Deliver the rendered prompt directly; do not run the agent.
  -h, --help               Show this help.

environment overrides:
  VUSPERIZE_ROUTE
  VUSPERIZE_DELIVER
  VUSPERIZE_DELIVER_CHAT_ID
  VUSPERIZE_DELIVER_ONLY
  VUSPERIZE_PROMPT
  VUSPERIZE_DESCRIPTION
EOF
}

require_cmd() {
  local name=$1

  if ! command -v "${name}" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "${name}" >&2
    return 127
  fi
}

require_hermes() {
  if ! command -v hermes >/dev/null 2>&1; then
    printf '%s\n' 'vusperize requires the Hermes CLI on PATH. Install Hermes or run vusperize in an environment that provides the hermes command.' >&2
    return 127
  fi
}

need_value() {
  local option=$1
  local value=${2-}

  if [[ -z ${value} ]]; then
    printf 'missing value for %s\n' "${option}" >&2
    return 2
  fi
}

cleanup() {
  local status=$?

  if [[ ${subscribed} == "1" ]]; then
    hermes webhook remove "${route}" >/dev/null 2>&1 || true
  fi

  exit "${status}"
}

on_int() {
  trap - INT
  exit 130
}

on_term() {
  trap - TERM
  exit 143
}

tofiny() {
  local event_type
  local state
  local payload

  if (($# < 2)); then
    printf 'usage: tofiny <label-or-type> <status-update-text>\n' >&2
    return 2
  fi

  event_type=$1
  shift
  state=$*

  payload=$(
    jq -nc \
      --arg event_type "${event_type}" \
      --arg state "${state}" \
      '{event_type: $event_type, state: $state}'
  )

  hermes webhook test "${VUSPERIZE_ROUTE}" --payload "${payload}" >/dev/null
}

main() {
  local deliver
  local deliver_chat_id
  local deliver_only
  local prompt
  local description
  local status
  local -a subscribe_args

  route=${VUSPERIZE_ROUTE:-}
  deliver=${VUSPERIZE_DELIVER:-}
  deliver_chat_id=${VUSPERIZE_DELIVER_CHAT_ID:-}
  deliver_only=${VUSPERIZE_DELIVER_ONLY:-false}
  prompt=${VUSPERIZE_PROMPT:-$'You are receiving a live status update for a running workflow. This update has the label "{event_type}". The update says "{state}".\n\nUse this information to maintain your own understanding of the workflow. If this update indicates the task has just started or been initiated for the first time, you should almost always tell the user. For other updates, decide whether to surface a message based on the user\'s preferences and the importance of the change. Avoid spamming the user. Keep routine or low-value progress details to yourself unless they materially affect expectations, decisions, blockers, or completion.'}
  description=${VUSPERIZE_DESCRIPTION:-Temporary route for LLM workflow status updates}

  while (($# > 0)); do
    case $1 in
      --route)
        need_value "$1" "${2-}"
        route=$2
        shift 2
        ;;
      --deliver)
        need_value "$1" "${2-}"
        deliver=$2
        shift 2
        ;;
      --deliver-chat-id)
        need_value "$1" "${2-}"
        deliver_chat_id=$2
        shift 2
        ;;
      --deliver-only)
        deliver_only=true
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      *)
        printf 'unknown vusperize arg: %s\n' "${1}" >&2
        usage
        return 2
        ;;
    esac
  done

  if (($# == 0)); then
    usage
    return 2
  fi

  if [[ -z ${route} ]]; then
    route="vusperize-$(date +%s)-$$"
  fi

  if [[ ${deliver_only} == "true" && -z ${deliver} ]]; then
    printf '%s\n' '--deliver-only requires --deliver TARGET' >&2
    return 2
  fi

  if [[ ${deliver_only} == "true" && ${deliver} == "log" ]]; then
    printf '%s\n' '--deliver-only cannot be used with deliver target "log"' >&2
    return 2
  fi

  require_hermes
  require_cmd jq

  subscribe_args=(
    webhook subscribe "${route}"
    --prompt "${prompt}"
    --description "${description}"
  )

  if [[ -n ${deliver} ]]; then
    subscribe_args+=(--deliver "${deliver}")
  fi

  if [[ -n ${deliver_chat_id} ]]; then
    subscribe_args+=(--deliver-chat-id "${deliver_chat_id}")
  fi

  if [[ ${deliver_only} == "true" ]]; then
    subscribe_args+=(--deliver-only)
  fi

  hermes "${subscribe_args[@]}" >/dev/null
  subscribed=1

  export VUSPERIZE_ROUTE="${route}"
  export -f tofiny

  status=0
  "$@" || status=$?

  return "${status}"
}

trap cleanup EXIT
trap on_int INT
trap on_term TERM

main "$@"
