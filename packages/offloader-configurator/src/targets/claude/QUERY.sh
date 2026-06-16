#!/usr/bin/env bash
set -euo pipefail

claude_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
credentials_json="${claude_config_dir}/.credentials.json"
bashrc="${HOME}/.bashrc"

credentials_present=false
oauth_token_configured=false

if [[ -s "${credentials_json}" ]]; then
  credentials_present=true
fi

if [[ -f "${bashrc}" ]] && grep -q "CLAUDE_CODE_OAUTH_TOKEN" "${bashrc}"; then
  oauth_token_configured=true
fi

jq -n \
  --arg claudeConfigDir "${claude_config_dir}" \
  --argjson credentialsPresent "${credentials_present}" \
  --argjson oauthTokenConfigured "${oauth_token_configured}" \
  '{
    claudeConfigDir: $claudeConfigDir,
    credentialsPresent: $credentialsPresent,
    oauthTokenConfigured: $oauthTokenConfigured
  }'
