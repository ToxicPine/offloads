# Context Carryover for Offloaded Agent Tasks — Research Notes

Research into how conversation context from the local session should travel to the
remote assistant that executes an offloaded task. Compiled 2026-07-07 from three
parallel investigations: Claude Code session/compaction internals (empirically
verified on a live install), Codex CLI internals (source-verified against
openai/codex @ `cca16a10`, 2026-07-06), and cross-industry prior art.

## 1. The gap in the current skill text

Nothing in `offload`, `offloader`, `boondoggler`, or the reference docs tells the
dispatching agent that the remote assistant starts with **zero conversation
context**. The open-ended path is:

```bash
printf "%s" "<task>" | nix run github:ToxicPine/offloads#boondoggler
```

Whatever the local agent happens to write as `<task>` is the *entire* context the
remote Codex/Claude instance ever sees. The `offload` skill's `argument-hint`
("plain description of the work to hand off") if anything nudges toward a thin
prompt. The only context the skills do carry deliberately is credential/repo
state (`offloader-configurator`), never conversational state.

This matters because the remote model is a blank slate plus a prompt string —
the same situation Anthropic documents for its own subagents ("Subagents receive
only this system prompt plus basic environment details… not the full Claude Code
system prompt", code.claude.com/docs/en/sub-agents), and the same failure mode
Anthropic's multi-agent research post identifies: short task descriptions caused
duplicated work, gaps, and misinterpretation; the fix was explicit objectives,
constraints, and task boundaries.

A key observation: at dispatch time, the local agent **already holds the full
conversation in its context window**. The cheapest, most robust carryover
mechanism is therefore a skill-text instruction — "serialize what matters into
the prompt" — with machinery (compaction borrowing, transcript copy) reserved
for fidelity beyond what fits in a brief.

## 2. Strategy A — Goal-conditioned handoff brief (prompt-only, no machinery)

**Verdict: do this unconditionally; it is the industry consensus.**

- Amp (Sourcegraph) **removed compaction entirely** in favor of `/handoff`: a
  goal for the next thread is stated, and a model extracts *what matters for
  that goal* from the current thread, producing a draft prompt + relevant-file
  list that a human reviews before dispatch (ampcode.com/news/handoff).
  Rationale: goal-conditioned extraction beats generic summarization, which
  "stacks summary on top of summary."
- Claude Code's own docs recommend exactly this over transcript shipping:
  "Capture the results you need … and pass them into a fresh session's prompt.
  This is often more robust than shipping transcript files around"
  (code.claude.com/docs/en/agent-sdk/sessions).
- Claude Code web's answer to the same gap is "plan locally, execute remotely" —
  a structured plan artifact, not transcript transfer. GitHub Copilot's coding
  agent treats the *issue* as the brief. Jules/Devin push standing context into
  repo files (AGENTS.md / Knowledge) and keep prompts goal-shaped.

**Brief checklist** (fields attested across the vendors' own compaction
templates — Claude Code, Codex, OpenCode — plus community HANDOFF.md patterns):

1. Goal for this run (goal-conditioned, not a recap)
2. Task boundaries / non-goals — what NOT to touch or re-investigate
3. Definition of done + expected output shape
4. Constraints and user preferences stated in the conversation
5. Decisions made **and why**
6. State of work: done / in progress / next steps
7. Relevant files (paths the remote agent should read first)
8. What was tried and failed — absent from most vendor compaction templates,
   but community handoff consensus; prevents repeated dead ends
9. Repo/environment facts: base branch, last commit, "uncommitted changes do
   not travel" (offloader pushes HEAD — same boundary Cursor and Claude Code
   web enforce)
10. Pointers instead of copies — link to issues/ADRs/plan files already in the
    repo rather than re-serializing them
11. Escape hatch: where fuller context lives if the brief is insufficient
    (see Strategy D)

The verbatim Codex compaction prompt (`codex-rs/prompts/templates/compact/prompt.md`)
is itself a ready-made template: "Create a handoff summary for another LLM that
will resume the task. Include: current progress and key decisions… constraints
or user preferences… what remains to be done… critical data/examples/references."

## 3. Strategy B — Borrow native compaction from the harnesses

