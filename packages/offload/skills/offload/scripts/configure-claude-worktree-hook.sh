#!/usr/bin/env bash
set -Eeuo pipefail

: "${remote_repo:?inject the absolute primary-checkout path before this script}"
[[ "${remote_repo}" = /* ]] || { echo "remote_repo must be absolute" >&2; exit 1; }
cd "${remote_repo}"

primary=$(git worktree list --porcelain | sed -n 's/^worktree //p;q')
primary_real=$(cd "${primary}" && pwd -P)
repo_real=$(pwd -P)
[[ "${primary_real}" == "${repo_real}" ]] \
  || { echo "refusing to configure a non-primary checkout: ${remote_repo}" >&2; exit 1; }
[[ ! -L .claude && (! -e .claude || -d .claude) ]] \
  || { echo "refusing unsafe .claude path" >&2; exit 1; }
mkdir -p .claude

settings=.claude/settings.local.json
[[ ! -L "${settings}" && (! -e "${settings}" || -f "${settings}") ]] \
  || { echo "refusing unsafe settings path: ${settings}" >&2; exit 1; }
if [[ -f "${settings}" ]]; then
  current=$(jq -ce \
    'select(type == "object" and ((has("hooks") | not) or (.hooks | type == "object")))' \
    "${settings}") \
    || { echo "refusing malformed or incompatible settings: ${settings}" >&2; exit 1; }
else
  current='{}'
fi

hook_command=$(cat <<'HOOK'
bash -c 'set -Eeuo pipefail
input=$(cat)
name=$(jq -er '\''.name | strings | select(length > 0)'\'' <<<"${input}")
cwd=$(jq -er '\''.cwd | strings | select(length > 0)'\'' <<<"${input}")
case "${name}" in .|..|*[!A-Za-z0-9._-]*) echo "unsafe worktree name: ${name}" >&2; exit 1;; *) :;; esac
repo=$(git -C "${cwd}" worktree list --porcelain | sed -n "s/^worktree //p;q")
bare=$(git -C "${repo}" rev-parse --is-bare-repository); test "${bare}" = false
worktree="${repo}/.worktrees/${name}"; branch="worktree-${name}"
exclude=$(git -C "${repo}" rev-parse --path-format=absolute --git-path info/exclude)
mkdir -p "$(dirname "${exclude}")" "${repo}/.worktrees"; touch "${exclude}"
grep -Fqx "/.worktrees/" "${exclude}" || printf "%s\n" "/.worktrees/" >>"${exclude}"
base="${CLAUDE_WORKTREE_BASE_REF:-}"
if test -z "${base}"; then git -C "${repo}" fetch origin >&2 && base=$(git -C "${repo}" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true); base="${base:-HEAD}"; fi
git -C "${repo}" worktree add -b "${branch}" "${worktree}" "${base}" >&2
cd "${worktree}"; pwd -P'
HOOK
)
desired=$(jq -cn --arg command "${hook_command}" \
  '[{hooks: [{type: "command", command: $command}]}]')

if jq -e '(.hooks? // {}) | has("WorktreeCreate")' <<<"${current}" >/dev/null; then
  jq -e --argjson desired "${desired}" '.hooks.WorktreeCreate == $desired' \
    <<<"${current}" >/dev/null \
    || { echo "different WorktreeCreate hook already exists; left ${settings} unchanged" >&2; exit 1; }
  result="already configured"
else
  tmp=$(mktemp "${settings}.XXXXXX")
  trap 'rm -f "${tmp}"' EXIT
  printf '%s\n' "${current}" | jq --argjson desired "${desired}" \
    '.hooks = (.hooks // {}) | .hooks.WorktreeCreate = $desired' > "${tmp}"
  mv "${tmp}" "${settings}"
  trap - EXIT
  result="configured"
fi

exclude=$(git rev-parse --path-format=absolute --git-path info/exclude)
grep -Fqx '/.claude/settings.local.json' "${exclude}" \
  || printf '%s\n' '/.claude/settings.local.json' >> "${exclude}"
printf '%s: %s\n' "${result}" "${settings}"
