#!/usr/bin/env python3
"""Verify the record index against a study's declared expectations.

Neutral: knows no run id, no arm, no hypothesis. It reads an expectations file that the
study owns and checks the index against it, so the same checker serves every study.

Expectation kinds:
  same_stimulus        the two must share stimulus_id   (e.g. cosmetically different files)
  different_stimulus   the two must NOT share stimulus_id (the actual treatment)
  same_input           the two must share input_id
  different_input      the two must NOT share input_id

A run is named by any unique suffix of run_id, plus an optional ":trial" suffix.

Usage:
    python verify_index.py --index records/index.jsonl --expect studies/<id>/expectations.json
"""

from __future__ import annotations

import argparse
import json
import pathlib

NEEDS = {
    "same_stimulus": ("stimulus_id", True),
    "different_stimulus": ("stimulus_id", False),
    "same_input": ("input_id", True),
    "different_input": ("input_id", False),
}


def find(rows: list[dict], ref: str) -> dict | None:
    run_ref, _, trial_ref = ref.partition(":")
    hits = [r for r in rows if r["run_id"].endswith(run_ref)]
    if trial_ref:
        hits = [r for r in hits if str(r["trial"]) == trial_ref]
    return hits[0] if len(hits) == 1 else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", type=pathlib.Path, required=True)
    ap.add_argument("--expect", type=pathlib.Path, required=True)
    args = ap.parse_args()

    rows = [json.loads(l) for l in args.index.read_text(encoding="utf-8").splitlines() if l.strip()]
    spec = json.loads(args.expect.read_text(encoding="utf-8"))

    failures = 0
    for i, check in enumerate(spec.get("assertions", []), 1):
        kind = check["kind"]
        if kind not in NEEDS:
            print(f"{i:>2}. SKIP unknown kind {kind!r}")
            continue
        field, want_same = NEEDS[kind]

        a, b = find(rows, check["a"]), find(rows, check["b"])
        if a is None or b is None:
            print(f"{i:>2}. SKIP {check['a']} vs {check['b']} (not uniquely found)")
            failures += 1
            continue

        va, vb = a.get(field), b.get(field)
        same = va is not None and va == vb
        ok = same == want_same
        if not ok:
            failures += 1

        print(f"{i:>2}. [{'PASS' if ok else 'FAIL'}] {kind:<20} {check['a']} vs {check['b']}")
        print(f"        {field}: {va} / {vb}  equal={same}")
        if check.get("why"):
            print(f"        why: {check['why']}")

    total = len(spec.get("assertions", []))
    print(f"\n{total - failures}/{total} passed")
    return 0 if failures == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
