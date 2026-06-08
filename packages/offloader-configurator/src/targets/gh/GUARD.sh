#!/usr/bin/env bash
set -euo pipefail

missing=()

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    missing+=("${name}")
  fi
}

require_command gh
require_command git
require_command jq

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
gh_config_dir="${config_home}/gh"
git_config="${HOME}/.gitconfig"

if [[ -e "${gh_config_dir}" && ! -w "${gh_config_dir}" ]]; then
  missing+=("gh-config-writable")
elif [[ ! -e "${gh_config_dir}" ]]; then
  gh_config_parent="${config_home}"
  while [[ ! -e "${gh_config_parent}" && "${gh_config_parent}" != "/" ]]; do
    gh_config_parent="$(dirname "${gh_config_parent}")"
  done
  if [[ ! -d "${gh_config_parent}" || ! -w "${gh_config_parent}" ]]; then
    missing+=("gh-config-creatable")
  fi
elif [[ ! -d "${gh_config_dir}" ]]; then
  missing+=("gh-config-creatable")
fi

if [[ -e "${git_config}" && ! -w "${git_config}" ]]; then
  missing+=("git-config-writable")
elif [[ ! -e "${git_config}" && ! -w "${HOME}" ]]; then
  missing+=("git-config-creatable")
fi

if [[ "${#missing[@]}" -eq 0 ]]; then
  printf '{"ok":true}\n'
  exit 0
fi

printf '{"ok":false,"error":{"type":"missing-requirements","detail":['
sep=""
for name in "${missing[@]}"; do
  case "${name}" in
    gh|git|jq)
      detail="not found on PATH"
      ;;
    gh-config-writable)
      detail="GitHub CLI config directory is not writable"
      ;;
    gh-config-creatable)
      detail="GitHub CLI config directory cannot be created"
      ;;
    git-config-writable)
      detail="global git config is not writable"
      ;;
    git-config-creatable)
      detail="global git config cannot be created"
      ;;
    *)
      detail="unavailable"
      ;;
  esac
  printf '%s{"name":"%s","detail":"%s"}' "${sep}" "${name}" "${detail}"
  sep=","
done
printf ']}}\n'
