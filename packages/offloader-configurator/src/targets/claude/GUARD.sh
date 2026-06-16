#!/usr/bin/env bash
set -euo pipefail

missing=()

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    missing+=("${name}")
  fi
}

require_command claude
require_command jq

claude_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
credentials_json="${claude_config_dir}/.credentials.json"

if [[ -e "${claude_config_dir}" && ! -d "${claude_config_dir}" ]]; then
  missing+=("claude-config-creatable")
elif [[ -e "${claude_config_dir}" && ! -w "${claude_config_dir}" ]]; then
  missing+=("claude-config-writable")
elif [[ ! -e "${claude_config_dir}" ]]; then
  claude_config_parent="$(dirname "${claude_config_dir}")"
  while [[ ! -e "${claude_config_parent}" && "${claude_config_parent}" != "/" ]]; do
    claude_config_parent="$(dirname "${claude_config_parent}")"
  done
  if [[ ! -d "${claude_config_parent}" || ! -w "${claude_config_parent}" ]]; then
    missing+=("claude-config-creatable")
  fi
fi

if [[ -e "${credentials_json}" && ! -w "${credentials_json}" ]]; then
  missing+=("claude-credentials-writable")
fi

if [[ "${#missing[@]}" -eq 0 ]]; then
  printf '{"ok":true}\n'
  exit 0
fi

printf '{"ok":false,"error":{"type":"missing-requirements","detail":['
sep=""
for name in "${missing[@]}"; do
  case "${name}" in
    claude|jq)
      detail="not found on PATH"
      ;;
    claude-config-writable)
      detail="Claude config directory is not writable"
      ;;
    claude-config-creatable)
      detail="Claude config directory cannot be created"
      ;;
    claude-credentials-writable)
      detail="Claude credentials artifact is not writable"
      ;;
    *)
      detail="unavailable"
      ;;
  esac
  printf '%s{"name":"%s","detail":"%s"}' "${sep}" "${name}" "${detail}"
  sep=","
done
printf ']}}\n'
