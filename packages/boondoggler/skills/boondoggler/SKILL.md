---
name: boondoggler
description: "Use when launching a persistent Codex goal run with `boondoggler` from a prompt on stdin."
---

# Boondoggler Workflow

Use `boondoggler` when the user wants to hand a prompt to Codex as a goal and let it run from a chosen working tree.

Boondoggler reads the full prompt from stdin. Empty prompts fail.

```bash
printf '%s\n' 'Implement the requested change and run tests' | boondoggler
```

Run it from the repository or directory that should become the Codex working root. Override that root with `ROOT` when needed:

```bash
ROOT=/path/to/repo printf '%s\n' 'Run the migration checks' | boondoggler
```

## Behavior

Boondoggler starts `codex app-server`, creates a thread in the selected working directory, sets the stdin prompt as the active goal, and resumes the thread with:

```text
model: gpt-5.5
approvalPolicy: never
sandbox: danger-full-access
```

It prints progress events from Codex, including thread id, goal status, turn start/completion, and selected message text.

## Useful Environment

- `ROOT` selects the Codex working directory. It defaults to `$PWD`.
- `BOONDOGGLE_MODEL` overrides the thread model. It defaults to `gpt-5.5`.
- `BOONDOGGLE_APPROVAL_POLICY` overrides the approval policy. It defaults to `never`; `--ask-for-approval` is accepted as an alias.
- `BOONDOGGLE_SANDBOX` overrides the thread sandbox. It defaults to `danger-full-access`.
- `BOONDOGGLE_EFFORT` sets the reasoning effort when provided; `--reasoning-effort` is accepted as an alias.
- `BOONDOGGLE_PERSONALITY` sets the Codex personality when provided.
- `BOONDOGGLE_SUMMARY` sets the summary preference when provided.
- `BOONDOGGLE_THREAD_CONFIG_JSON` merges an additional JSON object into the `thread/start` and `thread/resume` params. Values in this object override the named defaults.
- `BOONDOGGLE_PROFILE` passes top-level `--profile-v2` to Codex when provided.
- `BOONDOGGLE_LISTEN` passes `--listen` to `codex app-server` when provided.
- `GIT_PUBLISH_ON_GOAL_SUCCESS`, `GIT_PUBLISH_ON_GOAL_FAILURE`, and `GIT_PUBLISH_ON_UNEXPECTED_EXIT` control whether Boondoggler commits and pushes worktree state for those outcomes.
- `GIT_COMMIT_MESSAGE` overrides the status commit subject prefix. It defaults to `Codex Goal Worktree State`.

## Reporting

After launching Boondoggler, report:

- The working root.
- The task or prompt summary.
- The thread id if Boondoggler printed one.

If the user later asks about progress, use the `boondoggler-runs` skill when it is available.
