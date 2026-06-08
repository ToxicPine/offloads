#!/usr/bin/env bash
set -euo pipefail

authenticated=false
account=""
host=""

if gh auth status --hostname github.com >/dev/null 2>&1; then
  authenticated=true
  host="github.com"
  account="$(gh api user --jq .login 2>/dev/null || true)"
fi

git_user_name="$(git config --global --get user.name 2>/dev/null || true)"
git_user_email="$(git config --global --get user.email 2>/dev/null || true)"
credential_helper="$(git config --global --get credential.helper 2>/dev/null || true)"

jq -n \
  --argjson authenticated "${authenticated}" \
  --arg account "${account}" \
  --arg host "${host}" \
  --arg gitUserName "${git_user_name}" \
  --arg gitUserEmail "${git_user_email}" \
  --arg credentialHelper "${credential_helper}" \
  '{
    authenticated: $authenticated
  }
  + (if $account == "" then {} else {account: $account} end)
  + (if $host == "" then {} else {host: $host} end)
  + (if $gitUserName == "" then {} else {gitUserName: $gitUserName} end)
  + (if $gitUserEmail == "" then {} else {gitUserEmail: $gitUserEmail} end)
  + (if $credentialHelper == "" then {} else {credentialHelper: $credentialHelper} end)'
