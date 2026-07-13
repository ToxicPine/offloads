#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'claude-worktree-create: %s\n' "$*" >&2
  exit 1
}

input=$(cat)
name=$(jq -er '.name | strings | select(length > 0)' <<<"${input}") \
  || fail 'hook input has no worktree name'
cwd=$(jq -er '.cwd | strings | select(length > 0)' <<<"${input}") \
  || fail 'hook input has no working directory'

case "${name}" in
  . | .. | *[!A-Za-z0-9._-]*)
    fail "unsafe worktree name: ${name}"
    ;;
esac

source_root=$(git -C "${cwd}" rev-parse --show-toplevel) \
  || fail "not inside a Git worktree: ${cwd}"
repo_root=$(git -C "${source_root}" worktree list --porcelain \
  | awk '/^worktree / { print substr($0, 10); exit }')
[[ -n "${repo_root}" ]] || fail 'cannot locate the primary checkout'
[[ $(git -C "${repo_root}" rev-parse --is-bare-repository) == false ]] \
  || fail 'a normal primary checkout is required'

worktree_root="${repo_root}/.worktrees"
worktree="${worktree_root}/${name}"
branch="worktree-${name}"
[[ ! -e "${worktree}" && ! -L "${worktree}" ]] \
  || fail "worktree path already exists: ${worktree}"
git -C "${source_root}" show-ref --verify --quiet "refs/heads/${branch}" \
  && fail "branch already exists: ${branch}"

exclude=$(git -C "${source_root}" rev-parse --path-format=absolute --git-path info/exclude)
mkdir -p "$(dirname "${exclude}")" "${worktree_root}"
touch "${exclude}"
grep -Fqx '/.worktrees/' "${exclude}" || printf '%s\n' '/.worktrees/' >> "${exclude}"

base=${CLAUDE_WORKTREE_BASE_REF:-}
if [[ -z "${base}" ]]; then
  if git -C "${source_root}" remote get-url origin >/dev/null 2>&1; then
    if git -C "${source_root}" fetch origin >&2; then
      base=$(git -C "${source_root}" symbolic-ref --quiet --short refs/remotes/origin/HEAD \
        || true)
    fi
  fi
  base=${base:-HEAD}
fi

git -C "${source_root}" rev-parse --verify "${base}^{commit}" >/dev/null \
  || fail "base ref does not resolve to a commit: ${base}"
git -C "${source_root}" worktree add -b "${branch}" "${worktree}" "${base}" >&2

printf '%s\n' "$(cd "${worktree}" && pwd -P)"
