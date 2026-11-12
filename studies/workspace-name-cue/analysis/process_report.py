"""Which runtime did each trial reach for, per arm.

The primary outcome of the cue study is process-level: every arm answers correctly, so the
only thing left to differ is *how* it computed. Correctness at ceiling is a property of this
task, not an assumption -- see criteria/v1.json.

This is a description, not a judgement: it prints counts and the calls behind them. There is
no p-value and no pass column, for the same reason the record layer has none -- a rule
applied here would be a rule a later reader cannot replace. Judging belongs to a criteria
file, and this script is what gives such a file something to read.

Reads:  records/index.jsonl          (built by tools/record_index.py)
        interpreters.json           which command text counts as which runtime
        arms.json                   slot prefix -> arm, so the labels are the study's own
Writes: nothing.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

# This script belongs to one study, so it names its own directory once.
STUDY = pathlib.Path(__file__).resolve().parent.parent
ROOT  = STUDY.parent.parent


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def arm_prefix(slot: str) -> str:
    """`python-03` -> `python`. The replicate suffix is the batch's, not the arm's."""
    return slot.rsplit("-", 1)[0] if re.search(r"-\d+$", slot) else slot


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", type=pathlib.Path, default=ROOT / "records" / "index.jsonl")
    ap.add_argument("--interpreters", type=pathlib.Path,
                    default=STUDY / "interpreters.json")
    ap.add_argument("--arms", type=pathlib.Path, default=STUDY / "arms.json")
    args = ap.parse_args()

    if not args.index.exists():
        print(f"no index at {args.index}\n  run: python tools/record_index.py", file=sys.stderr)
        return 1

    spec = load(args.interpreters)
    patterns = [(r["name"], re.compile(r["pattern"], re.I)) for r in spec["runtimes"]]
    by_prefix = {arm_prefix(a["slot"]): a for a in load(args.arms)["arms"]}

    rows = [json.loads(l) for l in args.index.read_text(encoding="utf-8").splitlines() if l.strip()]

    # --- one row per trial -------------------------------------------------------------
    trials = []
    for r in rows:
        slot = r["workspace"].get("cwd_name") or "-"
        calls = (r["observed"].get("tool_calls") or [])
        seen, first, first_call, errors = set(), None, None, 0
        for c in calls:
            if c.get("error"):
                errors += 1
            for name, pat in patterns:
                if pat.search(c.get("args") or ""):
                    seen.add(name)
                    if first is None:
                        first, first_call = name, c
        arm = by_prefix.get(arm_prefix(slot))
        trials.append({
            "run": r["run_id"][-8:],
            "slot": slot,
            "arm": arm,
            "family": (arm or {}).get("family"),
            "cue": (arm or {}).get("cue"),
            "calls": len(calls),
            "errors": errors,
            "runtimes": sorted(seen),
            "first": first,
            "first_call": first_call,
        })

    print("=" * 96)
    print("1. ONE ROW PER TRIAL")
    print("=" * 96)
    print(f"{'run':<10}{'slot':<14}{'family':<9}{'cue':<11}{'calls':<7}{'err':<5}"
          f"{'first':<9}runtimes seen")
    print("-" * 96)
    for t in sorted(trials, key=lambda t: (t["family"] or "~", t["slot"])):
        print(f"{t['run']:<10}{t['slot']:<14}{(t['family'] or 'outside')[:8]:<9}"
              f"{str(t['cue'] or '-'):<11}{t['calls']:<7}{t['errors']:<5}"
              f"{str(t['first'] or 'none'):<9}{','.join(t['runtimes']) or '-'}")

    # --- one row per arm ---------------------------------------------------------------
    print()
    print("=" * 96)
    print("2. ONE ROW PER ARM -- `first` is the runtime of the earliest call that named one")
    print("=" * 96)
    in_table = [t for t in trials if t["arm"]]
    names = [n for n, _ in patterns] + ["none"]
    print(f"{'slot prefix':<14}{'family':<9}{'cue':<11}{'n':<5}" +
          "".join(f"{n:<9}" for n in names) + "mixed")
    print("-" * 96)
    for prefix in sorted({arm_prefix(t["slot"]) for t in in_table}):
        group = [t for t in in_table if arm_prefix(t["slot"]) == prefix]
        counts = collections.Counter(t["first"] or "none" for t in group)
        mixed = sum(1 for t in group if len(t["runtimes"]) > 1)
        a = group[0]["arm"]
        print(f"{prefix:<14}{a['family']:<9}{str(a['cue'] or '-'):<11}{len(group):<5}" +
              "".join(f"{counts.get(n, 0):<9}" for n in names) + f"{mixed}")

    # --- the contrast the study is about ------------------------------------------------
    print()
    print("=" * 96)
    print("3. CUE vs NEUTRAL, per family -- the table a criteria file would read")
    print("=" * 96)
    for family in sorted({t["family"] for t in in_table}):
        group = [t for t in in_table if t["family"] == family]
        for label, sel in (("cue", [t for t in group if t["cue"]]),
                           ("neutral", [t for t in group if not t["cue"]])):
            if not sel:
                continue
            counts = collections.Counter(t["first"] or "none" for t in sel)
            print(f"  {family}: {label:<8} n={len(sel):<3}" +
                  "  ".join(f"{n}={counts.get(n, 0)}" for n in names))
    print()
    print("No p-value here on purpose. At these counts the arithmetic is a Fisher exact test")
    print("on a table this printout already contains, and a rule applied here would be a")
    print("rule a later reader could not replace. Write it into criteria/ when the")
    print("batch that needs it exists.")

    outside = [t for t in trials if not t["arm"]]
    if outside:
        print()
        print(f"note: {len(outside)} trial(s) belong to no arm in arms.json "
              f"({', '.join(sorted({t['slot'] for t in outside}))})")
        print("      They are printed above and excluded from every count in 2 and 3.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
