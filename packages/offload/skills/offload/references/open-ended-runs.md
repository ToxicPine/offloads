# Open-ended runs with coding harnesses

An open-ended hand-off runs a coding harness (Claude Code or Codex) on the target machine. There is
no dedicated launcher tool: compose the harness's own CLI invocation, wrap it so it publishes its
result, and dispatch it through `offloader` like any other command. The harness must already be
configured on the target through `offloader-configurator`; see `assistants-on-the-machine.md`.

Every open-ended run needs three things:

- **A goal with a verifiable stopping condition.** Phrase the task so the harness can tell when it
  is done, e.g. "…; done when `npm test` passes and the README documents the new flag." Vague goals
  produce runs that stop early or never stop.
- **A publish step.** `offloader` pushes work in but never pulls results back. Tell the harness in
  the prompt to commit its work as it goes, and wrap the invocation so worktree state is committed
  and pushed on the run branch whether the run succeeds or fails.
- **No interactive prompts.** Use the harness's non-interactive mode with approvals disabled. The
  target is a disposable container, so that is the expected posture there; do not disable approvals
  this way on a machine that matters.

## The publish wrapper

Compose the remote command in this shape. The trailing git steps are the safety net that returns
partial work even when the run dies mid-task:

```bash
status=complete
<harness command> || status=failed
git add -A
git diff --cached --quiet || git commit -m "Offload Run Worktree State: status=${status}"
git push -u origin HEAD
```

Keep the commit subject format exactly: `offloader-target` uses it to answer "is it done?" later.
If `git status` on the target shows an unfinished merge or rebase, push what is committed and
report rather than auto-committing over it.

## Claude Code

Claude Code runs goals from the CLI directly: `/goal` works in print mode, and one invocation runs
the loop to completion.

```bash
claude -p --permission-mode bypassPermissions \
  "/goal <objective and completion condition>"
```

- The goal condition may be up to 4,000 characters and must be checkable from the run's own output.
- Bound the run when the user wants a ceiling: `--max-turns <n>` or `--max-budget-usd <n>`.
- A bounded task that needs no goal loop is just `claude -p "<task>"`.
- Select behavior with `--model <name>` and `--effort <low|medium|high|xhigh|max>` when asked.

## Codex

Codex has no CLI goal command; its `/goal` exists only in the interactive TUI. **Default to
`codex exec`; use the app-server goal API below only when the user asks for a run measured in hours
or explicitly wants goal semantics (persisted objective, automatic continuation, budget tracking).**
Headless Codex is `codex exec`:

```bash
codex exec --sandbox danger-full-access '<task>'
```

- One `codex exec` call runs a full multi-step turn chain to completion, so most open-ended tasks
  fit a single call with a well-phrased goal and stopping condition in the prompt.
- Follow up in the same session with `codex exec resume --last '<follow-up>'`.
- Select behavior with `-m <model>` and `codex -c model_reasoning_effort=<level> exec …` when asked.

### Codex goal runs (app-server)

Codex's persisted-goal machinery is exposed only through the `codex app-server` JSON-RPC API, and
using it means scripting a small client. Speak newline-delimited JSON over stdio:

1. Send `initialize` (any `clientInfo`), then the `initialized` notification.
2. Send `thread/start` with `{cwd, model, approvalPolicy: "never", sandbox: "danger-full-access"}`.
3. Send `thread/goal/set` with `{threadId, objective, status: "active"}`. The thread must be
   persisted (not ephemeral) and idle.
4. Send `thread/resume` with the same config plus `threadId` to kick the first turn.
5. Drive the run off the goal status alone, in the script (`jq`), never by reading the run's
   conversation: match `thread/goal/updated` notifications (or poll `thread/goal/get`) and discard
   every other event. The event stream carries the whole conversation, which is far too heavy to
   feed to a model. `complete` means success; `blocked`, `budgetLimited`, and `usageLimited` mean
   the run stopped needing intervention; a `failed` turn ends the run.

Keep the publish wrapper around the whole client so the worktree state still comes back.

## Choosing a harness

Use the harness the user asked for, otherwise whichever one is configured on the target. When both
are configured and the user has no preference: Claude Code is the simplest goal run (one CLI
invocation), and `codex exec` is the simplest bounded run. Say which harness was used when
reporting back.

## Dispatching

Combine the pieces and hand the whole wrapped command to `offloader`:

```bash
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- bash -lc '<publish-wrapped harness command>'
```
