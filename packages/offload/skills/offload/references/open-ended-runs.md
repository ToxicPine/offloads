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

## Composing the remote command safely

`offloader` base64-encodes the command, so it arrives on the target byte-for-byte; the only quoting
hazard is local, while building the string. Never inline the task text into a single-quoted command
string — an apostrophe in the task breaks it. Build the script with quoted heredocs instead, then
pass the variable as one argument. This is the whole shape, here with Claude Code as the harness
(`skill_dir` is the `<skill-dir>` this skill resolves):

```bash
remote_script=$(cat <<'REMOTE'
task=$(cat <<'TASK'
<objective and completion condition - any quotes, $vars, and `backticks` are safe here>
TASK
)
status=complete
claude -p --permission-mode bypassPermissions "/goal ${task}" || status=failed
git add -A
git diff --cached --quiet || git commit -m "Offload Run Worktree State: status=${status}"
git push -u origin HEAD
[[ "${status}" == complete ]]
REMOTE
)
: "${skill_dir:?resolve to the directory containing the offload SKILL.md}"
"${skill_dir}/scripts/nix" run github:ToxicPine/offloads#offloader -- -- bash -lc "${remote_script}"
```

Rules that make this work first time:

- Keep every heredoc delimiter quoted (`<<'REMOTE'`) and distinct, and make sure no line of the
  task text equals a delimiter.
- The trailing git steps are the safety net that returns partial work even when the run dies
  mid-task: `status=failed` commits still push, and the final `[[ … ]]` propagates the failure back
  through the transport to the local caller.
- Keep the commit subject format exactly: `offloader-target` uses it to answer "is it done?" later.
- If `git status` on the target shows an unfinished merge or rebase, push what is committed and
  report rather than auto-committing over it.

## Claude Code

Claude Code runs goals from the CLI directly: `/goal` works in print mode, and one invocation runs
the loop to completion. The harness line inside the wrapper:

```bash
claude -p --permission-mode bypassPermissions "/goal ${task}"
```

- The goal condition may be up to 4,000 characters and must be checkable from the run's own output.
- Add `--max-budget-usd <n>` when the user wants a spend ceiling.
- A bounded task that needs no goal loop drops the `/goal` prefix:
  `claude -p --permission-mode bypassPermissions "${task}"`.
- Select behavior with `--model <name>` and `--effort <low|medium|high|xhigh|max>` when asked.
- Claude Code refuses to bypass permissions when running as root. The provisioned container runs
  work as its non-root user, so this only bites user-managed targets: dispatch as a non-root user
  there.

## Codex

Codex has no CLI goal command; its `/goal` exists only in the interactive TUI. **Default to
`codex exec`; use the app-server goal API below only when the user asks for a run measured in hours
or explicitly wants goal semantics (persisted objective, automatic continuation, budget tracking).**
The harness line inside the wrapper:

```bash
codex exec --sandbox danger-full-access "${task}"
```

- One `codex exec` call runs a full multi-step turn chain to completion, so most open-ended tasks
  fit a single call with a well-phrased goal and stopping condition in the prompt.
- Follow up in the same session with `codex exec resume --last '<follow-up>'`.
- Select behavior with `-m <model>` and `codex -c model_reasoning_effort=<level> exec …` when asked.

### Codex goal runs (app-server)

Codex's persisted-goal machinery is exposed only through the `codex app-server` JSON-RPC API
(newline-delimited JSON over stdio), so this path scripts a small client. Drive the run off goal
and turn status alone, in the script, never by reading the run's conversation: the event stream
carries the whole conversation, which is far too heavy to feed to a model.

Use this driver as the harness step: have the remote script write it to a file with another quoted
heredoc (e.g. `cat > .offload-goal-driver.sh <<'DRIVER' … DRIVER`), then run
`bash .offload-goal-driver.sh || status=failed` in place of the `claude`/`codex` line, keeping the
publish wrapper around it. It expects `${task}` from the enclosing script. It sets the goal, kicks
the first turn, then reacts only to status signals — `thread/goal/updated` notifications plus a
`thread/goal/get` poll after each completed turn, the same belt-and-braces the retired boondoggler
tool used in production:

