---
name: git-worktrees
description: Create, clone, inspect, and safely remove Git repositories and linked worktrees with git and gh. Use when the user asks to create or clone a GitHub repository, isolate work on a branch, create or select a worktree, inspect or remove worktrees, or align Claude Code and Codex on a repository-local .worktrees layout.
---

# Git Worktrees

Use ordinary Git repositories and linked worktrees. Keep each repository's additional worktrees at
`<repo>/.worktrees/<name>` so a harness can be launched with that exact directory as its working
directory.

## Decide who owns the worktree

Inspect before changing anything:

```bash
git status --short --branch
git worktree list --porcelain
```

- Reuse the current checkout when Offloader, Codex, Claude Code, or another surrounding workflow
  already created it. Do not create a worktree inside that worktree.
- Create a worktree only when no surrounding workflow owns one and isolation is useful or requested.
- Leave publication and cleanup to the workflow that created the worktree. Do not let two systems
  independently manage the same directory.
- Report the selected worktree's absolute path when finished.

## Clone or create a repository

Check `gh auth status` before a GitHub write. If authentication is missing, tell the user what is
needed instead of starting an unrelated login flow.

Clone an existing GitHub repository as a normal checkout:

```bash
gh repo clone OWNER/REPO REPO
cd REPO
```

For a new repository, confirm its owner, name, and visibility first. Create the local checkout, then
connect it to GitHub:

```bash
mkdir REPO
cd REPO
git init -b main
gh repo create OWNER/REPO --private --source=. --remote=origin
```

Replace `--private` with the visibility the user chose. Commit before the first
`git push -u origin HEAD`; do not invent initial files or publish an empty commit unless requested.

## Create or select a worktree

Run these commands from the repository's primary checkout. Choose the name, branch, and base ref
from the task; do not silently reset or reuse a branch with unrelated work.

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

Use `HEAD` as the base when the new worktree must include unpushed local commits. To check out an
existing branch, omit `-b`:

```bash
git worktree add "${worktree}" "${branch}"
```

If the current directory may already be a linked worktree, use `git worktree list --porcelain` to
locate the primary checkout instead of treating the current root as `<repo>`. Never use `-B` or
`--force` merely to make a collision disappear; inspect the existing branch and worktree first.

## Inspect and remove worktrees

Inspect both the registry and the selected checkout:

```bash
git worktree list --porcelain
git -C "${worktree}" status --short --branch
git -C "${worktree}" log -1 --oneline --decorate
git -C "${worktree}" branch -vv
```

Before removal, surface uncommitted files, unpushed commits, or an unfinished merge or rebase. If
the worktree is safe to remove:

```bash
git worktree remove "${worktree}"
git worktree prune --dry-run
```

Do not use `rm -rf`. Use `git worktree remove --force` only when the user explicitly chooses to
discard the reported state. Removing a worktree does not require deleting its branch; delete the
branch separately only when requested and safe.

## Align Claude Code and Codex

Codex understands a linked worktree when that exact absolute path is supplied as the process or
thread `cwd`. It need not become a Codex-managed worktree.

Claude Code can also be launched directly from an existing worktree. When Claude Code should own
creation through `--worktree`, `EnterWorktree`, or `isolation: worktree`, configure its
`WorktreeCreate` hook to use the bundled creator. Add this as the sole creation handler under the
appropriate user or project settings, preserving unrelated settings:

```json
{
  "hooks": {
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.claude/skills/git-worktrees/scripts/claude-worktree-create.sh\""
          }
        ]
      }
    ]
  }
}
```

The creator reads Claude's `name` and `cwd`, creates
`<repo>/.worktrees/<name>` on `worktree-<name>`, and prints only its absolute path on stdout. It
fetches `origin` and starts from `origin/HEAD`, falling back to the launch checkout's `HEAD` when a
fresh remote base is unavailable. Set `CLAUDE_WORKTREE_BASE_REF=HEAD` in the hook command when
Claude-owned worktrees must inherit local unpushed state, or set it to another explicit ref.

`WorktreeCreate` replaces Claude Code's default creation logic; it does not run before or after the
default creator. Consequently, Claude does not process `.worktreeinclude` or its built-in base-ref
setting afterward. If ignored local files are needed, copy the explicitly approved files inside a
customized hook after `git worktree add`. Never copy secrets implicitly. Claude recognizes the
result as a Git worktree and handles its normal Git cleanup, so no custom `WorktreeRemove` hook is
needed for this creator.
