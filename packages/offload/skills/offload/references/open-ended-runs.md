# Open-ended runs with coding harnesses

An open-ended hand-off runs a coding harness (Claude Code or Codex) on the target machine. There is
no dedicated launcher tool: compose the harness's own CLI invocation, wrap it so it publishes its
result, and dispatch it through `offloader` like any other command. Machine-level assistant setup,
authentication, and remote steering are covered in `assistants-on-the-machine.md`.

The part you must get right is the task text. It needs two things:

**A goal with a verifiable stopping condition.** Phrase the task so the harness can tell when it is
done, e.g. "…; done when `npm test` passes and the README documents the new flag." Vague goals
produce runs that stop early or never stop. Also tell the harness, in the prompt, to commit its
work as it goes.

**The context the harness cannot see.** The remote harness starts blank: it has the repo at the
pushed commit and the task text, and none of the conversation that led here. Write the task as a
handoff brief, not a work order. Include what applies:

- constraints and preferences the user stated
- decisions already made and why, so the run does not relitigate them
- pointers to plans, issues, or docs already in the repo, instead of restating them

Sometimes it is also appropriate to include:

- what was tried and failed, so the run does not repeat it
- file paths to start from, and what not to touch or re-investigate

Length is never a reason to thin the brief; the heredoc composition below quotes task text of any
length safely.

The wrapper handles the rest. It ends by committing and pushing the worktree: `offloader` never
copies anything back, so results return only as commits on the run branch. And it runs the harness
non-interactively with approvals disabled, the expected posture on a disposable target, and not
one to repeat on a machine that matters.

## Choose the worktree before launch

Decide which workflow owns the checkout before starting the harness. A normal `offloader` dispatch
already creates a branch and worktree on the target, then starts the command inside it. Reuse that
current directory. Do not run `claude --worktree`, create a nested `.worktrees` directory, or ask
Codex to create another managed worktree inside it. The launch snippets below assume this normal
case and use the current `PWD` as the harness working directory.

When starting an open-ended run directly on the target instead, with no surrounding workflow that
already owns a checkout, use the installed `git-worktrees` skill first. Create or select
`<repo>/.worktrees/<name>`, choose the run branch and base ref deliberately, and then launch the
harness from the absolute path the skill reports:

```bash
worktree=<absolute path reported by the git-worktrees skill>
cd "${worktree}"
# Continue with the matching Claude Code or Codex recipe below; both use this PWD.
```

Claude Code can run directly in that existing worktree. If Claude Code itself owns creation, the
same skill documents its `WorktreeCreate` hook so Claude places the checkout under `.worktrees`.
That hook replaces Claude's default creator; do not combine it with a separately prepared checkout.
Codex only needs the selected directory as `cwd` and does not need to adopt it as Codex-managed.
Whichever workflow creates the worktree remains responsible for publishing and cleanup.

## Composing the remote command safely

The command string reaches the target byte-for-byte, so the only quoting hazard is local, while
building it. Never inline the task text into a single-quoted command
string — an apostrophe in the task breaks it. Build the script with quoted heredocs instead, then
pass the variable as one argument. This is the whole shape, here with Claude Code as the harness
(`skill_dir` is the `<skill-dir>` this skill resolves):

```bash
remote_script=''
while IFS= read -r line; do
  remote_script+="${line}"$'\n'
done <<'REMOTE'
set -Eeuo pipefail
log_file="${PWD}.log"
run_file="${PWD}.run.sh"
rm -f "${log_file}"
cat > "${run_file}" <<'RUN'
set -Eeuo pipefail
task=$(cat <<'TASK'
<objective, completion condition, and handoff context - any quotes, $vars, and `backticks` are safe here>
TASK
)
run_branch=$(git rev-parse --abbrev-ref HEAD)
run_commit=$(git rev-parse HEAD)
echo "worktree: ${run_branch} @ ${run_commit}"
status=complete
if ! claude -p --permission-mode bypassPermissions --output-format stream-json --verbose \
  "/goal ${task}"; then
  status=failed
fi
git add -A
if ! git diff --cached --quiet; then
  git commit -m "Offload Run Worktree State: status=${status}"
fi
git push -u origin HEAD
[[ "${status}" == complete ]]
RUN
if command -v setsid >/dev/null 2>&1; then
  setsid bash "${run_file}" > "${log_file}" 2>&1 < /dev/null &
else
  nohup bash "${run_file}" > "${log_file}" 2>&1 < /dev/null &
fi
run_pid=$!
return_structured_error_if_seen() {
  local error_line
  [[ -r "${log_file}" ]] || return 0
  error_line=$(jq -Rrs '
    first(split("\n")[] as $line
      | ($line | fromjson?)
      | select(
          (.error? != null) or
          (.type == "result" and .is_error == true) or
          (.type == "system" and .subtype == "api_retry") or
          (.method == "error") or
          (.method == "turn/completed" and
            (.params.turn.status == "failed" or .params.turn.status == "interrupted")))
      | $line) // empty
  ' "${log_file}" 2>/dev/null || true)
  if [[ -n "${error_line}" ]]; then
    echo "run reported during launch check: ${error_line}; log ${log_file}" >&2
    exit 1
  fi
}
require_running() {
  local run_rc=0
  kill -0 "${run_pid}" 2>/dev/null && return 0
  wait "${run_pid}" || run_rc=$?
  echo "run stopped during launch check (exit ${run_rc}); log ${log_file}" >&2
  exit 1
}
launch_deadline=$((SECONDS + 3))
while ((SECONDS < launch_deadline)); do
  return_structured_error_if_seen
  require_running
  sleep 0.1
done
return_structured_error_if_seen
require_running
echo "run started: pid ${run_pid}, log ${log_file}"
REMOTE
: "${skill_dir:?resolve to the directory containing the offload SKILL.md}"
"${skill_dir}/scripts/nix" run github:ToxicPine/offloads#offloader -- -- bash -lc "${remote_script}"
```

