#!/usr/bin/env bash
set -euo pipefail

codex_home="${CODEX_HOME:-${HOME}/.codex}"
auth_json="${codex_home}/auth.json"

authenticated=false
auth_json_present=false
login_status=""

if [[ -s "${auth_json}" ]]; then
  auth_json_present=true
fi

if [[ -d "${codex_home}" ]]; then
  if login_status="$(codex login status 2>/dev/null)"; then
    authenticated=true
  fi
fi

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg codexHome "${codex_home}" \
  --argjson authJsonPresent "${auth_json_present}" \
  --arg loginStatus "${login_status}" \
  '{
    authenticated: $authenticated,
    codexHome: $codexHome,
    authJsonPresent: $authJsonPresent
  }
  + (if $loginStatus == "" then {} else {loginStatus: $loginStatus} end)'
