#!/usr/bin/env bash
set -euo pipefail

hermes_home="${HERMES_HOME:-${HOME}/.hermes}"
auth_json="${hermes_home}/auth.json"

authenticated=false
auth_json_present=false
active_provider=""

if [[ -s "${auth_json}" ]] && jq -e 'type == "object"' "${auth_json}" >/dev/null 2>&1; then
  auth_json_present=true

  # Defer the authenticated verdict to Hermes' own `hermes auth status`. The
  # store is only used to enumerate which providers to ask about: its
  # active_provider pointer first, then every provider with stored state (OAuth
  # logins land in .providers, API keys in .credential_pool). The first provider
  # Hermes reports as logged in wins.
  if command -v hermes >/dev/null 2>&1; then
    candidates="$(jq -r '
      ([(.active_provider // empty)]
        + ((.providers // {}) | keys_unsorted)
        + ((.credential_pool // {}) | keys_unsorted))
      | map(select(. != null and . != "")) | .[]' "${auth_json}" 2>/dev/null || true)"
    declare -A seen=()
    while IFS= read -r candidate; do
      if [[ -z "${candidate}" || -n "${seen[${candidate}]:-}" ]]; then
        continue
      fi
      seen["${candidate}"]=1
      if status_text="$(hermes auth status "${candidate}" 2>/dev/null)" &&
        printf '%s' "${status_text}" | grep -q ': logged in'; then
        authenticated=true
        active_provider="${candidate}"
        break
      fi
    done <<<"${candidates}"
  fi
fi

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg hermesHome "${hermes_home}" \
  --argjson authJsonPresent "${auth_json_present}" \
  --arg activeProvider "${active_provider}" \
  'if $authenticated then
    {
      authenticated: true,
      hermesHome: $hermesHome,
      authJsonPresent: true,
      activeProvider: $activeProvider
    }
  else
    {
      authenticated: false,
      hermesHome: $hermesHome,
      authJsonPresent: $authJsonPresent
    }
  end'
