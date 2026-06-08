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

token="$(printf '%s' "${payload}" | jq -r '.githubToken')"
git_user_name="$(printf '%s' "${payload}" | jq -r '.gitUserName // empty')"
git_user_email="$(printf '%s' "${payload}" | jq -r '.gitUserEmail // empty')"

printf '%s\n' "${token}" | gh auth login --hostname github.com --with-token 1>&2
gh auth setup-git --hostname github.com 1>&2

if [[ -n "${git_user_name}" ]]; then
  git config --global user.name "${git_user_name}"
fi

if [[ -n "${git_user_email}" ]]; then
  git config --global user.email "${git_user_email}"
fi

authenticated=false
account=""
host=""

if gh auth status --hostname github.com >/dev/null 2>&1; then
  authenticated=true
  host="github.com"
  account="$(gh api user --jq .login 2>/dev/null || true)"
fi

current_git_user_name="$(git config --global --get user.name 2>/dev/null || true)"
current_git_user_email="$(git config --global --get user.email 2>/dev/null || true)"
credential_helper="$(git config --global --get credential.helper 2>/dev/null || true)"

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg account "${account}" \
  --arg host "${host}" \
  --arg gitUserName "${current_git_user_name}" \
  --arg gitUserEmail "${current_git_user_email}" \
  --arg credentialHelper "${credential_helper}" \
  '{
    authenticated: $authenticated
  }
  + (if $account == "" then {} else {account: $account} end)
  + (if $host == "" then {} else {host: $host} end)
  + (if $gitUserName == "" then {} else {gitUserName: $gitUserName} end)
  + (if $gitUserEmail == "" then {} else {gitUserEmail: $gitUserEmail} end)
  + (if $credentialHelper == "" then {} else {credentialHelper: $credentialHelper} end)'
