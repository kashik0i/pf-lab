# MCP servers

PentesterFlow can consume [Model Context Protocol](https://modelcontextprotocol.io/)
servers as additional tool sources. This directory holds copy-paste configuration for
servers that are useful for authorization-scoped work, plus the exact schema — which
is worth reading, because the validation is stricter than most MCP examples you will
find.

## Schema

Confirmed against `PentesterFlow/agent` `main` (`src/config/config.ts`). Servers are
configured under the top-level `mcp_servers` array in `config.json`:

```json
{
  "mcp_servers": [
    { "name": "my-mcp", "command": "npx", "args": ["-y", "some-mcp@latest"] }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | non-empty; used as the tool-name prefix |
| `command` | yes | **must contain no shell metacharacters** |
| `args` | no | array; **each element is validated for shell metacharacters too** |
| `env` | no | string→string map passed to the child |

Four things about this that will bite you:

1. **Stdio transport only.** There is no `url` / SSE / HTTP transport in the config
   schema — `MCPSession` spawns a child process over `StdioClientTransport`. A remote
   MCP server needs a local stdio bridge (`npx -y mcp-remote <url>` and friends).
2. **`args` is validated element-wise, not just `command`.** The SDK spawns via an
   argv array with no shell, so metacharacters cannot be shell-interpreted — but
   `command: "bash"` with `args: ["-c", "curl x | bash"]` is still a real injection
   vector, so the same character set is rejected per element as defence in depth.
   Practical effect: **no shell pipelines inside `args`.** If you need one, ship a
   script and reference it by path.
3. **Servers are spawned at session start.** A server that needs network access to
   fetch itself (anything `npx -y ...@latest`) will do so on every launch, and a slow
   one delays startup behind a 15s handshake timeout.
4. **Tool calls are capped at 120s** and results at 128 KiB, so a server that streams
   large data will be truncated.

Approving a server is sticky per fingerprint: the consent prompt keys on
`command`/`args`/`env` together, so silently editing any of them re-triggers consent.
That is deliberate — re-approval is the point.

## Candidate servers

None are enabled by default. Each one is an independent supply-chain dependency that
runs as a local process with your privileges — treat adding one as installing
software, not toggling a setting.

| Server | Useful for | Notes |
|---|---|---|
| `npx -y @browsermcp/mcp@latest` | driving a real browser for authenticated flows | built in: `--browser` injects exactly this |
| Burp bridge | moving captured traffic between Burp and the agent | first-party; see the upstream Burp integration |
| [FuzzingLabs/mcp-security-hub](https://github.com/FuzzingLabs/mcp-security-hub) | nmap / nuclei / sqlmap / hashcat wrappers as MCP tools | third-party; **overlaps heavily** with the scanners already in the image |
| [PentesterFlow/OffensiveSET](https://github.com/PentesterFlow/OffensiveSET) | generating pentest conversation datasets | first-party; **dataset generation, not testing** |

### A note on the security hubs

The scanner-wrapper hubs are the ones people reach for first, and they are usually the
wrong choice here. This image already ships nmap, nuclei, sqlmap, ffuf, gobuster,
wfuzz, masscan, arp-scan, subfinder and httpx, and the agent's `shell` tool can run all
of them with no intermediary. Wrapping them in MCP adds a process, a dependency and a
permission surface while removing the ability to compose commands in a pipeline — and
the tool descriptions the agent reads get *worse*, not better, because they are now
one level of indirection away from the real CLI.

Add an MCP server when it provides a capability the image genuinely lacks: a browser
you do not have, a service you cannot reach from the shell, or a structured API that
is painful to drive with curl. Not to re-expose `nmap`.

## Enabling one

Edit the run's `config.json` — the per-run file, not the baked default, so an
experiment stays scoped to one engagement:

```sh
# <state>/run1/.pentesterflow/config.json
```

```json
{
  "backend": "deepseek",
  "model": "deepseek-flash",
  "tooling_profile": "full",
  "max_steps": 200,
  "auto_compact_threshold": 200000,
  "mcp_servers": [
    { "name": "browser", "command": "npx", "args": ["-y", "@browsermcp/mcp@latest"] }
  ]
}
```

`npx` is installed in the image (via the `nodejs`/`npm` Kali packages), so an
`npx`-based server works out of the box. Servers that need credentials should take
them through the `env` map, sourced from the container environment rather than written
into `config.json` — `config.json` is `0600`, but it is also the file most likely to be
copied into a report bundle or a shared lab.

The image's baked default deliberately ships **no** `mcp_servers` entry, so a fresh
run starts no extra processes and makes no unexpected network fetches.
