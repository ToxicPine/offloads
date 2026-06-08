#!/usr/bin/env bash
set -euo pipefail

missing=()

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    missing+=("${name}")
  fi
}

require_command codex
require_command jq

codex_home="${CODEX_HOME:-${HOME}/.codex}"
auth_json="${codex_home}/auth.json"

if [[ -e "${codex_home}" && ! -d "${codex_home}" ]]; then
  missing+=("codex-home-creatable")
elif [[ -e "${codex_home}" && ! -w "${codex_home}" ]]; then
  missing+=("codex-home-writable")
elif [[ ! -e "${codex_home}" ]]; then
  codex_home_parent="$(dirname "${codex_home}")"
  while [[ ! -e "${codex_home_parent}" && "${codex_home_parent}" != "/" ]]; do
    codex_home_parent="$(dirname "${codex_home_parent}")"
  done
  if [[ ! -d "${codex_home_parent}" || ! -w "${codex_home_parent}" ]]; then
    missing+=("codex-home-creatable")
  fi
fi

if [[ -e "${auth_json}" && ! -w "${auth_json}" ]]; then
  missing+=("codex-auth-writable")
fi

if [[ "${#missing[@]}" -eq 0 ]]; then
  printf '{"ok":true}\n'
  exit 0
fi

printf '{"ok":false,"error":{"type":"missing-requirements","detail":['
sep=""
for name in "${missing[@]}"; do
  case "${name}" in
    codex|jq)
      detail="not found on PATH"
      ;;
    codex-home-writable)
      detail="Codex home is not writable"
      ;;
    codex-home-creatable)
      detail="Codex home cannot be created"
      ;;
    codex-auth-writable)
      detail="Codex auth artifact is not writable"
      ;;
    *)
      detail="unavailable"
      ;;
  esac
  printf '%s{"name":"%s","detail":"%s"}' "${sep}" "${name}" "${detail}"
  sep=","
done
printf ']}}\n'
