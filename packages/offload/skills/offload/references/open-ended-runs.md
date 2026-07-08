# Open-ended runs with coding harnesses

An open-ended hand-off runs a coding harness (Claude Code or Codex) on the target machine. There is
no dedicated launcher tool: compose the harness's own CLI invocation, wrap it so it publishes its
result, and dispatch it through `offloader` like any other command. The harness must already be
configured on the target through `offloader-configurator`; see `assistants-on-the-machine.md`.

Two things to get right when composing, both inside the task text:

**A goal with a verifiable stopping condition.** Phrase the task so the harness can tell when it is
done, e.g. "…; done when `npm test` passes and the README documents the new flag." Vague goals
produce runs that stop early or never stop. Also tell the harness, in the prompt, to commit its
work as it goes.

**The context the harness cannot see.** The remote harness starts blank: it has the repo at the
pushed commit and the task text, and none of the conversation that led here. Write the task as a
handoff brief, not a work order. Include what applies:

- constraints and preferences the user stated, and the definition of done
- decisions already made and why, so the run does not relitigate them
- what was tried and failed, so the run does not repeat it
- file paths to start from, and what not to touch or re-investigate
- pointers to plans, issues, or docs already in the repo, instead of restating them

The heredoc below makes task text of any length safe to compose, so never thin the brief to dodge
quoting. A goal without its context produces a run that redoes what the conversation already
settled.

The rest is already in the shape below: the wrapper commits and pushes the result because
`offloader` never pulls anything back, and the harness runs non-interactively with approvals
disabled — the expected posture on a disposable target, and not one to repeat on a machine that
matters.

## Composing the remote command safely

The command string reaches the target byte-for-byte, so the only quoting hazard is local, while
building it. Never inline the task text into a single-quoted command
string — an apostrophe in the task breaks it. Build the script with quoted heredocs instead, then
pass the variable as one argument. This is the whole shape, here with Claude Code as the harness
(`skill_dir` is the `<skill-dir>` this skill resolves):

```bash
remote_script=$(cat <<'REMOTE'
cat > "${PWD}.run.sh" <<'RUN'
task=$(cat <<'TASK'
<objective, completion condition, and handoff context - any quotes, $vars, and `backticks` are safe here>
TASK
)
echo "worktree: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse HEAD)"
status=complete
claude -p --permission-mode bypassPermissions "/goal ${task}" || status=failed
git add -A
git diff --cached --quiet || git commit -m "Offload Run Worktree State: status=${status}"
git push -u origin HEAD
[[ "${status}" == complete ]]
RUN
setsid bash "${PWD}.run.sh" > "${PWD}.log" 2>&1 < /dev/null &
echo "run detached: pid ${!}, log ${PWD}.log"
REMOTE
)
: "${skill_dir:?resolve to the directory containing the offload SKILL.md}"
"${skill_dir}/scripts/nix" run github:ToxicPine/offloads#offloader -- -- bash -lc "${remote_script}"
```

