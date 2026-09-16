#!/usr/bin/env bash
# Build a purple-team PDF from one or more pf runs.
#
#   OUTDIR=/path NAME=base ./make-report.sh
#
# Reads, per run dir: findings/*.md, recon-*.md, recon/*.md, brief.md, hosts.txt
# Writes $OUTDIR/$NAME.pdf
#
# The report body is generated from those files alone — there is no per-engagement
# text baked into this script. Configure it with the environment:
#
#   OUTDIR      output directory                  (default: current directory)
#   NAME        output basename, no extension     (default: incident-report-<date>)
#   PF_RUNS_ROOT  where run workdirs live         (default: ~/pf-runs)
#   RUNS        "idx:title:dir" entries, space- or newline-separated. Each dir is
#               absolute or relative to PF_RUNS_ROOT.
#               (default: "1:Network & Web Assessment:run1")
#   TARGET_CIDR the assessed network, shown in the header   (optional)
#   TARGET_IFACE the interface it was assessed over          (optional)
#   TITLE       report title                      (default: Purple Team Network Assessment)
#   WARNINGS    extra text rendered in the warning box      (optional)
#   INVENTORY   run index whose hosts.txt becomes the live-host inventory (optional)
#   BUILD       scratch dir for the HTML (default: ./.report-build)
#
# Examples:
#   RUNS="6:Network & Web Assessment:run6 7:CVE Discovery:run7" ./make-report.sh
#   TARGET_CIDR=10.0.0.0/24 TARGET_IFACE=eth0 INVENTORY=1 ./make-report.sh
#
# Requires: python3 with the `markdown` package, and LibreOffice (`soffice`) for
# the HTML -> PDF step. There is no bundled PDF engine; soffice is what renders it.
set -uo pipefail

BUILD="${BUILD:-./.report-build}"
OUTDIR="${OUTDIR:-$PWD}"
NAME="${NAME:-incident-report-$(date +%Y%m%d)}"
RUNS_SPEC="${RUNS:-1:Network & Web Assessment:run1}"
RUNS_ROOT="${PF_RUNS_ROOT:-$HOME/pf-runs}"
TITLE="${TITLE:-Purple Team Network Assessment}"
WARNINGS="${WARNINGS:-}"
INVENTORY="${INVENTORY:-}"
SCOPE_LINE=""
[ -n "${TARGET_CIDR:-}" ] && SCOPE_LINE="<code>${TARGET_CIDR}</code>"
[ -n "${TARGET_IFACE:-}" ] && SCOPE_LINE="${SCOPE_LINE:+$SCOPE_LINE &middot; }interface <code>${TARGET_IFACE}</code>"
mkdir -p "$BUILD"

# RUNS is passed through the environment rather than parsed into argv, so titles
# containing spaces survive intact.
export REPORT_RUNS="$RUNS_SPEC" REPORT_RUNS_ROOT="$RUNS_ROOT" \
       REPORT_TITLE="$TITLE" REPORT_WARNINGS="$WARNINGS" \
       REPORT_SCOPE="$SCOPE_LINE" REPORT_INVENTORY="$INVENTORY"

python3 - "$BUILD/report.html" <<'PY'
import datetime, glob, html, os, sys
import markdown

out = sys.argv[1]
runs_root = os.environ["REPORT_RUNS_ROOT"]

def parse_runs(spec):
    """'6:OWASP:run6 7:CVE discovery:run7' -> [(idx, title, abs_dir), ...]"""
    runs = []
    for entry in spec.replace("\n", " ").split():
        parts = entry.split(":", 2)
        if len(parts) != 3:
            sys.exit(f"bad RUNS entry {entry!r}: expected idx:title:dir")
        idx, title, path = parts
        if not os.path.isabs(path):
            path = os.path.join(runs_root, path)
        runs.append((idx, title, path))
    return runs

runs = parse_runs(os.environ["REPORT_RUNS"])

def collect(base):
    confirmed = sorted(glob.glob(os.path.join(base, "findings", "*.md")))
    recon = sorted(set(glob.glob(os.path.join(base, "recon-*.md"))
                      + glob.glob(os.path.join(base, "recon", "*.md"))))
    return confirmed, recon

data = {idx: collect(base) for idx, _t, base in runs}

