# Local skills

Markdown playbooks for the PentesterFlow agent. Two of these are worked examples
drawn from failures documented in `../pentesterflow-docker/ISSUES.md`; the third is an
annotated template.

| Skill | Covers |
|---|---|
| `lan-discovery/` | scope-safe subnet discovery, the attached-network preflight, interface pinning, client-isolation vs misroute |
| `cve-triage/` | exact-version fingerprinting, a *bounded* nuclei sweep, NVD fallback, confirmed vs version-inferred |
| `_template/` | annotated `SKILL.md` starter |

## Format

A skill is a directory containing `SKILL.md`, with optional bundled `payloads/` and
`scripts/` alongside it:

```
skills/
└── my-skill/
    ├── SKILL.md          # required
    ├── payloads/         # optional: wordlists, fingerprints, probe files
    └── scripts/          # optional: helper scripts
```

`SKILL.md` is YAML frontmatter followed by a Markdown body:

| Field | Required | Notes |
|---|---|---|
| `name` | yes | must match the directory name |
| `description` | yes | ≤1024 chars. **The only thing the model sees until it loads the skill** — put explicit "Use when …" trigger conditions here. There is no separate `triggers` list. |
| `allowed-tools` | no | restricts the tools the skill may call (`shell`, `http`, `file_write`, …). Omit for no restriction. Legacy alias: `tools`. |
| `disable-model-invocation` | no | `true` = user-only, invoked via `/<name>` |

The body is delivered to the model verbatim on `load_skill`. `${SKILL_DIR}` in the
body expands to the skill's absolute directory path, so bundled files are reachable
by ordinary path:

```sh
nmap -sV --open -iL "${SKILL_DIR}/payloads/targets.txt"
```

> **Do not call `read_payloads(...)`.** PentesterFlow's own `skills/_template/SKILL.md`
> demonstrates it, but no such tool exists in the released binary *or* on `main` —
> it is a stale doc. Use `${SKILL_DIR}` plus the normal file/shell tools.

## Loading them

Discovery order, later entries overriding earlier ones on a name collision:

1. built-in `skills/` shipped in the image
2. `./.pentesterflow/skills/` — project-local, scoped to the engagement repo
3. `~/.pentesterflow/builtin-skills/` — installer-managed
4. `~/.pentesterflow/skills/` — personal
5. directories passed with `--skills <dir>`, or set in `config.json` as
   `"skills_dirs": [...]`

Point the agent at this directory:

```sh
pentesterflow --skills /path/to/pf-lab/skills
```

or in `config.json`:

```json
{ "skills_dirs": ["/work/pf-lab/skills"] }
```

The image's entrypoint replaces image-owned skills on every start, so a rebuilt image
takes effect without wiping state — but these local skills live outside the image and
are mounted, not refreshed.

## Writing one

Start from `_template/SKILL.md`. Two things are worth getting right:

- **The description carries the trigger.** The model reads only that until it decides
  to load the skill, so a vague description means the playbook never fires.
- **Constrain the method, not just the goal.** These playbooks exist because
  unconstrained instructions produced specific, repeated failures: unbounded nuclei
  sweeps, probes leaking off the authorized subnet, and turns burned re-deriving
  capabilities the container already has.