The `RUN` script performs and publishes the work. The `REMOTE` script detaches it and waits briefly
to confirm that it started. See the `offloader` skill's Persistence section for the attached
alternative. Rules that make this work first time:

- Keep every heredoc delimiter quoted (`<<'REMOTE'`) and distinct, and make sure no line of the
  task text equals a delimiter.
- The trailing git steps are the safety net that returns partial work even when the run dies
  mid-task: `status=failed` commits still push.
- Keep the commit subject format exactly: `offloader-target` uses it to answer "is it done?" later.
- The `worktree:` echo is the state check: the first line of `<worktree>.log` must name the run
  branch and the same commit as the local `git rev-parse HEAD` that was dispatched.
- If `git status` on the target shows an unfinished merge or rebase, push what is committed and
  report rather than auto-committing over it.

The dispatch waits about three seconds. It prints `run started:` when the process remains live and
no structured error appears; otherwise it returns the error or early exit. For setup or
authentication failures, follow `assistants-on-the-machine.md` rather than logging in inside the
run. Later progress lives in `<worktree>.log`, and the outcome arrives as a status commit on the run
branch. `<worktree>.run.sh` records what was launched. There is no separate launch-status artifact.

## Claude Code

Claude Code runs goals from the CLI directly: `/goal` works in print mode, and one invocation runs
the loop to completion. Keep `--output-format stream-json --verbose` so launch failures appear in
the output being checked. The harness invocation inside the wrapper is:

```bash
task='<objective and handoff context>'
claude -p --permission-mode bypassPermissions --output-format stream-json --verbose \
  "/goal ${task}"
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

Codex's persisted-goal machinery is exposed only through the `codex app-server` JSON-RPC API
(newline-delimited JSON over stdio), so this path scripts a small client. The driver follows goal
status rather than reading the run's conversation.

Keep the outer `REMOTE` layer above unchanged. For Codex, replace its `RUN` heredoc body with the
publish wrapper below, then put the following driver block at its placeholder. The temporary driver
stays outside the worktree, and `task` is exported for the child process.

```bash
set -Eeuo pipefail
task=$(cat <<'TASK'
<objective, completion condition, and handoff context>
TASK
)
export task
run_branch=$(git rev-parse --abbrev-ref HEAD)
run_commit=$(git rev-parse HEAD)
echo "worktree: ${run_branch} @ ${run_commit}"
driver_file=$(mktemp)
cat > "${driver_file}" <<'DRIVER'
# ... the driver script below ...
DRIVER
status=complete
if ! bash "${driver_file}"; then
  status=failed
fi
rm -f "${driver_file}"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "Offload Run Worktree State: status=${status}"
fi
git push -u origin HEAD
[[ "${status}" == complete ]]
```

The driver sets the goal, resumes the thread, and follows goal status until the run ends. It also
copies app-server replies to the run log so the outer launch check can return an error.

```bash
set -Eeuo pipefail
: "${task:?export task before running the driver}"
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
    complete)
      exit 0
      ;;
    blocked|budgetlimited|paused|usagelimited)
      echo "goal ended: ${1}" >&2
      exit 1
      ;;
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
  printf '%s\n' "${line}"
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
the `offloader` skill's Concurrent Dispatches section). Claude Code sessions are likewise scoped
to the directory they ran in. The wrapper and driver write nothing shared: the driver file is a
fresh `mktemp` path, while `<worktree>.run.sh` and `<worktree>.log` derive from each run's own
worktree path.
