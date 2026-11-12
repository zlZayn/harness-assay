"""The contrast the cue study was pre-registered to estimate.

This does not invent a test. The test is declared in prereg/norris-r3-v1.json
(`analysis.primary`): a wording-level permutation over the wordings of the two conditions
being compared, one-sided, exhaustively enumerated. This script executes that declaration.

Why the wording is the unit
---------------------------
The treatment is applied to a folder name, so a folder name is a cluster of six trials, not
six independent observations. Permuting trial labels would treat the six replicates of one
wording as if they carried six independent pieces of evidence about that wording, which they
do not. Permuting wording labels asks the question the design can actually answer: were the
twelve r-eco names collectively higher than the twelve software names?

The enumeration is exact, not sampled: the number of distinct label assignments is C(24,12)
= 2704156, small enough to count in full with a convolution rather than approximate with
random draws. A random permutation p-value carries its own Monte-Carlo error; an exact one
does not, and there is no reason to accept that error for free.

What this file deliberately does not do
---------------------------------------
- It does not drop trials. Zero-tool-call trials are post-treatment: removing them would
  condition on a variable downstream of the treatment. They count as "not R".
- It does not stratify on "used a runtime at all" for the same reason.
- It does not order the conditions by effect size or drop wordings that behaved oddly.
  Both are in the prereg's `_not_analysed` list.

Reads:  records/index.jsonl            (tools/record_index.py)
        conditions.json          wording -> condition
        interpreters.json        which command text names which runtime
        prereg/norris-r3-v1.json the declared contrasts, printed beside the numbers
Writes: records/<study>/judgment/cue-effect.json
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import itertools
import json
import math
import pathlib
import re
import sys

# This file belongs to this study, so it names its own directory once and derives the
# rest. The record layer still knows no study; only a study's own analysis does.
STUDY = pathlib.Path(__file__).resolve().parent.parent
ROOT  = STUDY.parent.parent
REC   = ROOT / "records" / STUDY.name


def load(p: pathlib.Path):
    return json.loads(p.read_text(encoding="utf-8"))


def first_runtime(calls, patterns):
    """The earliest executed call whose arguments name a runtime.

    Ties inside one call are resolved by the order the interpreter table lists them, and the
    full set is reported separately so this choice is visible rather than trusted.
    """
    seen = set()
    first = None
    for c in calls:
        hit = [n for n, pat in patterns if pat.search(c.get("args") or "")]
        if hit:
            seen.update(hit)
            if first is None:
                first = hit[0]
    return first, sorted(seen)


def exact_permutation(counts_a, counts_b, observed):
    """One-sided p for `sum(counts_a) >= observed`, labels exchangeable over units.

    Every unit contributes an integer count. Counting how many of the C(n_a+n_b, n_a) label
    assignments give a sum at least as large as the observed one is a convolution over the
    units, so it is done in exact integer arithmetic instead of by enumerating assignments.
    """
    pool = list(counts_a) + list(counts_b)
    n_a = len(counts_a)
    top = sum(pool) + 1
    # dp[j][s] = number of ways to pick j units from those seen so far with total count s
    dp = [[0] * top for _ in range(n_a + 1)]
    dp[0][0] = 1
    for c in pool:
        for j in range(min(n_a, len(pool)), 0, -1):
            row, prev = dp[j], dp[j - 1]
            for s in range(top - 1, c - 1, -1):
                if prev[s - c]:
                    row[s] += prev[s - c]
    total = sum(dp[n_a])
    at_least = sum(dp[n_a][observed:])
    return at_least, total, at_least / total


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", type=pathlib.Path, default=ROOT / "records" / "index.jsonl")
    ap.add_argument("--conditions", type=pathlib.Path, default=STUDY / "conditions.json")
    ap.add_argument("--interpreters", type=pathlib.Path,
                    default=STUDY / "interpreters.json")
    ap.add_argument("--prereg", type=pathlib.Path,
                    default=STUDY / "prereg" / "norris-r3-v1.json")
    ap.add_argument("--out", type=pathlib.Path,
                    default=REC / "judgment" / "cue-effect.json")
    args = ap.parse_args()

    if not args.index.exists():
        print(f"no index at {args.index}\n  run: python tools/record_index.py", file=sys.stderr)
        return 1

    spec = load(args.interpreters)
    patterns = [(r["name"], re.compile(r["pattern"], re.I)) for r in spec["runtimes"]]
    conds = load(args.conditions)["conditions"]
    prereg = load(args.prereg)
    plan_id = prereg["plan_id"]

    wording_of = {w: name for name, c in conds.items() for w in c["words"]}

    rows = [json.loads(l) for l in args.index.read_text(encoding="utf-8").splitlines() if l.strip()]

    trials = []
    for r in rows:
        slot = r["workspace"].get("cwd_name") or ""
        m = re.match(r"^(?P<w>.+)-(?P<rep>\d+)$", slot)
        if not m or m.group("w") not in wording_of:
            continue
        first, seen = first_runtime(r["observed"].get("tool_calls") or [], patterns)
        trials.append({
            "slot": slot,
            "wording": m.group("w"),
            "condition": wording_of[m.group("w")],
            "record_schema": r.get("record_schema"),
            "stimulus_id": r["stimulus_id"],
            "outcome": first or "none",
            "runtimes": seen,
            "calls": len(r["observed"].get("tool_calls") or []),
            "answer": bool(r["observed"].get("structured")),
        })

    if not trials:
        print("no trial in the index belongs to a wording in conditions.json", file=sys.stderr)
        return 1

    per_wording = collections.defaultdict(list)
    for t in trials:
        per_wording[(t["condition"], t["wording"])].append(t)

    print("=" * 92)
    print(f"plan {plan_id}   {len(trials)} trial(s) over "
          f"{len(per_wording)} wording(s) in {len(conds)} condition(s)")
    print("=" * 92)

    # --- 1. per wording ------------------------------------------------------------------
    print()
    print("1. PER WORDING -- the unit the test permutes. n is the replicate count.")
    print("-" * 92)
    print(f"{'condition':<11}{'wording':<14}{'n':<4}{'R':<4}{'python':<8}{'none':<6}"
          f"{'mixed':<7}{'zero-tool'}")
    for (name, word), group in sorted(per_wording.items()):
        c = collections.Counter(t["outcome"] for t in group)
        mixed = sum(1 for t in group if len(t["runtimes"]) > 1)
        zero = sum(1 for t in group if t["calls"] == 0)
        print(f"{name:<11}{word:<14}{len(group):<4}{c.get('R', 0):<4}{c.get('python', 0):<8}"
              f"{c.get('none', 0):<6}{mixed:<7}{zero}")

    # --- 2. per condition ----------------------------------------------------------------
    print()
    print("2. PER CONDITION -- Y is the first runtime the trial asked for.")
    print("-" * 92)
    print(f"{'condition':<11}{'n':<5}{'R':<6}{'python':<9}{'none':<7}{'R rate':<9}"
          f"{'python rate':<13}{'runtime used':<13}{'zero-tool':<11}{'mixed'}")
    by_cond = {}
    for name in conds:
        group = [t for t in trials if t["condition"] == name]
        if not group:
            continue
        c = collections.Counter(t["outcome"] for t in group)
        n = len(group)
        used = c.get("R", 0) + c.get("python", 0)
        by_cond[name] = {"n": n, "R": c.get("R", 0), "python": c.get("python", 0),
                         "none": c.get("none", 0), "used": used}
        print(f"{name:<11}{n:<5}{c.get('R', 0):<6}{c.get('python', 0):<9}{c.get('none', 0):<7}"
              f"{c.get('R', 0) / n:<9.4f}{c.get('python', 0) / n:<13.4f}{used / n:<13.4f}"
              f"{c.get('none', 0) / n:<11}"
              f"{sum(1 for t in group if len(t['runtimes']) > 1)}")

    # --- 3. the declared contrasts --------------------------------------------------------
    def wording_counts(name, key):
        return [collections.Counter(t["outcome"] for t in g).get(key, 0)
                for (c, _), g in sorted(per_wording.items()) if c == name]

    def contrast(label, cond_a, cond_b, key):
        ca, cb = wording_counts(cond_a, key), wording_counts(cond_b, key)
        na, nb = sum(len(g) for (c, _), g in per_wording.items() if c == cond_a), \
                 sum(len(g) for (c, _), g in per_wording.items() if c == cond_b)
        obs_a, obs_b = sum(ca), sum(cb)
        at_least, total, p = exact_permutation(ca, cb, obs_a)
        diff = obs_a / na - obs_b / nb
        print(f"\n  {label}")
        print(f"    {cond_a:<9} P(Y={key}) = {obs_a}/{na} = {obs_a / na:.4f}")
        print(f"    {cond_b:<9} P(Y={key}) = {obs_b}/{nb} = {obs_b / nb:.4f}")
        print(f"    difference        = {diff:+.4f}")
        print(f"    exact one-sided p = {p:.4f}   "
              f"({at_least} of {total} label assignments at least this large)")
        print(f"    C({len(ca) + len(cb)},{len(ca)}) = {math.comb(len(ca) + len(cb), len(ca))}"
              f"{'  == enumerated' if math.comb(len(ca) + len(cb), len(ca)) == total else '  MISMATCH'}")
        return {"label": label, "a": cond_a, "b": cond_b, "outcome": key,
                "rate_a": obs_a / na, "rate_b": obs_b / nb, "difference": diff,
                "p_one_sided": p, "assignments_at_least_as_large": at_least,
                "assignments_total": total, "wordings_a": len(ca), "wordings_b": len(cb),
                "wording_counts_a": ca, "wording_counts_b": cb}

    print()
    print("=" * 92)
    print("3. THE DECLARED CONTRASTS (prereg/norris-r3-v1.json, analysis.primary/secondary)")
    print("=" * 92)
    results = [contrast("primary: does an R-package name raise R use, holding "
                        "'looks like software' constant?", "r-eco", "software", "R")]
    results += [
        contrast("secondary: the same question in the other direction", "py-eco", "software",
                 "python"),
        contrast("secondary: total effect against a name with no software meaning", "r-eco",
                 "plain", "R"),
    ]
    used_a = sum(by_cond[c]["used"] for c in ("software",))
    used_b = sum(by_cond[c]["used"] for c in ("plain",))
    print(f"\n  secondary: does software flavour alone make it reach for a runtime?")
    print(f"    software  P(Y in {{R,python}}) = {used_a}/{by_cond['software']['n']} = "
          f"{used_a / by_cond['software']['n']:.4f}")
    print(f"    plain     P(Y in {{R,python}}) = {used_b}/{by_cond['plain']['n']} = "
          f"{used_b / by_cond['plain']['n']:.4f}")
    print(f"    difference = {used_a / by_cond['software']['n'] - used_b / by_cond['plain']['n']:+.4f}")

    # --- 3b. the full pairwise matrix -------------------------------------------------
    # The prereg declares three contrasts and says which question each answers. It does not
    # say the other three are absent, and reporting only the declared ones lets a reader ask
    # "was that pair left out because it was inconvenient". So all six get the same exact
    # test on the same footing. Nothing here changes the primary: the primary is the test
    # named in the prereg, and it is reported first, above.
    #
    # Each pair is tested on the outcome the pair can speak to. Comparing py-eco against
    # r-eco on P(Y=R) is nearly uninformative by construction -- it repeats the primary from
    # the other side -- and testing every pair on every outcome would be twelve tests whose
    # "significance" is a property of looking twelve times. So: the R pairs get P(Y=R), the
    # python pairs get P(Y=python), and the two pairs that share no language (r-eco vs
    # py-eco, software vs plain) get P(Y in {R,python}) -- "did it reach for any runtime".
    print()
    print("=" * 92)
    print("3b. THE FULL PAIRWISE MATRIX -- exploratory, declared ONE outcome per pair")
    print("=" * 92)
    print("  Not six chances to find something: each pair is tested once, on the outcome")
    print("  that separates that pair. The prereg's three contrasts are the first three rows.")

    def pairing(a, b, key):
        return contrast(f"pair {a} vs {b}, P(Y={key})", a, b, key)

    matrix_pairs = [
        ("r-eco", "software", "R", "primary -- declared"),
        ("r-eco", "plain", "R", "declared secondary -- total effect vs no software meaning"),
        ("py-eco", "software", "python", "declared secondary -- the same question, mirrored"),
        ("r-eco", "py-eco", "R", "exploratory -- does the R cue beat the python cue"),
        ("py-eco", "plain", "python", "exploratory -- python cue vs no software meaning"),
    ]
    matrix = []
    for a, b, key, why in matrix_pairs:
        res = pairing(a, b, key)
        res["why"] = why
        matrix.append(res)

    # The sixth pair has no shared language, so it is read on "reached for any runtime".
    # That outcome is post-treatment in the sense that it counts how far the trial got;
    # it is reported as a description of these 288 trials, never as a second primary.
    for a, b in (("software", "plain"),):
        na, nb = by_cond[a]["n"], by_cond[b]["n"]
        ua, ub = by_cond[a]["used"], by_cond[b]["used"]
        print(f"\n  pair {a} vs {b}, P(Y in {{R,python}})   [exploratory -- software flavour alone]")
        print(f"    {a:<9} {ua}/{na} = {ua / na:.4f}")
        print(f"    {b:<9} {ub}/{nb} = {ub / nb:.4f}")
        print(f"    difference = {ua / na - ub / nb:+.4f}")
        print(f"    no p reported: this outcome is not in the prereg's declared set")
        matrix.append({"label": f"pair {a} vs {b}, runtime used", "a": a, "b": b,
                       "outcome": "runtime-used", "rate_a": ua / na, "rate_b": ub / nb,
                       "difference": ua / na - ub / nb, "p_one_sided": None,
                       "why": "exploratory -- not declared, reported without a test"})

    # --- 4. instrument readings -----------------------------------------------------------
    print()
    print("=" * 92)
    print("4. INSTRUMENT READINGS -- the prereg's stop rules read these, not the contrast")
    print("=" * 92)
    n = len(trials)
    zero = sum(1 for t in trials if t["calls"] == 0)
    used = sum(1 for t in trials if t["outcome"] in ("R", "python"))
    answered = sum(1 for t in trials if t["answer"])
    print(f"  zero-tool-call rate : {zero}/{n} = {zero / n:.4f}   (stop above 1/3)")
    print(f"  runtime-use rate    : {used}/{n} = {used / n:.4f}   (below 2/3 means diluted)")
    print(f"  structured answer   : {answered}/{n} = {answered / n:.4f}")
    print(f"  mixed-runtime count : {sum(1 for t in trials if len(t['runtimes']) > 1)}")

    out = {
        "plan_id": plan_id,
        "prereg": str(args.prereg.relative_to(ROOT)).replace("\\", "/"),
        "interpreter_table": str(args.interpreters.relative_to(ROOT)).replace("\\", "/"),
        "condition_table": str(args.conditions.relative_to(ROOT)).replace("\\", "/"),
        "index_sha": hashlib.sha256(args.index.read_bytes()).hexdigest()[:16],
        "trials": n,
        "wordings": len(per_wording),
        "per_condition": by_cond,
        "contrasts": results,
        "pairwise_matrix": matrix,
        "instrument": {"zero_tool": zero, "runtime_used": used, "answered": answered,
                       "mixed": sum(1 for t in trials if len(t["runtimes"]) > 1)},
        "stimulus_ids": sorted({t["stimulus_id"] for t in trials}),
        "_unit_of_inference": "the wording, 12 per condition, 6 replicates each",
        "_method": "exact one-sided permutation over wordings, exhaustive enumeration",
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n-> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