**Verdict: feasible on both harnesses; useful as an automated brief generator,
but goal-conditioned summarization is strictly better when available.**

### Claude Code (empirically verified on 2.1.202)

- `/compact` works headlessly: `claude -p --resume <session-id> "/compact focus on X"`.
  Fails safely on short sessions ("Not enough messages to compact").
- The summary is written into the session JSONL as a `user`-type entry with
  `"isCompactSummary": true`; the text is already handoff-shaped (Primary
  Request and Intent, Key Technical Concepts, Files and Code Sections, Errors
  and fixes, …). Extract with:

  ```bash
  jq -r 'select(.isCompactSummary==true)
         | .message.content
         | if type=="string" then . else map(.text)|join("\n") end' \
     ~/.claude/projects/<munged-cwd>/<session-id>.jsonl | tail -n +2
  ```

  (Take the last such entry; munged-cwd = absolute cwd with every
  non-alphanumeric char replaced by `-`.)
- Caveat: `/compact` mutates the source session (draws a compact boundary the
  live UI session will act on). The non-mutating and higher-quality variant is
  **resume-and-summarize with a fork** — verified working:

  ```bash
  claude -p --resume "$SESSION_ID" --fork-session \
    "Write a handoff brief for an engineer taking over: goals, decisions, \
     constraints, file paths touched, what was tried and failed, open items."
  ```

  The model sees the real conversation natively (including tool results), the
  original session file is untouched, output is plain stdout, no JSONL parsing.
  Inside a live session the skill has `$CLAUDE_SESSION_ID`; hooks receive
  `transcript_path` and `session_id` in their input JSON.
- `/export` is interactive-only (verified failing in print mode) — do not build
  on it.

### Codex (source-verified, not executed)

- Manual compaction is exposed over app-server JSON-RPC as `thread/compact/start`
  (non-experimental, documented in `codex-rs/app-server/README.md`); auto-compact
  lives in core and fires under `codex exec` too. `codex exec` has no compact flag.
- The summary is persisted in the rollout JSONL as
  `{"type":"compacted","payload":{"message":"<summary>", ...}}` — the app-server
  notification carries only an item id, so extraction means reading the rollout
  (or `thread/read` / `thread/items/list`).
- The compaction prompt is overridable via config (`compact_prompt`).

## 4. Strategy C — Copy session state to the remote machine

**Verdict: works on both harnesses and is the highest-fidelity option, but
carries the sharpest risks (secret exfiltration, version skew, unstable
schemas). Gate behind an explicit opt-in.**

### Claude Code (empirically verified)

- Sessions live at `~/.claude/projects/<munged-cwd>/<session-uuid>.jsonl`.
  Copying the JSONL alone into the munged dir corresponding to the *resuming*
  cwd, then `claude -p --resume <id>` from that cwd, **works** — verified with
  a mismatched cwd; embedded `cwd`/`gitBranch` fields do not block resume, and
  sidecar dirs (`todos/`, `shell-snapshots/`, …) are not required.
- This is now officially endorsed: the Agent SDK "Resume across hosts" doc says
  to persist and restore the `.jsonl` (plus a `SessionStore` adapter for shared
  storage). Resume by explicit ID, not the interactive picker; pin
  `claude --version` on both ends (a closed issue, #18645, reported
  cross-machine validation failures on 2.1.9 that did not reproduce on 2.1.202).
- On the remote, resume with `--fork-session` so the transported history is
  never mutated, and optionally `--session-id <uuid>` to pre-pick the remote
  session ID for later inspection.

### Codex (source-verified)

- Rollouts live at `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<ts>-<thread-uuid>.jsonl`.
  Lookup falls back to a filename scan when the sqlite index (`~/.codex/state_db`)
  has no row, so a copied file is discoverable by `codex resume <id>` /
  `thread/resume {threadId}` without touching the DB. Resume by explicit id has
  no cwd constraint (cwd filtering only affects `--last` pickers), and
  `thread/resume` accepts a `cwd` override.
- Simpler still: `thread/resume {path: <rollout file>}` and `thread/fork {path}`
  resume from an arbitrary file location (experimental-gated; boondoggler
  already sends `experimentalApi: true`).
