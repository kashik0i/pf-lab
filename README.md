# pf-lab

An authorized-pentest lab built around [PentesterFlow](https://github.com/PentesterFlow/agent):
a containerised agent + full scanner toolchain, the operating knowledge for driving
it across a real engagement, and a small isolated memory-safety lab for studying
CVE bug classes.

Everything here was developed against networks and devices the author owns. All
site-specific identifiers have been replaced with placeholders — see
[Sanitization](#sanitization) below.

## What is in here

| Path | What it is |
|---|---|
| `pentesterflow-docker/` | Kali image with PentesterFlow + 8 scanners, a `pf` launcher, run provisioning, smoke tests, and a 629-line field issue log |
| `scripts/` | Helpers for driving a batch of runs: a modal-aware stall watcher and a PDF report builder |
| `skills/` | Agent playbooks (LAN discovery, bounded CVE triage) plus an annotated template |
| `mcp/` | MCP server schema, candidate servers, and copy-paste opt-in config |
| `cve-lab/` | An isolated, ASan-instrumented mock reproducing three CVE bug classes — loopback-only by construction |
| `.env.example` | Every tunable in one place |

## Quickstart

```sh
# 1. Build the agent image and verify the toolchain
cd pentesterflow-docker
docker build -t pentesterflow:full .
DEEPSEEK_API_KEY=sk-... ./smoke-test.sh

# 2. Provision a run (scope comes from the environment, not the script)
PF_TARGET_CIDR=10.0.0.0/24 PF_TARGET_IFACE=eth0 PF_LOCAL_IP=10.0.0.5 \
  ./setup-run.sh 1 slice:1-254

# 3. Launch the agent against that run's workdir, loading the local skills
cd ~/pf-runs/run1
PF_REQUIRE_SUBNET=10.0.0.0/24 \
  /path/to/pf-lab/pentesterflow-docker/pf --start --skills /path/to/pf-lab/skills
```

The CVE lab is independent and self-contained:

```sh
cd cve-lab
make && make test        # 8/8 cases: three bug classes + controls
```

## What is inside

### The agent lab (`pentesterflow-docker/`)

The scanner-in-a-container problem is specific: PentesterFlow's shell tool executes
locally, so every scanner has to live in the **same** container as the agent — a
sidecar is unreachable to it. The image is Kali (glibc, because the agent ships as a
Bun-compiled binary) plus nmap, masscan, arp-scan, ffuf, gobuster, sqlmap, wfuzz,
nuclei, subfinder and httpx.

Three decisions are worth knowing before you use it:

- **It runs as your uid, not root.** On a userns-remapped daemon a root container
  writes bind mounts as an unmapped `nobody`. Raw sockets for masscan/arp-scan come
  from `setcap` baked into the image instead.
- **`--network host`.** That is what lets the agent reach lab targets — and it means
  the container shares your host's network position. Treat it accordingly.
- **The key is never baked in.** It comes from the environment or an interactive
  prompt, never from a command line that `ps` can read.

`ISSUES.md` is the part most worth reading. It is a field log of 29 numbered issues
with evidence and fixes: the step-limit modal that stalls unattended runs, the
context threshold that elides the agent's own brief, the raw-socket capability that
nmap already ships, and the run where the network changed mid-engagement and started
egressing probes onto an out-of-scope link. Those failures shaped the defaults,
the preflight, and the brief templates.

### The isolated CVE lab (`cve-lab/`)

A miniature mock — not Apache — with three parsers that each reproduce a bug class
from real advisories: an HTTP/2 stream-pool lifetime bug, a regex quantifier
underwrite, and an AJP attribute length overflow. Built with AddressSanitizer
because the whole point is having the undefined behaviour *named*, with a source
line, rather than silently corrupting a heap.

Its safety properties are enforced in code, not just documented: the listener binds
`INADDR_LOOPBACK` only, the peer address is re-checked after `accept()`, and no
vector spawns a shell, writes a file, or connects outward. The impact of every
crashing case is an ASan abort.

### Skills (`skills/`)

Markdown playbooks the agent loads on demand, written from this lab's specific
failures rather than generic methodology:

- **`lan-discovery/`** — leads with the *preflight*, because the most expensive
  failure here was not a slow scan but one that silently egressed onto an
  out-of-scope network. Covers interface pinning and the client-isolation-vs-misroute
  judgment call.
- **`cve-triage/`** — keeps a nuclei sweep bounded (a measured run produced 0 lines in
  13 minutes across ~13,600 templates) and holds the line between
  **confirmed** and **version-inferred** CVE matches.

Load them with `pentesterflow --skills /path/to/pf-lab/skills`, or set `skills_dirs`
in the run's `config.json`. `_template/SKILL.md` is an annotated starter.

### MCP servers (`mcp/`)

`config.json` takes an `mcp_servers` array, and the image now ships `npx` so any
published MCP server is a one-line addition. The schema is stricter than most MCP
examples — **stdio only, no shell metacharacters in `command` or in any single `args`
element** — and `mcp/README.md` documents the four constraints that actually bite.

Nothing is enabled by default, deliberately: an MCP server is a local process running
with your privileges, and `npx -y pkg@latest` re-fetches over the network on every
session start. The README also argues *against* the obvious first choice — scanner
wrapper hubs duplicate the eight scanners already in the image while making their tool
descriptions worse.

## Sanitization

This repository is published, so every site-specific value was replaced with a
placeholder:

| Placeholder | Stood for |
|---|---|
| `<TARGET_CIDR>`, `<TARGET_IFACE>`, `<LOCAL_IP>`, `<GATEWAY_IP>` | the authorized target network and its interface |
| `<OUT_OF_SCOPE_CIDR>`, `<OUT_OF_SCOPE_IFACE>` | a second attached network the brief forbids |
| `<SSID>`, `<ROAMED_CIDR>` | the target WiFi, and wherever the machine roamed mid-run |
| `<HOST_A>`…`<HOST_C_IP>`, `<GATEWAY_MAC>` | internal hostnames and hardware addresses |

Timings, command output, error text and issue numbering in `ISSUES.md` are
unedited — the placeholders stand in for identity, never for evidence. Scripts take
their scope from environment variables (`PF_TARGET_CIDR`, `PF_TARGET_IFACE`, …) with
generic defaults, so none of them needs editing to run.

Live scan output is never committed: `.gitignore` excludes `findings/`, `*.gnmap`,
`*.nmap`, `*.xml`, `.env`, and the build artifacts of the CVE lab.

## Authorization

This is offensive tooling plus the knowledge to point it at a network. It is only
meaningful for systems you own or have **written** permission to assess.

The design reflects that: `pf` has an opt-in preflight that refuses to start unless
the target network is actually attached (so a mid-engagement network change cannot
silently reroute probes), and every brief template here is read-only enumeration —
no exploitation, no credential guessing, no state changes, with a bounded
default-credential cap and an explicit stop-on-lockout rule.

## Credits

- [PentesterFlow](https://github.com/PentesterFlow/agent) — the agent. All agent
  code and binaries belong to that project; this repo packages it.
- [Kali Linux](https://www.kali.org/) — base image.
- [ProjectDiscovery](https://projectdiscovery.io/) — nuclei, httpx, subfinder.

## License

MIT — see [LICENSE](LICENSE). The PentesterFlow agent itself is fetched at build
time and is covered by its own license.
