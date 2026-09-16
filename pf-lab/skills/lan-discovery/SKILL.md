---
name: lan-discovery
description: Scope-safe discovery and service enumeration of a local Ethernet or WiFi subnet you own, with the "is the target network actually attached?" preflight and interface pinning baked in. Use when the task is to sweep a LAN slice, enumerate live hosts and services, or when a previous sweep returned nothing and you need to distinguish client isolation from a misrouted scan.
allowed-tools:
  - shell
  - http
  - file_write
---

# LAN discovery playbook

Map a subnet the operator owns: live hosts, then services, then an HTTP surface —
without letting a scan leave the authorized network.

## 0. Preflight — never skip this

The most expensive failure mode in this lab was not a slow scan; it was a scan that
silently egressed onto a network that was **out of scope**. The target WiFi dropped
mid-engagement, NetworkManager fell back to a remembered SSID within one second, and
every remaining probe to the old subnet went out the machine's *other* default route.
The runs were neither useful nor contained.

Before any probe, confirm the target network is actually attached:

```sh
ip -brief addr
ip route get <FIRST_TARGET_IP>
```

`ip route get` must answer with `dev <TARGET_IFACE>`. If it names a different
interface, **stop** — the target is not attached and your probes would leave the
authorized scope. When launching `pf`, enforce the same check mechanically:

```sh
PF_REQUIRE_SUBNET=<TARGET_CIDR> pf --start
```

If the subnet is present but you want a route change to fail loudly rather than
spill, ask the operator to add a blackhole route — and warn them it has metric 0, so
it will shadow the real LAN on reconnect and must be removed first (ISSUE-27):

```sh
sudo ip route add blackhole <TARGET_CIDR>     # remove with: ip route del
```

## 1. Discovery — pin the interface

An unprivileged Kali container can do ARP discovery: `nmap` ships
`cap_net_raw`/`cap_net_admin` file capabilities, so raw scans work as a normal user.
Do **not** waste turns reasoning about needing root, and do not fall back to slow
`-sT` connect scans on a local segment.

```sh
nmap -sn -e <TARGET_IFACE> <TARGET_CIDR>          # ARP sweep, unprivileged
ip neigh                                          # cross-check the ARP cache
```

Always pass `-e <TARGET_IFACE>`. With two default routes present, a scanner that
picks the "primary" interface will pick the wrong network.

`arp-scan` is often the more tempting tool and the more fragile one: it may lack
file capabilities and fail with `CAP_NET_RAW may be required`. If it does, use
nmap's ARP sweep — it already covers the same ground. Do not spend several turns
trying to `setcap` at runtime; that needs `CAP_SETFCAP` and will fail as a normal
user.

## 2. Services

Top 100 ports first; widen only per host where something answered.

```sh
nmap -sS -sV --open -F -e <TARGET_IFACE> <LIVE_HOSTS>
```

Keep output small and redirect to files, then grep the files rather than dumping
whole scans into context.

## 3. HTTP surface

```sh
httpx -silent -title -tech-detect -status-code -o http.txt <TARGETS_OR_URLS>
grep -iE 'admin|login|console' http.txt
```

## 4. When a sweep returns nothing

If discovery finds nothing beyond the gateway, that is a **result, not a failure**:
report it as probable AP/client isolation, which many routers enable by default. Do
not escalate to louder techniques to force a finding — and do not conclude the
target is absent without first re-checking step 0.

## Reporting

Record per host: address, open ports, product/version, and the exact command that
showed it. Unreachable hosts belong in the report as unreachable, not omitted.
Call `confirm_finding` only for a reproduced issue; a clean host is a coverage note,
not a finding.

Dispatch a bounded slice — one nmap invocation's worth of work per delegate — rather
than asking a sub-agent to "assess this host".
