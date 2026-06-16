#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
mutation_type="$(printf '%s' "${payload}" | jq -r '.type')"

claude_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
credentials_json="${claude_config_dir}/.credentials.json"
bashrc="${HOME}/.bashrc"
sentinel="# offloader-configurator: claude oauth token"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

auth_method=""

case "${mutation_type}" in
  configure-credentials)
    auth_method="credentials"
    tmp_credentials="${tmp_dir}/.credentials.json"
    printf '%s' "${payload}" | jq -c '.credentials' > "${tmp_credentials}"
    jq -e . "${tmp_credentials}" >/dev/null

    mkdir -p "${claude_config_dir}"
    chmod 700 "${claude_config_dir}"
    cp "${tmp_credentials}" "${credentials_json}"
    chmod 600 "${credentials_json}"
    ;;
  configure-token)
    auth_method="token"
    token="$(printf '%s' "${payload}" | jq -r '.oauthToken')"
    tmp_bashrc="${tmp_dir}/bashrc"

    if [[ -f "${bashrc}" ]]; then
      grep -v -e "${sentinel}" -e "CLAUDE_CODE_OAUTH_TOKEN" "${bashrc}" \
        > "${tmp_bashrc}" || true
    fi

    esc_token="${token//\'/\'\\\'\'}"
    {
      printf '%s\n' "${sentinel}"
      printf "export CLAUDE_CODE_OAUTH_TOKEN='%s'\n" "${esc_token}"
    } >> "${tmp_bashrc}"

    cp "${tmp_bashrc}" "${bashrc}"
    chmod 600 "${bashrc}"
    ;;
  *)
    printf 'unknown mutation type: %s\n' "${mutation_type}" >&2
    exit 2
    ;;
esac

credentials_present=false
oauth_token_configured=false

if [[ -s "${credentials_json}" ]]; then
  credentials_present=true
fi

if [[ -f "${bashrc}" ]] && grep -q "CLAUDE_CODE_OAUTH_TOKEN" "${bashrc}"; then
  oauth_token_configured=true
fi

jq -n \
  --arg authMethod "${auth_method}" \
  --arg claudeConfigDir "${claude_config_dir}" \
  --argjson credentialsPresent "${credentials_present}" \
  --argjson oauthTokenConfigured "${oauth_token_configured}" \
  '{
    claudeConfigDir: $claudeConfigDir,
    credentialsPresent: $credentialsPresent,
    oauthTokenConfigured: $oauthTokenConfigured
  }
  + (if $authMethod == "" then {} else {authMethod: $authMethod} end)'
