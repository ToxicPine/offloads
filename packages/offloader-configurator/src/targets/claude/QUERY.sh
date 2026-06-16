#!/usr/bin/env bash
set -euo pipefail

claude_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
credentials_json="${claude_config_dir}/.credentials.json"
bashrc="${HOME}/.bashrc"

authenticated=false
credential_source="none"

if [[ -s "${credentials_json}" ]]; then
  credential_source="credentials"
elif [[ -f "${bashrc}" ]] && grep -q "CLAUDE_CODE_OAUTH_TOKEN" "${bashrc}"; then
  credential_source="token"
fi

if status_json="$(claude auth status --json 2>/dev/null)"; then
  logged_in="$(jq -r '.loggedIn // false' <<<"${status_json}")"
  if [[ "${logged_in}" == "true" ]]; then
    authenticated=true
  fi
fi

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg credentialSource "${credential_source}" \
  --arg claudeConfigDir "${claude_config_dir}" \
  '{
    authenticated: $authenticated,
    credentialSource: $credentialSource,
    claudeConfigDir: $claudeConfigDir
  }'
