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

codex_home="${CODEX_HOME:-${HOME}/.codex}"
auth_json="${codex_home}/auth.json"
tmp_dir="$(mktemp -d)"
tmp_auth_json="${tmp_dir}/auth.json"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

printf '%s' "${payload}" | jq -c '.authJson' > "${tmp_auth_json}"
jq -e . "${tmp_auth_json}" >/dev/null

mkdir -p "${codex_home}"
chmod 700 "${codex_home}"
cp "${tmp_auth_json}" "${auth_json}"
chmod 600 "${auth_json}"

authenticated=false
auth_json_present=false
login_status=""

if [[ -s "${auth_json}" ]]; then
  auth_json_present=true
fi

if login_status="$(codex login status 2>/dev/null)"; then
  authenticated=true
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
