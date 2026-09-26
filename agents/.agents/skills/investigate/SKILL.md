---
name: investigate
description: Investigate a question or problem without making changes. Use when explicitly asked for investigation-only or read-only analysis.
disable-model-invocation: true
---

Investigate only. Read code, configuration, logs and other evidence, but do not edit
files, change state, or run commands with side effects. Apply the same restriction
to any delegated work.

If the investigation needs a change to proceed (turning on debug logging, clearing a cache,
a command with side effects), ask first and say why.

Report what you found, the evidence, and anything still unverified. Suggest fixes
where useful, but do not implement them until the user explicitly asks you to.
