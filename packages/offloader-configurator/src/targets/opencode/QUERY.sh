#!/usr/bin/env bash
set -euo pipefail

data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/opencode"
auth_json="${data_dir}/auth.json"

authenticated=false
auth_json_present=false
providers=""

if [[ -s "${auth_json}" ]] && jq -e 'type == "object"' "${auth_json}" >/dev/null 2>&1; then
  auth_json_present=true
  providers="$(jq -r 'keys_unsorted | join(", ")' "${auth_json}" 2>/dev/null || true)"
  if jq -e 'length > 0' "${auth_json}" >/dev/null 2>&1; then
    authenticated=true
  fi
fi

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg dataDir "${data_dir}" \
  --argjson authJsonPresent "${auth_json_present}" \
  --arg providers "${providers}" \
  '{
    authenticated: $authenticated,
    dataDir: $dataDir,
    authJsonPresent: $authJsonPresent
  }
  + (if $providers == "" then {} else {providers: $providers} end)'
