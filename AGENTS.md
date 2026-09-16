# AGENTS.md

Guidance for coding agents working in this repository.

## What this repo is

A packaging and field-notes repository for an authorized-pentest lab built around
[PentesterFlow](https://github.com/PentesterFlow/agent). It ships no application code
of its own — it ships a container image definition, shell launchers, operational
scripts, agent skills, MCP config docs, and one small C project.

Three components, no shared build:

| Path | Kind | Build |
|---|---|---|
| `pf-lab/pentesterflow-docker/` | Dockerfile + bash | `docker build` |
| `pf-lab/cve-lab/` | C11 + Python 3 | `make` |
| `pf-lab/scripts/` | bash | none — syntax-check only |
| `pf-lab/skills/`, `pf-lab/mcp/` | Markdown / JSON — documentation | none |

There is no package manager, no lockfile, and no CI in this repo. Do not introduce one
without being asked.

## Layout

```
README.md                          # human-facing overview
LICENSE                            # MIT
AGENTS.md                          # this file
pf-lab/
├── README.md                      # (none — pf-lab is documented from the root README)
├── .env.example                   # every tunable in one place
├── pentesterflow-docker/          # the containerized agent lab
│   ├── Dockerfile                 # Kali + scanners + agent (release binary)
│   ├── Dockerfile.main            # same runtime, agent built from upstream main
│   ├── entrypoint.sh              # seeds config, refreshes image-owned skills
│   ├── pf                         # launcher: mounts cwd, key handling, preflight
│   ├── run.sh                     # raw `docker run`
│   ├── setup-run.sh               # provisions a run's config + USER.md + brief
│   ├── smoke-test.sh              # asserts the toolchain in a built image
│   ├── run-with-harness-key.sh    # optional DSH credentials convenience
│   ├── ISSUES.md                  # 29-issue field log — the important document
│   └── prompts/                   # sanitized engagement brief templates
├── scripts/                       # pf-monitor.sh, pf-watch.sh, make-report.sh
├── skills/                        # PentesterFlow SKILL.md playbooks
├── mcp/                           # MCP server schema + opt-in examples
└── cve-lab/                       # isolated ASan mock (C11 + Python harness)
```

## Setup commands

Nothing needs installing to *work on* this repo. To *run* it:

```sh
# Container image (needs Docker; the build fetches the agent from upstream)
cd pf-lab/pentesterflow-docker
docker build -t pentesterflow:full .
DEEPSEEK_API_KEY=sk-... ./smoke-test.sh

# CVE lab (needs a C compiler with ASan and python3)
cd pf-lab/cve-lab
make && make test
```

`smoke-test.sh` exits non-zero if any scanner is missing. A broken rebuild should fail
loudly, not degrade quietly — preserve that property.

## Testing instructions

There is exactly one test suite, and it is not optional to run:

```sh
cd pf-lab/cve-lab
make test          # 8/8 expected
make asan-check    # confirms libasan is actually linked
```

**`make asan-check` is not decoration.** The whole value of that lab is that a
memory-safety bug gets *named* by AddressSanitizer; a build without `-fsanitize=address`
would let a vector corrupt memory silently and every result after it would be
meaningless. `asan-check` exists to prove the flag reached the link line.

Test-case semantics, which are inverted from what you may expect:

- A **regression** case *passes when ASan reports the expected defect*. A regression
  case that exits cleanly is a **failure** — a lab vector that does nothing teaches the
  wrong lesson.
- A **control** case sends benign input and passes when the process exits cleanly.
- `expect=[...]` tokens are substring-matched against combined stdout+stderr, so an
  assertion about sanitizer output must be verified against a real run. One case in
  this repo originally asserted `double-free` and failed, because a use-after-free
  aborts first — see the note in `cve-lab/README.md` before "fixing" a failing case by
  loosening its expectation.

For the shell scripts there is no test runner; use `bash -n` at minimum:

```sh
for f in pf-lab/pentesterflow-docker/*.sh pf-lab/scripts/*.sh; do bash -n "$f" || echo "FAIL $f"; done
```

`setup-run.sh` has an end-to-end check that needs no container — it writes into
throwaway directories and prints what it did:

```sh
cd pf-lab/pentesterflow-docker
PF_STATE_ROOT=$(mktemp -d)/s PF_RUNS_ROOT=$(mktemp -d)/r ./setup-run.sh 1 slice:1-254
```

## Code style

**Shell.** `#!/usr/bin/env bash` (or `#!/bin/sh` for `entrypoint.sh`, which must stay
POSIX). Start every script with `set -euo pipefail` — except the watcher scripts, which
use `set -uo pipefail` deliberately because their `grep` probes are expected to fail.
Quote every expansion. Prefer `[ ]` tests and POSIX-safe flags: the *agent* is blocked
from GNU-only flags by its own portability guard, but the host scripts here should be
portable anyway.

A real trap in this repo: `printf` with a placeholder is an **error** in some shells,
and more importantly the `Dockerfile` writes JSON via a `printf '%s\n'` per line chain.
If you add a config key there, add a matching line and keep the trailing-comma placement
correct, then confirm the JSON parses.

**C (cve-lab).** C11, `-Wall -Wextra -Wpedantic`, ASan always on. Every deliberately
buggy function is marked with the `============================ THE DEFECT
============================` banner and a `FIX:` line, and the file header states the
safety invariants. Keep that convention: the comments are the teaching material, and a
change that removes the explanation of *why* something is wrong removes the point.

**Markdown.** Documentation here carries the reasoning, not just the instruction. When
you change behaviour, update the *why* — several files in `pentesterflow-docker/`
exist specifically to record a failure that a future reader would otherwise repeat.

## Recording a discovered issue

`pf-lab/pentesterflow-docker/ISSUES.md` is the repo's centre of gravity. Its convention,
worth matching for anything new:

- One `### ISSUE-N · short title — OPEN|FIXED, severity` heading, numbered sequentially.
- **The evidence, verbatim** — the actual command and its actual output, not a summary.
- The **root cause**, with a file/line reference when it is upstream code.
- The **fix**, as something applicable — a config key, a `setcap`, a brief rewrite.
- Round headings (`# Round N — ...`) for issues found in the same session.

Do not renumber or reorder existing issues; append. `ISSUES.md` is also the file with
the most sanitization history — placeholder substitutions there are deliberate (see
"Sanitization" in the root README) and the header note explains the key.

## Security considerations

**Never commit real engagement data.** `.gitignore` excludes `findings/`, `*.gnmap`,
`*.nmap`, `*.xml`, `.env`, and run logs. Keep it that way, and do not add an exception
without a specific reason.

**Never commit a credential.** The API key is never baked into the image and never
passed on a command line (that is visible to `ps` and lands in shell history). The
supported paths are `--key` (interactive prompt), the `0600` keyfile, or the
`DEEPSEEK_API_KEY` environment variable. Do not "simplify" this into a CLI flag.

**Sanitization is load-bearing.** Every network address, interface name, SSID and
hostname in this repo is a placeholder standing in for the author's real network.
Keep it that way: use RFC 5737 documentation ranges (`198.51.100.0/24`) for defaults
and examples, never a real private subnet. A default of `192.168.1.0/24` would be
actively dangerous — it is the most common home router subnet, so an unconfigured run
would scan whatever network the machine happened to be on.

**Scope guardrails are deliberate.** `PF_REQUIRE_SUBNET` refuses to start `pf` unless
the target network is actually attached; the default `mcp_servers` is empty so no
server is spawned implicitly. Both exist because of documented failures. Do not
weaken them for convenience.

**The CVE lab must stay contained.** `src/main.c` binds `INADDR_LOOPBACK` and re-checks
the peer address after `accept()`. No vector may spawn a shell, open an outbound
connection, write a file, or read a credential. If you add a vector, preserve all four
properties — they are enforced in code precisely so a mistake in the parsers cannot
reach the network.

**Third-party MCP servers** run as local processes with your privileges. Treat adding
one as installing software. The schema rejects shell metacharacters in `command` and
in every `args` element; do not work around that validation.

## Pull request guidelines

- Title: `[component] Brief description`, e.g. `[cve-lab] Fix stale double-free assertion`.
- Run before submitting: `make test` in `cve-lab/` (expect 8/8) and `bash -n` over the
  scripts you touched.
- One concern per PR. A change to the Dockerfile and a change to a skill playbook are
  two PRs.
- If you change a documented behaviour, update the document that describes it —
  including the root README's table and `ISSUES.md` where relevant.
- Do not include generated artifacts: no `build/`, no `__pycache__/`, no PDFs, no
  `report.html`.

## Additional notes

- **Exit-code convention:** `pf` reports working/idle to `herdr` on start/exit but
  always propagates the container's exit code. Scripts that poll for completion treat a
  killed container as "stopped", not "succeeded".
- **The `pf` launcher and `run.sh` overlap on purpose.** `run.sh` is the raw invocation
  for one-off commands; `pf` adds key precedence, the subnet preflight and the `herdr`
  reporting. Keep them consistent when changing mounts or capabilities — they must pass
  the same `docker run` flags or a `pf`-only bug becomes invisible.
- **`Dockerfile.main` patches upstream source** (`DELEGATE_MAX_STEPS`, the version
  string) with `sed` against a downloaded tarball. A `sed` that silently stops matching
  is a real hazard here: each patch greps its own result so the build fails loudly if
  upstream renames the symbol. Preserve those `grep` assertions.
- **The image intentionally runs as the host uid, not root**, and relies on `setcap`
  file capabilities for raw sockets. Do not "fix" a permission error by switching to
  root — it breaks bind-mount ownership for the host user (see ISSUE-1 and the
  Dockerfile comments).
- `pf-lab/` has no README of its own; the root `README.md` documents it. Add to the root
  file rather than creating a nested overview.
