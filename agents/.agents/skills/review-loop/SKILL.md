---
name: review-loop
description: Get local changes merge-ready by running rounds of code review from fresh subagents, fixing what they find, until a round comes back clean or minor only. Use when Sam runs /review-loop, says "review loop", "get this merge ready", "review until clean", or before raising a PR.
---

# /review-loop

1. **Scope.** `base` = merge-base with the target branch (ask if unclear). Snapshot the working tree
   without touching the index, untracked files included:
   ```sh
   snap() { i=$(mktemp); cp "$(git rev-parse --git-path index)" "$i"; GIT_INDEX_FILE=$i git add -A; GIT_INDEX_FILE=$i git write-tree; rm "$i"; }
   ```
2. **Review.** Spawn a fresh agent each round, never reuse one. Give it the goal of the change, the
   diff command, and project rules (CLAUDE.md, AGENTS.md). Not your reasoning or conclusions.
   - Round 1: `git diff $base $(snap)`, the whole change.
   - Later rounds: `git diff $prev $(snap)`, only the last round's fixes, with the full diff as
     context. Pass the rejected findings so they are not raised again.
   - Ask for real defects only (bugs, security, broken edge cases, missing tests, project rule
     breaches), each with `file:line`, severity (`critical|important|minor`) and a concrete failure
     scenario. No style nits.
3. **Triage.** Check each finding against the code yourself. Fix the real ones, reject the rest with
   a one-line reason. Take `prev=$(snap)` before fixing.
4. **Fix and verify.** Minimal fixes, then run the project's tests and linters.
5. **Repeat** from 2. Stop when a round has no critical or important findings. After 4 rounds, stop
   and hand it to Sam.

Report one line per round (findings, fixed, rejected), plus the minor findings left open. Never
commit or push.