- **Cross-harness transplant is a first-class pattern inside Codex itself**:
  `codex-rs/external-agent-sessions/` imports Claude Code `~/.claude/projects`
  transcripts by converting messages into `RolloutItem::ResponseItem`s. That
  crate is a ready-made recipe (or directly reusable code) for turning a local
  Claude Code session into a Codex-resumable history.

### Shared risks

- **Secrets**: transcripts embed tool outputs (env dumps, tokens printed by
  commands) and file contents. Any transcript that leaves the machine should be
  scrubbed or the user warned. Precedent: `opencode export --sanitize`.
- **Version skew**: both vendors mark the JSONL schemas internal/unstable.
- **Relevance**: full-history resume imports everything, including noise; a
  goal-conditioned brief often outperforms it (Amp's core argument).

## 5. Strategy D — Seed the remote thread / escape hatch to the full transcript

**Verdict: the best-fit boondoggler extension and the most novel pattern found.**

- boondoggler drives `codex app-server` and already initializes with
  `experimentalApi: true`, so today it could:
  1. **Stable, minimal**: after `thread/start`, call `thread/inject_items`
     (non-experimental, documented) with one Responses-API `message` item
     containing the brief, then `thread/goal/set` as today. Or pass the brief
     as `developerInstructions` on `thread/start`.
  2. **Maximal**: `thread/resume {history: [...ResponseItems]}` — seed the whole
     prior conversation without any disk file. This `[UNSTABLE] FOR CODEX CLOUD`
     param is the exact mechanism OpenAI's own local↔cloud handoff uses.
  3. Avoid `turn/start.additionalContext` for briefs — values are
     middle-truncated to ~1,000 tokens.
- **Escape hatch pattern** (opencode-handoff plugin; Hermes `session_search`):
  ship the brief *plus* a queryable copy of the full transcript, and tell the
  remote agent where it is. For /offload, a live callback to the laptop is
  wrong (the laptop sleeping is the whole point), so the fit is: copy a
  sanitized transcript file to the remote worktree (or a non-committed path on
  the target) and reference it in the brief — "full local-session transcript at
  <path> if this brief is insufficient."

## 6. Direction constraints worth documenting

- Claude Code teleport is **cloud→local only** (`claude --teleport`); there is
  no local→arbitrary-remote push (requested in anthropics/claude-code#56687,
  #14666). `claude --cloud "task"` carries only prompt + git ref. So /offload
  cannot ride any official transfer mechanism for its direction.
- Codex cloud task creation likewise carries only
  `prompt + git_ref + environment_id` (`cloud-tasks-client/src/api.rs`).
- Every surveyed product treats **git as the state channel** (commit/push
  before handoff) and the **brief as the intent channel**. /offload already has
  the git half; the brief half is the missing piece.

## 7. Recommended tiers

1. **Tier 0 — skill text only (no code).** Add a "Carry the conversation over"
   section to the `offload` skill: state explicitly that the remote assistant
   starts with zero context, require the dispatching agent to compose a handoff
   brief (checklist in §2) as the boondoggler prompt, and require surfacing
   uncommitted local changes before dispatch. This alone closes most of the gap
   because the dispatching agent already holds the conversation.
2. **Tier 1 — automated brief generation.** When the local harness is Claude
   Code, offer the fork-resume-summarize recipe (§3) so the brief is generated
   from the real transcript rather than the agent's recollection; fall back to
   compaction-borrowing where a compact summary already exists.
3. **Tier 2 — transcript escape hatch.** Optionally ship a sanitized transcript
   to the remote target and reference it in the brief.
4. **Tier 3 — native session transplant.** Claude JSONL copy + `--resume
   --fork-session`, or Codex `thread/resume {history|path}` via boondoggler.
   Highest fidelity, unstable surfaces, secrets risk — explicit opt-in only.

## Open unknowns

- True cross-machine Claude session copy on latest versions with
  `sessions-index.json` present (needs a two-machine CI test).
- Whether `--fork-session` + `/compact` confines the compact boundary to the
  fork's file (likely, untested).
- Codex `thread/resume {history}` interaction with boondoggler's
  `thread/goal/set` (source-verified, not executed end-to-end).
- Whether gpt-5.5 performs better with a seeded full transcript or a compact
  brief — empirical product question; the brief + `thread/inject_items` is the
  safest first move.
