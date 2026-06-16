#!/usr/bin/env bash
set -euo pipefail

claude_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"

authenticated=false
auth_method=""
api_provider=""

if status_json="$(claude auth status --json 2>/dev/null)"; then
  logged_in="$(jq -r '.loggedIn // false' <<<"${status_json}")"
  if [[ "${logged_in}" == "true" ]]; then
    authenticated=true
  fi
  auth_method="$(jq -r '.authMethod // empty' <<<"${status_json}")"
  api_provider="$(jq -r '.apiProvider // empty' <<<"${status_json}")"
fi

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg authMethod "${auth_method}" \
  --arg apiProvider "${api_provider}" \
  --arg claudeConfigDir "${claude_config_dir}" \
  '{ authenticated: $authenticated }
  + (if $authMethod == "" then {} else {authMethod: $authMethod} end)
  + (if $apiProvider == "" then {} else {apiProvider: $apiProvider} end)
  + { claudeConfigDir: $claudeConfigDir }'
