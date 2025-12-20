#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

out_dir="${KCOV_OUT_DIR:-$ROOT_DIR/coverage}"

python3 - <<'PY' "$out_dir"
import glob
import json
import os
import sys

out_dir = sys.argv[1]

candidates = glob.glob(os.path.join(out_dir, "**", "coverage.json"), recursive=True)
if not candidates:
    print(f"No kcov coverage.json found under: {out_dir}", file=sys.stderr)
    sys.exit(2)

# Prefer merged coverage if present.
preferred = None
for p in candidates:
    if p.endswith(os.path.join("kcov-merged", "coverage.json")):
        preferred = p
        break
coverage_path = preferred or sorted(candidates)[0]

with open(coverage_path, "r", encoding="utf-8") as f:
    data = json.load(f)

# kcov formats vary; try to find totals.
covered = total = None

if isinstance(data, dict):
    totals = data.get("totals")
    if isinstance(totals, dict):
        covered = totals.get("covered_lines") or totals.get("covered")
        total = totals.get("lines") or totals.get("total_lines") or totals.get("total")

    if covered is None or total is None:
        # Some versions put totals at top-level.
        covered = covered or data.get("covered_lines") or data.get("covered")
        total = total or data.get("lines") or data.get("total_lines") or data.get("total")

if covered is None or total is None:
    print(f"Unrecognized kcov JSON schema in {coverage_path}", file=sys.stderr)
    sys.exit(3)

covered = int(covered)
total = int(total)

pct = 100.0 if total == 0 else (covered / total) * 100.0
print(f"kcov: covered_lines={covered} total_lines={total} percent={pct:.4f} (from {coverage_path})")

# Print per-file breakdown when available.
files = None
if isinstance(data, dict):
    files = data.get("files")

rows = []
if isinstance(files, list):
    for entry in files:
        if not isinstance(entry, dict):
            continue
        path = entry.get("file") or entry.get("filename")
        if not path:
            continue

        c = entry.get("covered_lines") or entry.get("covered")
        t = entry.get("total_lines") or entry.get("lines") or entry.get("total")
        p = entry.get("percent_covered") or entry.get("percent")

        try:
            c_i = int(c) if c is not None else None
            t_i = int(t) if t is not None else None
        except (TypeError, ValueError):
            c_i = None
            t_i = None

        if p is not None:
            try:
                p_f = float(p)
            except (TypeError, ValueError):
                p_f = None
        elif c_i is not None and t_i is not None:
            p_f = 100.0 if t_i == 0 else (c_i / t_i) * 100.0
        else:
            p_f = None

        rows.append((p_f, c_i, t_i, path))

if rows:
    rows.sort(key=lambda r: (r[0] if r[0] is not None else -1.0, r[3]))
    print("kcov per-file coverage (worst -> best):")
    for p_f, c_i, t_i, path in rows:
        if p_f is None:
            print(f"  - {path}: (no per-file totals in JSON)")
            continue
        if c_i is not None and t_i is not None:
            print(f"  - {path}: {p_f:.2f}% ({c_i}/{t_i})")
        else:
            print(f"  - {path}: {p_f:.2f}%")

# Allow tiny float noise.
if pct < 99.9999:
    sys.exit(1)
PY
