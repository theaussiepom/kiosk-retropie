#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

out_dir="${KCOV_OUT_DIR:-$ROOT_DIR/coverage}"

python3 - <<'PY' "$out_dir"
import glob
import json
import os
import re
import sys

out_dir = sys.argv[1]

candidates = glob.glob(os.path.join(out_dir, "**", "coverage.json"), recursive=True)
if not candidates:
    print(f"No kcov coverage.json found under: {out_dir}", file=sys.stderr)
    sys.exit(2)

# Prefer the top-level merged coverage if present.
expected_top_level = os.path.join(out_dir, "kcov-merged", "kcov-merged", "coverage.json")
if os.path.exists(expected_top_level):
    coverage_path = expected_top_level
else:
    # Fall back to any merged coverage.
    preferred = None
    for p in sorted(candidates):
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


def _collect_report_js_files(report_root: str) -> list[str]:
    # kcov report output typically contains many *.js files (including per-source data).
    # We'll scan under the directory that contains coverage.json.
    return glob.glob(os.path.join(report_root, "**", "*.js"), recursive=True)


def _pick_js_for_source(js_files: list[str], source_path: str) -> str | None:
    base = os.path.basename(source_path)
    base_l = base.lower()
    # Prefer a js file that includes the basename; tie-breaker: shortest path.
    candidates = [p for p in js_files if base_l in os.path.basename(p).lower()]
    if not candidates:
        return None
    candidates.sort(key=lambda p: (len(p), p))
    return candidates[0]


_LINE_OBJ_RE = re.compile(
    r'\{"lineNum":"(?P<num>\s*\d+)"\s*,\s*"line":"(?P<line>(?:\\.|[^"\\])*)"(?P<rest>[^}]*)\}',
    re.MULTILINE,
)


def _uncovered_lines_from_js(js_text: str) -> list[tuple[int, str]]:
    uncovered: list[tuple[int, str]] = []
    for m in _LINE_OBJ_RE.finditer(js_text):
        rest = m.group("rest")
        if '"class":"lineNoCov"' not in rest and '"class":"lineNoCovHov"' not in rest:
            continue
        num_s = m.group("num").strip()
        try:
            num = int(num_s)
        except ValueError:
            continue
        line = m.group("line")
        # Best-effort unescape of common sequences.
        line = line.replace('\\\\', '\\')
        line = line.replace('\\"', '"')
        line = line.replace('\\t', '\t')
        line = line.replace('\\n', '\\n')
        uncovered.append((num, line))
    return uncovered


def _print_uncovered_details(data: dict, coverage_path: str) -> None:
    files = data.get("files")
    if not isinstance(files, list):
        return

    report_root = os.path.dirname(coverage_path)
    js_files = _collect_report_js_files(report_root)
    if not js_files:
        return

    # Focus on the worst few files to keep logs readable.
    with_pct = []
    for entry in files:
        if not isinstance(entry, dict):
            continue
        path = entry.get("file")
        if not path:
            continue
        try:
            p = float(entry.get("percent_covered"))
        except (TypeError, ValueError):
            continue
        with_pct.append((p, path))

    if not with_pct:
        return
    with_pct.sort(key=lambda t: (t[0], t[1]))
    worst = with_pct[:5]

    print("kcov uncovered lines (best-effort from report JS):")
    for p, path in worst:
        js_path = _pick_js_for_source(js_files, path)
        if not js_path:
            print(f"  - {path}: (no matching report JS found)")
            continue
        try:
            with open(js_path, "r", encoding="utf-8", errors="replace") as f:
                js_text = f.read()
        except OSError:
            print(f"  - {path}: (failed to read {js_path})")
            continue
        uncovered = _uncovered_lines_from_js(js_text)
        if not uncovered:
            print(f"  - {path}: (no uncovered lines found in {os.path.basename(js_path)})")
            continue
        uncovered.sort(key=lambda t: t[0])
        # Print up to 12 uncovered lines per file.
        print(f"  - {path}:")
        for num, line in uncovered[:12]:
            print(f"      L{num}: {line}")


if pct < 99.9999 and isinstance(data, dict):
    # Only dump detailed uncovered lines when failing the gate.
    try:
        _print_uncovered_details(data, coverage_path)
    except Exception as e:
        print(f"kcov: failed to extract uncovered line details: {e}", file=sys.stderr)

# Allow tiny float noise.
if pct < 99.9999:
    sys.exit(1)
PY
