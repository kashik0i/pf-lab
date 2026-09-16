---
name: my-skill
description: One line on what this playbook does, then an explicit "Use when ..." clause so the agent knows when to load it. Max 1024 chars — this description is the ONLY thing the model sees until it loads the skill, so state the trigger conditions concretely.
allowed-tools:
  - shell
  - http
  - file_write
  - read_payloads
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

Bundled payload files can be pulled by name with the `read_payloads` tool, which is
the intended path for curated wordlists (`<skill>/payloads/…`):

```text
read_payloads(skill="my-skill", file="list.txt")
```

Use `${SKILL_DIR}` (replaced with this skill's absolute directory path) for bundled
scripts and anything read through the shell:

```sh
nmap -sV --open -iL "${SKILL_DIR}/payloads/targets.txt"
```

## 2. Next step

...

## Reporting

What proves the bug, the concrete impact in one sentence, and the remediation.
When you have a reproduced finding with a real request/response, call
`confirm_finding` so it lands in `./findings/<slug>.md`.
