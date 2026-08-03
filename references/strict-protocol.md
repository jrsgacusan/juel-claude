# Strict protocol — authoring source of truth

This file is **not** read at runtime. No `SKILL.md` links to it, and nothing
in the plugin loads it during a skill invocation — that is deliberate, per
spec §6. A sibling file is only loaded if the model chooses to read it, which
cannot deliver an "always print the checklist" guarantee, and the block's own
first clause ("before any tool call") would be self-violating if obeying it
required a tool call to fetch this file first.

This file exists so that changing the protocol later is a mechanical,
diffable sweep across all 12 skills rather than an archaeology exercise.
Every `SKILL.md` carries a byte-for-byte copy of the block below, pasted in
verbatim by Tasks 7–11. If the protocol ever changes, edit it here first,
then re-sweep all 12 skills from this copy.

The block below — from the `## Strict Execution Protocol` heading through
the end of rule 5 — is `PROTOCOL_BLOCK`: the literal, exact text every skill
carries. Copy it character-for-character. Do not paraphrase, reformat, or
"improve" it during a paste.

## Strict Execution Protocol (non-negotiable)

<!-- juel:protocol v1 -->

**1. Preflight, then checklist, before anything else.** Before any other output and before any tool call, emit the Preflight block (below), then this skill's `## Phases` checklist rendered as:

```
<skill-name> — N phases
[ ] 1. <phase name>
[ ] 2. <phase name>
```

If the preflight verdict is STOP, print the preflight block and **stop** — do not print the checklist and do not begin work. Otherwise no work begins until the checklist is on screen. This is not optional on re-invocation, on resume, or when the user says "just do it".

**2. Phases run in order.** No skipping, reordering, or merging. A phase that does not apply is still announced: mark it `[-] N. <name> — SKIPPED: <one-line reason>` and continue at N+1. Never drop a phase silently. Never begin phase N+1 before phase N is marked done or skipped.

**3. Report after every phase.** Re-emit the checklist (`[x]` done, `[-]` skipped, `[ ]` pending) plus one line of evidence for the phase just finished — path written, command run, count found. Never claim progress in prose alone.

**4. Everything runs in the FOREGROUND.** This overrides every other instruction in this file and in any skill invoked from it.
- `pr-review-toolkit:review-pr`, `simplify`, and `codex exec` are all foreground-only. Invoke subagents with `run_in_background: false` **explicitly** — the harness backgrounds subagents by default, so omitting the flag is a violation, not a neutral choice.
- Never `&`. Never `run_in_background: true`. Never "dispatch and continue".
- **Never redirect a command's output to a log file.** No `> out.log`, no `| tee`, no writing output somewhere to read back later. The user must be able to watch the run as it happens.
- Do not request `review-pr`'s parallel / `all parallel` mode.
- Read the complete output and state the outcome — finding count, exit status, files changed — before marking the phase done. A summary may follow the raw output; it may never replace it.
- Passing any of this into another session (a CMUX prompt, a nested `claude`) carries these rules with it — say so explicitly in that prompt string.

**5. Confirmation gates stack; they do not replace this.** Where this skill pauses between phases, the checklist report comes first, then the "Proceed to phase N+1?" question. A user's "yes" advances exactly one phase — it never authorizes skipping ahead or batching the remainder.