CSS = """
@page { size: A4; margin: 18mm 16mm; }
body { font-family: 'DejaVu Sans', Arial, sans-serif; color:#1b2430; font-size:10.5pt; line-height:1.45; }
h1 { color:#0b2e4f; font-size:20pt; margin:0 0 2mm; }
h2 { color:#0b2e4f; border-bottom:2px solid #cfe0ee; padding-bottom:1mm; margin-top:9mm; font-size:14pt; }
h3 { color:#173b5c; margin:5mm 0 1mm; font-size:11.5pt; }
h4 { color:#173b5c; margin:4mm 0 1mm; font-size:10.5pt; }
.sub { color:#5a6b7b; margin:0 0 1mm; }
table { border-collapse:collapse; width:100%; margin:2mm 0; }
th, td { border:1px solid #c3ced9; padding:2px 5px; text-align:left; vertical-align:top; font-size:9.5pt; }
th { background:#eef4fa; }
code, pre { font-family:'DejaVu Sans Mono', monospace; font-size:8.8pt; background:#f4f6f8; }
pre { padding:2mm; border:1px solid #dde3e9; border-radius:2px; white-space:pre-wrap; }
.finding { border:1px solid #e2e8ee; border-radius:3px; padding:3mm; margin:3mm 0; page-break-inside:avoid; }
.recon { border-left:4px solid #9fb3c8; padding:1mm 0 1mm 3mm; margin:3mm 0; }
.note { background:#fff8e6; border-left:4px solid #e0a800; padding:2mm 3mm; }
.warn { background:#fdecea; border-left:4px solid #c0392b; padding:2mm 3mm; }
details { margin:2mm 0; }
"""

def esc(s): return html.escape(str(s))

def md(path):
    return markdown.markdown(open(path, encoding="utf-8", errors="replace").read(),
                             extensions=["tables", "fenced_code"])

n_conf = sum(len(data[i][0]) for i, _t, _b in runs)

p = ["<!doctype html><html><head><meta charset='utf-8'>",
     f"<style>{CSS}</style></head><body>",
     f"<h1>{esc(os.environ['REPORT_TITLE'])}</h1>"]
scope = os.environ.get("REPORT_SCOPE", "")
if scope:
    p.append(f"<p class='sub'>Authorized self-assessment &middot; {scope}</p>")
p += [f"<p class='sub'>Generated {datetime.datetime.now():%Y-%m-%d %H:%M}</p>"]

warnings = os.environ.get("REPORT_WARNINGS", "").strip()
if warnings:
    p.append(f"<p class='warn'>{esc(warnings)}</p>")
p.append("<p class='note'>Method was strictly read-only discovery: no exploitation, no "
         "authentication attempts, no configuration or state changes.</p>")
p.append("<h2>Executive summary</h2>")
p.append("<table><tr><th>Run</th><th>Focus</th><th>Confirmed findings</th><th>Recon notes</th></tr>")
for idx, title, _base in runs:
    c, r = data[idx]
    p.append(f"<tr><td>run{idx}</td><td>{title}</td><td>{len(c)}</td><td>{len(r)}</td></tr>")
p.append(f"</table><p>Total confirmed findings: <strong>{n_conf}</strong>.</p>")

# Optional live-host inventory, taken from one run's hosts.txt (one address per line).
inv_idx = os.environ.get("REPORT_INVENTORY", "").strip()
if inv_idx:
    for idx, _t, base in runs:
        if idx != inv_idx:
            continue
        inv = os.path.join(base, "hosts.txt")
        if os.path.isfile(inv):
            hosts = [h.strip() for h in open(inv, encoding="utf-8", errors="replace") if h.strip()]
            if hosts:
                p.append("<h2>Live host inventory</h2><p>"
                         + ", ".join(f"<code>{esc(h)}</code>" for h in hosts) + "</p>")

for idx, title, base in runs:
    confirmed, recon = data[idx]
    p.append(f"<h2>Run {idx} &mdash; {title}</h2>")
    brief = os.path.join(base, "brief.md")
    if os.path.isfile(brief):
        p.append("<details><summary>Engagement brief &amp; scope</summary>" + md(brief) + "</details>")
    p.append("<h3>Confirmed findings</h3>")
    if not confirmed:
        p.append("<p><em>No confirmed findings recorded.</em></p>")
    for f in confirmed:
        p.append(f"<section class='finding'><h4>{esc(os.path.basename(f))}</h4>{md(f)}</section>")
    if recon:
        p.append("<h3>Reconnaissance notes (unconfirmed)</h3>")
        for f in recon:
            p.append(f"<section class='recon'><h4>{esc(os.path.basename(f))}</h4>{md(f)}</section>")

p.append("<h2>Remediation priorities</h2>")
p.append("<p>Prioritise network-reachable admin/control interfaces without authentication, "
         "outdated components with a mapped CVE, and services exposing version/telemetry "
         "detail. Re-scan after changes to confirm closure. If coverage was partial, re-run "
         "the remaining hosts before treating the estate as assessed.</p>")
p.append("</body></html>")
open(out, "w", encoding="utf-8").write("\n".join(p))
print("wrote", out)
PY

rm -f "$BUILD/report.pdf"
soffice -env:UserInstallation="file:///tmp/lo_report_$$" --headless \
  --convert-to pdf --outdir "$BUILD" "$BUILD/report.html" >/dev/null 2>&1
if [ ! -s "$BUILD/report.pdf" ]; then echo "PDF conversion failed" >&2; exit 1; fi
mkdir -p "$OUTDIR"
cp "$BUILD/report.pdf" "$OUTDIR/$NAME.pdf"
echo "PDF -> $OUTDIR/$NAME.pdf"
