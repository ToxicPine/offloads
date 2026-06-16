#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
mutation_type="$(printf '%s' "${payload}" | jq -r '.type')"

case "${mutation_type}" in
  configure) ;;
  *)
    printf 'unknown mutation type: %s\n' "${mutation_type}" >&2
    exit 2
    ;;
esac

claude_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
credentials_json="${claude_config_dir}/.credentials.json"
tmp_dir="$(mktemp -d)"
tmp_credentials="${tmp_dir}/.credentials.json"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

printf '%s' "${payload}" | jq -c '.credentials' > "${tmp_credentials}"
jq -e . "${tmp_credentials}" >/dev/null

mkdir -p "${claude_config_dir}"
chmod 700 "${claude_config_dir}"
cp "${tmp_credentials}" "${credentials_json}"
chmod 600 "${credentials_json}"

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
