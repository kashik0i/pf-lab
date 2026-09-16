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

The body is delivered to the model verbatim on `load_skill`. Bundled files can be
reached two ways.

**`read_payloads` — the intended path for curated payload lists.** A shipped tool
(`src/tools/payloads.ts`, registered in both `main` and the `v0.1.20` release) that
resolves files inside a skill's own `payloads/` directory, with the skill name plus a
relative path and `../` escapes rejected:

```text
read_payloads(skill="ssti", file="jinja2.txt")
```

It caps at 256 KiB with a 16 KiB preview, and lists a directory when given no `file`.
This is the right way to ship wordlists and probe files: the agent asks for them by
name instead of inventing payloads from training memory.

The shipped upstream manifests declare it properly — `ssti`, `jwt`, `graphql`,
`deserialize`, `supabase` and `takeover` all list `read_payloads` in their
`allowed-tools`. **Do the same in yours if you ship a `payloads/` directory**, since
that manifest is the only declaration of what your playbook may touch.

**`${SKILL_DIR}` — for everything else.** Expands to the skill's absolute directory
path, so bundled scripts and data are reachable by ordinary path:

```sh
nmap -sV --open -iL "${SKILL_DIR}/payloads/targets.txt"
```

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
