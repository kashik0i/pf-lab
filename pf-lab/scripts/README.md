# Operational helpers

Small scripts for driving and observing a batch of `pf` runs. None of them are
required — `pf` alone is enough for a single engagement. They earn their place when
you fan out across slices and want to know, without watching a terminal, whether the
runs are progressing or quietly stalled.

| Script | Job |
|---|---|
| `pf-monitor.sh` | append a run/finding snapshot to a log on an interval |
| `pf-watch.sh` | same, but *stops* when every run goes idle — modal-aware |
| `make-report.sh` | build one PDF from a set of run directories |

All three are configured through the environment and carry no site-specific values.
`../.env.example` lists every variable in one place.

## Watch for stalls, not just completion

The reason `pf-watch.sh` exists as more than a poller is ISSUE-3/9/14 in
`../pentesterflow-docker/ISSUES.md`: an unattended `pf` run can end up parked on a
modal — the per-turn step limit, or a permission prompt — and *look* finished,
because it stops printing `agent running`. A watcher that greps for the absence of
that string will happily declare "all idle" while three runs sit stalled.

So `pf-watch.sh` samples the **status bar**, treats modals as *busy*, and requires
three consecutive idle samples before it exits. It needs `herdr` for the pane part;
without `WATCH_PANES` it degrades to a container/finding poller.

```sh
WATCH_PANES="w1:p4G w1:p4H" WATCH_RUNS=2 WATCH_MINUTES=30 ./pf-watch.sh ./pf-watch.log
```

## Build the report

`make-report.sh` reads each run's `findings/*.md`, `recon-*.md`, `recon/*.md` and
`brief.md`, and emits one PDF. The report body comes from those files alone — there
is no per-engagement prose in the script.

```sh
RUNS="6:Network & Web Assessment:run6 7:CVE Discovery:run7" \
TARGET_CIDR=10.0.0.0/24 TARGET_IFACE=eth0 INVENTORY=7 \
OUTDIR=./out NAME=my-lab-report \
  ./make-report.sh
```

Each `RUNS` entry is `idx:title:dir`, where `dir` is absolute or relative to
`PF_RUNS_ROOT`. Requirements:

- **python3** with the `markdown` package (tables + fenced code) —
  `pip install markdown`
- **LibreOffice** (`soffice`) — used headlessly for the HTML → PDF conversion

If `soffice` is missing the script fails loudly rather than writing a half-finished
report; the intermediate HTML is left in `BUILD` for inspection.

## A note on the warning box

`WARNINGS` is the honest-coverage channel. If a sweep timed out, if nuclei was
inconclusive, or if you stopped early, say so in the report — a partial scan that
reads like a complete one is worse than no report, because "no finding" will be read
as "clean". The original engagement that motivated this script had all three
conditions and the report states them plainly.
