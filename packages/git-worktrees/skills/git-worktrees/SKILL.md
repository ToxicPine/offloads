---
name: git-worktrees
description: Create, locate, inspect, and safely remove linked Git worktrees. Use when the user wants an isolated branch checkout under a repository's .worktrees directory or needs to inspect or tear down an existing worktree.
---

# Git Worktrees

Keep additional worktrees at `<repo>/.worktrees/<name>`.

## Inspect

Start by checking the current checkout and registered worktrees:

```bash
git status --short --branch
git worktree list --porcelain
```

Reuse a suitable existing worktree. Do not create a worktree inside another worktree. Before any
mutation, inspect the selected branch and path for unrelated work.

## Create

Run from the primary checkout. Choose the name, branch, and base ref from the task:

```bash
name=feature-auth
branch=feature/auth
base=origin/HEAD
repo_root=$(git rev-parse --show-toplevel)
worktree="${repo_root}/.worktrees/${name}"

exclude=$(git rev-parse --path-format=absolute --git-path info/exclude)
mkdir -p "$(dirname "${exclude}")" "${repo_root}/.worktrees"
touch "${exclude}"
grep -Fqx '/.worktrees/' "${exclude}" || printf '%s\n' '/.worktrees/' >> "${exclude}"

git fetch origin
git worktree add -b "${branch}" "${worktree}" "${base}"
printf '%s\n' "$(cd "${worktree}" && pwd -P)"
```

Use `HEAD` as the base when the new worktree must include local commits. To check out an existing
branch, omit `-b`:

```bash
git worktree add "${worktree}" "${branch}"
```

Never use `-B` or `--force` to hide a branch or path collision. Inspect the existing state first.

## Remove

Check for uncommitted files, unpushed commits, and unfinished Git operations:

```bash
git -C "${worktree}" status --short --branch
git -C "${worktree}" log -1 --oneline --decorate
git -C "${worktree}" branch -vv
```

When it is safe to remove:

```bash
git worktree remove "${worktree}"
git worktree prune --dry-run
```

Do not use `rm -rf`. Use `git worktree remove --force` only when the user explicitly chooses to
discard the reported state. Delete the branch separately only when requested and safe. Report the
absolute worktree path and final state.
