---
name: git-worktrees
description: Create, locate, inspect, and safely remove linked Git worktrees. Use when the user wants an isolated branch checkout under a repository's .worktrees directory or needs to inspect or tear down an existing worktree.
---

# Git Worktrees

Keep linked worktrees at `<primary-checkout>/.worktrees/<name>`. This skill covers only their Git
lifecycle; the caller decides what runs inside them.

## Inspect

Run `git status --short --branch` and `git worktree list --porcelain`. The first `worktree` entry is
the primary checkout. Reuse a suitable registered worktree, and inspect its branch and status before
changing it. Never create a worktree inside another worktree.

## Create

Choose the name, branch, and base ref deliberately. Fetch first when the base is remote; use `HEAD`
when local commits must be included. From the primary checkout, create `.worktrees`, add
`/.worktrees/` to the repository's `info/exclude`, and run
`git worktree add -b <branch> .worktrees/<name> <base>`. Omit `-b` to check out an existing branch.

Never use `-B` or `--force` to bypass a collision. Stop and inspect it. Report the new worktree's
absolute path.

## Remove

Check the worktree for uncommitted files, unpushed commits, and unfinished Git operations. When it
is safe, run `git worktree remove <path>`. Do not use `rm -rf`; use `--force` only when the user
explicitly chooses to discard the reported state. Delete its branch separately only when requested
and safe, then report the final state.