```bash
coproc CODEX { codex app-server; }
app_pid=$!
trap 'kill "${app_pid}" 2>/dev/null || true' EXIT
send() { printf '%s\n' "${1}" >&"${CODEX[1]}"; }
finish_goal() {
  case "${1}" in
    complete) exit 0 ;;
    blocked|budgetlimited|paused|usagelimited) echo "goal ended: ${1}" >&2; exit 1 ;;
    *) : ;;
  esac
}
cfg=$(jq -cn --arg cwd "${PWD}" \
  '{cwd:$cwd,model:"gpt-5.5",approvalPolicy:"never",sandbox:"danger-full-access"}')
send '{"id":0,"method":"initialize","params":{"clientInfo":{"name":"offload","version":"1.0.0"}}}'
send '{"method":"initialized","params":{}}'
payload=$(jq -cn --argjson cfg "${cfg}" '{id:1,method:"thread/start",params:$cfg}')
send "${payload}"
thread=""
req_id=3
get_id=-1
while IFS= read -r line <&"${CODEX[0]}"; do
  if [[ -z "${thread}" ]]; then
    thread=$(jq -r 'try (.result.thread.id // .params.thread.id // .params.threadId // empty)' 2>/dev/null <<<"${line}") || thread=""
    if [[ -n "${thread}" ]]; then
      payload=$(jq -cn --arg t "${thread}" --arg o "${task}" \
        '{id:2,method:"thread/goal/set",params:{threadId:$t,objective:$o,status:"active"}}')
      send "${payload}"
    fi
    continue
  fi
  if jq -e 'select(.id==2 and .result)' >/dev/null 2>&1 <<<"${line}"; then
    payload=$(jq -cn --argjson cfg "${cfg}" --arg t "${thread}" \
      '{id:3,method:"thread/resume",params:($cfg+{threadId:$t})}')
    send "${payload}"
    continue
  fi
  goal_status=$(jq -r --arg t "${thread}" 'try (select(.method=="thread/goal/updated" and ((.params.threadId // .params.goal.threadId // "") == $t)) | (.params.goal.status // "" | ascii_downcase)) // empty' 2>/dev/null <<<"${line}") || goal_status=""
  finish_goal "${goal_status}"
  got_status=$(jq -r --argjson id "${get_id}" 'try (select(.id==$id) | (.result.goal.status // "" | ascii_downcase)) // empty' 2>/dev/null <<<"${line}") || got_status=""
  finish_goal "${got_status}"
  turn_status=$(jq -r 'try (select(.method=="turn/completed") | (.params.turn.status // "" | ascii_downcase)) // empty' 2>/dev/null <<<"${line}") || turn_status=""
  if [[ "${turn_status}" == "completed" ]]; then
    req_id=$((req_id + 1))
    get_id="${req_id}"
    payload=$(jq -cn --argjson id "${get_id}" --arg t "${thread}" \
      '{id:$id,method:"thread/goal/get",params:{threadId:$t}}')
    send "${payload}"
  elif [[ "${turn_status}" == "failed" || "${turn_status}" == "interrupted" ]]; then
    echo "turn ended: ${turn_status}" >&2
    exit 1
  fi
done
echo "app-server exited without a terminal goal status" >&2
exit 1
```

The thread must be persisted (not ephemeral) and idle when the goal is set; the driver satisfies
both by starting its own thread. `jq` must be on the target's `PATH` (it is on the provisioned
container).

## Choosing a harness

Use the harness the user asked for, otherwise whichever one is configured on the target. When both
are configured and the user has no preference: Claude Code is the simplest goal run (one CLI
invocation), and `codex exec` is the simplest bounded run. Say which harness was used when
reporting back.
