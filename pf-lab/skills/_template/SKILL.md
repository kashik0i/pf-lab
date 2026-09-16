---
name: my-skill
description: One line on what this playbook does, then an explicit "Use when ..." clause so the agent knows when to load it. Max 1024 chars — this description is the ONLY thing the model sees until it loads the skill, so state the trigger conditions concretely.
allowed-tools:
  - shell
  - http
  - file_write
---

# my-skill playbook

State the goal in one or two sentences — what the operator is trying to achieve —
and the scope rules (authorized targets only).

## 1. First step

Concrete, copy-pasteable commands. Default to `curl` and the built-in `http` tool;
only reach for specialised scanners when the task genuinely needs them.

```sh
curl -ksS "https://TARGET/"
```

Note that `${SKILL_DIR}` is replaced with this skill's absolute directory path, so
bundled files can be referenced directly:

```sh
nmap -sV --open -iL "${SKILL_DIR}/payloads/targets.txt"
```

> Do not call `read_payloads(...)`. It is named in PentesterFlow's own
> `skills/_template/SKILL.md` but no such tool exists in the released binary or on
> `main` — a stale doc. Read bundled files through the ordinary file/shell tools
> using the `${SKILL_DIR}` path.

## 2. Next step

...

## Reporting

What proves the bug, the concrete impact in one sentence, and the remediation.
When you have a reproduced finding with a real request/response, call
`confirm_finding` so it lands in `./findings/<slug>.md`.
