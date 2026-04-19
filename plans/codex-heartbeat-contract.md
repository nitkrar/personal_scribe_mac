# Codex Heartbeat Contract

**Referenced by every codex subagent brief.** If you are a codex subagent executing a task that takes longer than 5 minutes, this contract is mandatory.

## Why

Main-session Claude cannot introspect a running Codex task (the forwarder-subagent pattern blocks status/cancel/inject). Without a heartbeat, we cannot distinguish:

- A productive agent mid-work from a wedged agent
- A deliberate tool-call pause (e.g., grepping thousands of files) from a deadlock
- A near-done agent from one that just started

## The contract

Every 3–5 minutes of wall-clock time during your task, write a structured heartbeat file to:

```
.codex-heartbeat/<agent-or-task-id>.md
```

Use whichever identifier you were given at dispatch. If you have multiple (agent ID + task ID), use the agent ID for the filename and include both IDs in the body.

Overwrite in place each heartbeat. Do NOT `git add` or `git commit` the heartbeat file. Do NOT include it in the final task's commit.

## File format

```markdown
# Codex heartbeat — <agent-or-task-id>

- **Last update (local time):** 2026-04-19 17:42:11 +0100
- **Agent ID:** a7b8ca4d4a4ef47e0
- **Task ID (if any):** task-mo5zg58s-s931t2
- **Uptime:** 00:42:31 (HH:MM:SS since task start)
- **Phase:** `reading-inputs` | `grepping-codebase` | `drafting-file` | `running-tests` | `writing-commit` | `other`
- **Last action:** One sentence describing what you just finished doing.
- **Next action:** One sentence describing what you are about to do.
- **Files produced so far:** bullet list of paths committed or staged.
- **Estimated time to completion:** "5 minutes" | "unknown" | "blocked on X"
- **Blockers:** Any `[QUESTION]` / `[BLOCKED]` items you've hit that main session should know about. One bullet each, brief.
```

## Timing

- Write the FIRST heartbeat within the first 60 seconds of the task starting. This confirms the task is alive and has started reading inputs.
- Subsequent heartbeats every 3–5 minutes.
- Before any single tool call you expect to take > 30 seconds (a large grep, a recursive file read), write a pre-call heartbeat with `phase: tool-call-<name>-in-flight`.
- After finishing that long tool call, write a post-call heartbeat updating `last_action`.
- Skip heartbeats only if the total task takes under 5 minutes end-to-end.

## Handling the `.codex-heartbeat/` directory

- The directory is `.gitignore`'d. Files in it are ephemeral.
- If the directory doesn't exist when you start, `mkdir -p .codex-heartbeat/`.
- If your task completes successfully, delete your heartbeat file at the end of the task (leave the dir).
- If your task fails or is cancelled, leave the heartbeat in place as a crash breadcrumb.

## Main-session usage

Main session checks liveness with:

```
ls -la .codex-heartbeat/
cat .codex-heartbeat/<agent-id>.md
```

A heartbeat older than 10 minutes without a completion notification implies the task is wedged. Main session may:

- Send a `SendMessage` probe to the dispatcher agent (often useless — forwarder can't introspect).
- Dispatch a fresh task to replace the wedged one.
- Kill the underlying process if identifiable (last resort).

## Enforcement in briefs

Every codex brief should include this single line verbatim:

> **Heartbeat**: comply with `plans/codex-heartbeat-contract.md`. First heartbeat within 60 seconds. Subsequent every 3–5 minutes. Delete on successful completion.
