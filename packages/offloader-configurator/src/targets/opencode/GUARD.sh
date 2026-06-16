#!/usr/bin/env bash
set -euo pipefail

missing=()

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    missing+=("${name}")
  fi
}

require_command opencode
require_command jq

data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/opencode"
auth_json="${data_dir}/auth.json"

if [[ -e "${data_dir}" && ! -d "${data_dir}" ]]; then
  missing+=("opencode-data-creatable")
elif [[ -e "${data_dir}" && ! -w "${data_dir}" ]]; then
  missing+=("opencode-data-writable")
elif [[ ! -e "${data_dir}" ]]; then
  data_dir_parent="$(dirname "${data_dir}")"
  while [[ ! -e "${data_dir_parent}" && "${data_dir_parent}" != "/" ]]; do
    data_dir_parent="$(dirname "${data_dir_parent}")"
  done
  if [[ ! -d "${data_dir_parent}" || ! -w "${data_dir_parent}" ]]; then
    missing+=("opencode-data-creatable")
  fi
fi

if [[ -e "${auth_json}" && ! -w "${auth_json}" ]]; then
  missing+=("opencode-auth-writable")
fi

if [[ "${#missing[@]}" -eq 0 ]]; then
  printf '{"ok":true}\n'
  exit 0
fi

printf '{"ok":false,"error":{"type":"missing-requirements","detail":['
sep=""
for name in "${missing[@]}"; do
  case "${name}" in
    opencode|jq)
      detail="not found on PATH"
      ;;
    opencode-data-writable)
      detail="OpenCode data directory is not writable"
      ;;
    opencode-data-creatable)
      detail="OpenCode data directory cannot be created"
      ;;
    opencode-auth-writable)
      detail="OpenCode auth artifact is not writable"
      ;;
    *)
      detail="unavailable"
      ;;
  esac
  printf '%s{"name":"%s","detail":"%s"}' "${sep}" "${name}" "${detail}"
  sep=","
done
printf ']}}\n'
