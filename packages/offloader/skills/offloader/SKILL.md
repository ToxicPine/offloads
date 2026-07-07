---
name: offloader
description: Use for dispatching a command from the current git repo to a remote machine in order to offload work for execution.
---

# Offloader Dispatch Workflow

Use `offloader` when the user wants a command from the current git repository to run in a matching worktree on a remote target machine.

Run it from inside the source repository. Offloader pushes the current `HEAD` to the selected repo remote, pushes a run branch named `offloader/<run-id>`, reaches the target through a transport command, creates or refreshes the target worktree, and runs the requested command there.

Typical usage:

```bash
offloader -- npm run dev
offloader -- npm run test
offloader -- bash scripts/start.sh --port 3000
offloader --command 'npm run dev'
OFFLOADER_COMMAND='npm run test' offloader
```

## The transport

Offloader is provider-agnostic. It reaches the target through a **transport**: one local command that reads a script on stdin, runs it under `bash -s` on the remote, and forwards stdout, stderr, and exit status.

Set the transport with `OFFLOADER_TRANSPORT` or `--transport`. Multiple adapters ship with the project, and any command with the same stdin/stdout/stderr/exit-status contract can be used:

```bash
export OFFLOADER_TRANSPORT='offloader-ssh box.lab'              # plain SSH
export OFFLOADER_TRANSPORT='offloader-tailscale box.lab'        # Tailscale SSH
export OFFLOADER_TRANSPORT='offloader-fly --app my-app --machine 0123456789'  # Fly.io
offloader -- npm run test
```

The adapter named in the transport must be on `PATH`. For SSH and Tailscale, the first argument is the host; extra args pass through to the adapter. Offloader has no default transport, so one must be set before launch.

## Persistence

The dispatched command runs in the foreground of the transport session and dies with it if the connection drops. Detach anything that should outlive the connection — long tests, dev servers, agentic runs — with `setsid` (`nohup` on targets without it, such as macOS); the dispatch then returns immediately and the run's output lands beside the worktree:

```bash
run_cmd=$(cat <<'CMD'
setsid bash -lc "<command>" > "${PWD}.log" 2>&1 < /dev/null &
echo "detached: pid ${!}, log ${PWD}.log"
CMD
)
offloader --command "${run_cmd}"
```

Dispatch plainly (no wrapper) only for short commands watched live, where stdout and the exit status should flow back through the transport.

## Required Context

Before launching, confirm these are true:

- The current directory is inside the git repository the user wants to dispatch.
- A transport is configured via `OFFLOADER_TRANSPORT` (or `--transport`), and the named transport command is installed.
- The source repo has a usable git remote, or `OFFLOADER_REPO_URL` is set explicitly.
- The command is safe to run on the target worktree.

If the repo has no remote, set `OFFLOADER_REPO_URL`. If the desired remote is not the current upstream or `origin`, set `OFFLOADER_REMOTE_NAME`.

## Useful Overrides

- `OFFLOADER_REPO_ROOT` sets the source repo root when `$PWD` is not enough.
- `OFFLOADER_REPO_URL` sets the remote URL pushed to and cloned from.
- `OFFLOADER_REMOTE_NAME` selects which local git remote to use.
- `OFFLOADER_REPO_PATH` overrides the target repo path segment under `repos/`.
- `OFFLOADER_RUN_ID` fixes the run id instead of generating one.
- `OFFLOADER_WORKTREE_NAME` overrides the target worktree directory name. By default it is derived from the run branch, so `offloader/<run-id>` becomes `offloader-<run-id>`.
- `OFFLOADER_RUN_BRANCH` overrides the pushed run branch.
- `OFFLOADER_BASE_BRANCH` records the source branch used as the base branch.
- `OFFLOADER_REMOTE_ROOT` changes the target root, defaulting on the remote to `~/.remote-work`.
- `OFFLOADER_REMOTE_DIR`, `OFFLOADER_BARE_DIR`, and `OFFLOADER_WORKTREE_DIR` override the exact remote directories.
- `OFFLOADER_COMMAND` provides a shell command when not using `--command` or `-- COMMAND`.
- `OFFLOADER_TRANSPORT` sets the transport command; `--transport` overrides it per call.

## What To Report

After dispatching, report:

- The command that was launched.
- The run branch and worktree path when known.

```text
offloader/<run-id>
~/.remote-work/repos/<repo-path>/offloader-<run-id>
```

For later status checks on the target machine, use the `offloader-target` skill.
