#!/usr/bin/env python3
"""Judge recorded observations against a versioned criteria file.

    judgment = grade(observation, criteria)

That is the whole contract. The observation is expensive and happened once; the criteria
are cheap and will drift. Keeping the two apart is what lets a later reader re-judge the
same measurements under a rule nobody had thought of yet, without paying for them twice.

Reads:   records/tables/observations.csv   (written by analysis/index_tables.R)
         a criteria JSON                   (<study>/criteria/*.json)
Writes:  records/<study>/judgment/<criteria_id>.json

The output carries the sha of both inputs. Re-running with the same inputs reproduces it
byte for byte; re-running with an edited criteria file under the same criteria_id shows up
as a different criteria_sha, which is the difference between "restated" and "quietly
changed".

Stdlib only, like the rest of the record layer.

Usage:
    python tools/grade.py --observations records/tables/observations.csv \
                          --criteria studies/<id>/criteria/v1.json
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _study  # noqa: E402  (which study -- resolved in one place, not four)

OUT_DEFAULT = _study.records_dir() / "judgment"


def sha_bytes(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def load_csv(path: pathlib.Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def as_number(value) -> float | None:
    """A reported value, or None when it is not a usable number."""
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def judge_answer(answer: dict, truth: dict, tol_for) -> tuple[str, list[dict]]:
    """Compare declared fields. Returns (status, field verdicts)."""
    fields = []
    for name, expected in truth.items():
        reported = as_number(answer.get(name))
        rel = tol_for(name)

        if reported is None:
            fields.append({"field": name, "expected": expected, "reported": None,
                           "rel_err": None, "ok": False, "why": "missing or non-numeric"})
            continue

        if expected == 0:
            # Relative error is undefined at zero; fall back to absolute agreement.
            err = abs(reported - expected)
            ok = err <= rel
            fields.append({"field": name, "expected": expected, "reported": reported,
                           "rel_err": None, "abs_err": err, "ok": ok, "why": "abs (truth==0)"})
            continue

        err = abs(reported - expected) / abs(expected)
        fields.append({"field": name, "expected": expected, "reported": reported,
                       "rel_err": err, "ok": err <= rel})

    ok = all(f["ok"] for f in fields)
    return ("pass" if ok else "fail"), fields


def grade(observations: list[dict], criteria: dict) -> dict:
    key_field = criteria.get("task_key", "task_prompt_sha")
    default_rel = float(criteria.get("tolerance", {}).get("rel", 0.0))
    tasks = criteria.get("tasks", {})

    verdicts = []
    for row in observations:
        task_key = row.get(key_field, "")

        base = {
            "run_id": row.get("run_id"),
            "trial": row.get("trial"),
            "task_id": row.get("task_id"),
            "task_key": task_key,
            "stimulus_id": row.get("stimulus_id"),
            "input_id": row.get("input_id"),
        }

        spec = tasks.get(task_key)
        if spec is None:
            verdicts.append({**base, "status": "unruled", "fields": [],
                             "why": f"no criteria for {key_field}={task_key}"})
            continue

        raw = row.get("answer_json") or ""
        if not raw.strip():
            verdicts.append({**base, "status": "missing", "fields": [],
                             "why": "no structured answer recorded"})
            continue

        try:
            answer = json.loads(raw)
        except json.JSONDecodeError as exc:
            verdicts.append({**base, "status": "missing", "fields": [],
                             "why": f"unparseable answer: {exc}"})
            continue

        truth = spec.get("truth", {})
        overrides = spec.get("tolerance", {})

        def tol_for(name: str) -> float:
            return float(overrides.get(name, default_rel))

        status, fields = judge_answer(answer, truth, tol_for)
        verdicts.append({**base, "status": status, "fields": fields,
                         "label": spec.get("label")})

    summary = {}
    for v in verdicts:
        summary[v["status"]] = summary.get(v["status"], 0) + 1

    return {
        "criteria_id": criteria.get("criteria_id"),
        "verdicts": verdicts,
        "summary": summary,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--observations", type=pathlib.Path,
                    default=HERE / "records" / "tables" / "observations.csv")
    ap.add_argument("--criteria", type=pathlib.Path, required=True)
    ap.add_argument("--out", type=pathlib.Path, default=OUT_DEFAULT)
    args = ap.parse_args()

    if not args.observations.exists():
        print(f"no observations at {args.observations}\n"
              f"  run: Rscript analysis/index_tables.R", file=sys.stderr)
        return 1

    observations = load_csv(args.observations)
    criteria = json.loads(args.criteria.read_text(encoding="utf-8"))

    result = grade(observations, criteria)
    result["criteria_sha"] = sha_bytes(args.criteria)
    result["observations_sha"] = sha_bytes(args.observations)
    result["criteria_path"] = str(args.criteria)
    result["observations_path"] = str(args.observations)

    args.out.mkdir(parents=True, exist_ok=True)
    out_path = args.out / f"{result['criteria_id']}.json"
    out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")

    print(f"{'status':<9}{'run':<10}{'tr':<4}{'task':<20}{'stimulus_id':<18}note")
    print("-" * 96)
    for v in result["verdicts"]:
        note = v.get("why", "")
        if v["status"] in ("pass", "fail"):
            worst = max((f for f in v["fields"] if f.get("rel_err") is not None),
                        key=lambda f: f["rel_err"], default=None)
            note = (f"worst rel_err {worst['rel_err']:.2e} on {worst['field']}"
                    if worst else "exact")
        print(f"{v['status']:<9}{(v['run_id'] or '')[-8:]:<10}{v['trial']:<4}"
              f"{(v['task_id'] or '')[:19]:<20}{(v['stimulus_id'] or '-')[:17]:<18}{note}")

    print()
    print(f"summary: {result['summary']}")
    print(f"criteria {result['criteria_id']} (sha {result['criteria_sha']}), "
          f"observations sha {result['observations_sha']}")
    print(f"-> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
