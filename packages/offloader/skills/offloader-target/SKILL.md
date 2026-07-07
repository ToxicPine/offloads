---
name: offloader-target
description: Use this to inspect long-running tasks the user dispatched to this machine through Offloader. This is relevant when asks about dispatched task status, dispatched task logs or output, whether a related command is still alive, or what branch/worktree a dispatched run used.
---

# Offloader Target Task State

You are on the machine where the dispatched command runs. Inspect local files and processes directly, then answer with the concrete state you found.

Offloader launches a command on this machine using a bare repo and worktree layout.
The source branch is pushed first, then the run branch is pushed as:

```text
offloader/<run-id>
```

Default target paths are:

```text
~/.remote-work/repos/<repo-path>/.bare
~/.remote-work/repos/<repo-path>/offloader-<run-id>
```

Useful environment names: `OFFLOADER_REPO_PATH`, `OFFLOADER_REMOTE_ROOT`, `OFFLOADER_WORKTREE_DIR`, `OFFLOADER_RUN_BRANCH`.

## Inspect Local State

List recent Offloader worktrees under the remote root:

```bash
root="${OFFLOADER_REMOTE_ROOT:-${HOME}/.remote-work}"
find "$root/repos" -path '*/.git' -not -path '*/.bare/*' -printf '%T@ %h\n' 2>/dev/null \
  | sort -nr \
  | head -20
```

Inspect the selected worktree:

```bash
worktree="${HOME}/.remote-work/repos/gh/OWNER/REPO/offloader-run-id"
git -C "$worktree" status --short --branch
git -C "$worktree" log -1 --oneline
```

Check recent file activity in a selected worktree:

```bash
find "$worktree" -xdev -type f -printf '%T@ %p\n' 2>/dev/null \
  | sort -nr \
  | head -40
```

Look for a process tied to that worktree:

```bash
pgrep -af "$worktree" || true
ps -eo pid,ppid,etime,stat,cmd --sort=etime | rg -F "$worktree" || true
```

## Local Branch Clues

When working locally in the source repo, these commands often identify the Offloader run branch or pushed state:

```bash
git branch --list 'offloader/*'
git log --all --decorate --oneline --grep='Worktree State: status=' -20
git remote -v
```

Offloader itself runs commands like:

```bash
offloader -- npm run dev
offloader --command 'npm run test'
```

Offloader writes the pushed repo state to a local worktree on this machine and runs the requested command there. Detached runs leave their output at `<worktree>.log`, and open-ended ones also leave `<worktree>.run.sh` (what was launched). Attached runs leave no log file of their own; for those, say so and report process state, worktree status, last commit, and recent file activity instead.

## Open-Ended Harness Runs

Open-ended dispatches run a coding harness CLI in the worktree, usually `claude -p "/goal ..."` or `codex exec ...`, wrapped so worktree state is committed and pushed when the run ends. They are normally detached with `setsid`, so expect no parent session. Read progress and the launched script directly:

```bash
worktree="${HOME}/.remote-work/repos/gh/OWNER/REPO/offloader-run-id"
tail -n 50 "${worktree}.log"
cat "${worktree}.run.sh"
```

Check whether a run is still alive:

```bash
pgrep -af 'claude|codex' || true
ps -eo pid,ppid,etime,stat,cmd --sort=etime | rg 'claude|codex' || true
```

Several runs can be live at once, and the command line rarely names the worktree. Attribute a harness process to a specific run by its working directory:

```bash
worktree="${HOME}/.remote-work/repos/gh/OWNER/REPO/offloader-run-id"
while IFS= read -r pid; do
  cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null) || cwd=""
  case "${cwd}" in
    "${worktree}"|"${worktree}"/*) ps -o pid,etime,cmd -p "${pid}" ;;
    *) : ;;
  esac
done < <(pgrep -f 'claude|codex' || true)
```

The wrapper's completion signal is a commit whose subject matches:

```text
Offload Run Worktree State: status=<status>
```

`status=complete` means the harness finished its goal; `status=failed` means it exited early and the commit holds partial work. Older runs used the subject prefix `Codex Goal Worktree State`. Find the latest outcome with:

```bash
worktree="${HOME}/.remote-work/repos/gh/OWNER/REPO/offloader-run-id"
git -C "${worktree}" log --decorate --oneline --grep='Worktree State: status=' -20
git -C "${worktree}" log -1 --format=fuller
```

Harness runs track state through git commits and live processes, not pidfiles or status files. Report what those signals show.
