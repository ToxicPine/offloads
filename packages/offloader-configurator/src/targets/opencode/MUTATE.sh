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

data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/opencode"
auth_json="${data_dir}/auth.json"
tmp_dir="$(mktemp -d)"
tmp_auth_json="${tmp_dir}/auth.json"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

printf '%s' "${payload}" | jq -c '.authJson' > "${tmp_auth_json}"
jq -e . "${tmp_auth_json}" >/dev/null

mkdir -p "${data_dir}"
chmod 700 "${data_dir}"
cp "${tmp_auth_json}" "${auth_json}"
chmod 600 "${auth_json}"

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