Two layers, one job each: the `RUN` script is the run itself — task, harness, publish wrapper —
and the `REMOTE` script only writes it down and launches it detached, so the run survives
disconnects (the mechanism, and the attached alternative for short watched runs, are in the
`offloader` skill's Persistence section). Rules that make this work first time:

- Keep every heredoc delimiter quoted (`<<'REMOTE'`) and distinct, and make sure no line of the
  task text equals a delimiter.
- The trailing git steps are the safety net that returns partial work even when the run dies
  mid-task: `status=failed` commits still push.
- Keep the commit subject format exactly: `offloader-target` uses it to answer "is it done?" later.
- The `worktree:` echo is the state check: the first line of `<worktree>.log` must name the run
  branch and the same commit as the local `git rev-parse HEAD` that was dispatched.
- If `git status` on the target shows an unfinished merge or rebase, push what is committed and
  report rather than auto-committing over it.

The dispatch returns as soon as the run starts, echoing the pid and log path. The outcome arrives
as the status commit on the run branch; progress lives in `<worktree>.log`, and `<worktree>.run.sh`
records what was launched — both beside the worktree, per-run unique, never swept into a commit.

## Claude Code

Claude Code runs goals from the CLI directly: `/goal` works in print mode, and one invocation runs
the loop to completion. The harness line inside the wrapper:

```bash
claude -p --permission-mode bypassPermissions "/goal ${task}"
```

- The goal condition may be up to 4,000 characters and must be checkable from the run's own output.
- When the brief outgrows that limit, keep the `/goal` text to the objective and stopping
  condition, write the rest from the `RUN` script to `"${PWD}.brief.md"` with its own quoted
  heredoc (beside the worktree like the log, never swept into a commit), and open the goal with
  "Read <worktree>.brief.md before starting."
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

Use this driver as the harness step. The `RUN` script for this variant is the publish wrapper
with the harness line swapped for a temp-file driver — written **outside the worktree** (never
inside it, where `git add -A` would sweep it into the status commit), with `task` exported, since
the driver runs as a child process and an unexported `task` would arrive empty. Launch it detached
like any other run:

```bash
task=$(cat <<'TASK'
<objective, completion condition, and handoff context>
TASK
)
export task
echo "worktree: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse HEAD)"
driver_file=$(mktemp)
cat > "${driver_file}" <<'DRIVER'
# ... the driver script below ...
DRIVER
status=complete
bash "${driver_file}" || status=failed
rm -f "${driver_file}"
git add -A
git diff --cached --quiet || git commit -m "Offload Run Worktree State: status=${status}"
git push -u origin HEAD
[[ "${status}" == complete ]]
```

The driver itself sets the goal, kicks the first turn, then reacts only to status signals —
`thread/goal/updated` notifications plus a `thread/goal/get` poll after each completed turn. Any
error response is terminal, so a rejected request fails the run instead of hanging it:

```bash
rpc_dir=$(mktemp -d)
mkfifo "${rpc_dir}/in" "${rpc_dir}/out"
codex app-server < "${rpc_dir}/in" > "${rpc_dir}/out" &
app_pid=$!
trap 'kill "${app_pid}" 2>/dev/null || true; rm -rf "${rpc_dir}"' EXIT
exec 3> "${rpc_dir}/in" 4< "${rpc_dir}/out"
trap '' PIPE
send() { printf '%s\n' "${1}" >&3; }
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
get_id=3
while IFS= read -r line <&4; do
  rpc_error=$(jq -r 'try (.error.message // empty)' 2>/dev/null <<<"${line}") || rpc_error=""
  if [[ -n "${rpc_error}" ]]; then
    echo "app-server error: ${rpc_error}" >&2
    exit 1
  fi
  if [[ -z "${thread}" ]]; then
    thread=$(jq -r 'try (.result.thread.id // .params.thread.id // .params.threadId // empty)' 2>/dev/null <<<"${line}") || thread=""
    if [[ -n "${thread}" ]]; then
      payload=$(jq -cn --arg t "${thread}" --arg o "${task}" \
        '{id:2,method:"thread/goal/set",params:{threadId:$t,objective:$o,status:"active"}}')
      send "${payload}"
    fi
    continue
  fi
  event=$(jq -r --arg t "${thread}" --argjson gid "${get_id}" '
    if .id == 2 and .result then "ack|"
    elif .method == "thread/goal/updated" and ((.params.threadId // .params.goal.threadId // "") == $t)
      then "goal|" + ((.params.goal.status // "") | ascii_downcase)
    elif .id == $gid and .result.goal
      then "goal|" + ((.result.goal.status // "") | ascii_downcase)
    elif .method == "turn/completed"
      then "turn|" + ((.params.turn.status // "") | ascii_downcase)
    else empty end' 2>/dev/null <<<"${line}") || event=""
  value="${event#*|}"
  case "${event%%|*}" in
    ack)
      payload=$(jq -cn --argjson cfg "${cfg}" --arg t "${thread}" \
        '{id:3,method:"thread/resume",params:($cfg+{threadId:$t})}')
      send "${payload}"
      ;;
    goal)
      finish_goal "${value}"
      ;;
    turn)
      if [[ "${value}" == "completed" ]]; then
        get_id=$((get_id + 1))
        payload=$(jq -cn --argjson id "${get_id}" --arg t "${thread}" \
          '{id:$id,method:"thread/goal/get",params:{threadId:$t}}')
        send "${payload}"
      elif [[ "${value}" == "failed" || "${value}" == "interrupted" ]]; then
        echo "turn ended: ${value}" >&2
        exit 1
      fi
      ;;
    *) : ;;
  esac
done
echo "app-server exited without a terminal goal status" >&2
exit 1
```

The thread must be persisted (not ephemeral) and idle when the goal is set; the driver satisfies
both by starting its own thread. The driver needs `jq` on the target's `PATH` (it is on the
provisioned container).

## Simultaneous runs

Concurrent dispatches are isolated by the offloader layout — own branch, own worktree per run (see
the `offloader` skill's Concurrent Dispatches section). At the harness level the rule is session
scoping: `codex exec resume --last` picks the most recent session **for its working directory**, so
run it from that run's worktree — from anywhere else (or with `--all`) it can resume a different
run's session. Claude Code sessions are likewise scoped to the directory they ran in. The wrapper
and driver write nothing shared: the driver file is a fresh `mktemp` path, and `<worktree>.run.sh`
and `<worktree>.log` derive from each run's own worktree path.

## Choosing a harness

Prefer, in order: the harness the user asked for; the one this agent is itself running in
(comparable model), if configured on the target; whichever is configured. When reporting back, say
which was used only if it differs from the harness dispatching the run.
