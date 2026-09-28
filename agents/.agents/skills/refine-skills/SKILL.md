---
name: refine-skills
description: Retrospective on a session that used one or more skills, turned into tested edits to those skills. Mines the session for friction (failures, retries, workarounds, the user correcting or overriding a step), checks each finding against the skill's current text, and reviews the whole skill for redundancy, contradictions and length, so it gets sharper rather than longer. Proposes changes one at a time, then applies and commits the approved ones. Use when the user runs /refine-skills, or asks for a "retro", "retrospective", "lessons learned", "what should we change in the skill", "improve the skill from this run" or "tighten up the skill", typically after an upgrade, patch, test run or any other skill-driven task.
---

# Refine skills

Turns what happened in this session into changes to the skills that drove it. Run it after each
use and the skill should converge: more correct each time, and no longer than it needs to be.
Appending a lesson per run does the opposite.

## 1. Find the skills and their source

- **Which skills ran.** Slash invocations and skill loads; `scripts/digest.py` lists them.
- **Where they live.** Skill files are usually symlinks (`readlink -f`), often into a dotfiles
  repo. Edit the source. New files need the same linking as their neighbours.
- **Repo state.** Changes you did not make stay unstaged. Check whether the repo is public
  before writing client or project names into it.
- **Current text.** Read the skill as it is now, not as it was when the session started. Skills
  get edited between runs, and a finding the current text already covers is dropped.

## 2. Gather the evidence

Work from the conversation. When the context has been compacted, or the session is long, read
the digest instead:

```bash
python3 ~/.claude/skills/refine-skills/scripts/digest.py [transcript.jsonl]
```

With no argument it reads the newest transcript for the current directory. It prints, in
order, the skills used, every user message, the assistant's own narration and every failed
tool call. Failures inside commands that exited 0 (background logs, test output) only show up
in the narration, so read the `NOTE` lines too.

What to look for, strongest signal first:

- the user correcting, overriding or narrowing something
- failures and retries, and what finally worked
- steps the skill does not describe, or describes wrongly
- a question asked at the wrong time, costing an extra round trip
- a claim made without verification: it points at a missing check
- repeated work, such as a helper written by hand that the skill should ship as a script

Sort each finding before drafting anything:

- **Project facts** (this store's quirks, why a patch exists) go to project memory or the
  project's docs. A skill stays generic.
- **Another skill's job.** A finding can belong to a different skill than the one where it
  surfaced, or to none.
- **Already covered.** If the current text handles it, drop it.

## 3. Review the whole skill

Read the skill with the session set aside, and look for:

- **redundancy**: the same point made twice, in the skill or across its reference files
- **contradictions**: a new rule that conflicts with an old one. Check every mention, including
  numbered cross-references such as "phase 6"
- **stale facts**: versions, URLs, commands. Run them
- **length**: a paragraph that could be a sentence, prose that could be a table or a script

Prefer replacing and deleting to appending. When a change adds lines, look for the lines it
makes redundant.

## 4. Verify before proposing

- Draft on scratchpad copies and show the diff, not a description of it.
- Run commands and scripts against the real project, with a positive control (what it should
  find, it finds) and a negative control.
- A change that cannot be tested here is marked untested, with the reason.

## 5. Present one point at a time

A long list of proposals does not get read. For each point, highest value first:

- **Problem**: what happened, with the evidence
- **Change**: the diff
- **Tested**: what was run and what it showed, or why it is untested
- then: approve, amend or skip?

Recommend skipping a point that does not earn its place. Where a point would let the agent
act on the user's behalf (deleting data, pruning, choosing a default), propose asking the user
instead.

## 6. Apply and commit

- Confirm the source file has not changed since you drafted against it, then apply only what
  was approved. An amend is redrafted and shown again.
- Re-run the check that proved the change, through the live skill path.
- Commit per skill, only the files you changed. Show the messages first. Do not push.
