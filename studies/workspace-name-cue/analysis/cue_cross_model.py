"""Paired wording-level comparison of two already completed model batches.

The primary estimand is declared in prereg/norris-r4-v1.json:
    Delta(candidate) - Delta(reference)
where each model's Delta is P(Y=R|r-eco) - P(Y=R|software).

The bootstrap resamples the same wording clusters in both models, preserving the
paired design. It describes between-batch heterogeneity; it does not turn calendar
and host-version differences into a randomized model effect. Stdlib only.
"""
from __future__ import annotations

import argparse
import csv
import json
import pathlib
import random
import sys

STUDY = pathlib.Path(__file__).resolve().parent.parent
ROOT = STUDY.parent.parent
REC = ROOT / "records" / STUDY.name


def load_trials(path: pathlib.Path):
    with path.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise ValueError(f"no trials in {path}")
    models = {r["model"] for r in rows}
    if len(models) != 1:
        raise ValueError(f"expected one model in {path}, got {sorted(models)}")
    model = models.pop()
    out = {}
    for condition in ("r-eco", "software"):
        rates = {}
        for wording in sorted({r["wording"] for r in rows if r["condition"] == condition}):
            mine = [r for r in rows if r["condition"] == condition and r["wording"] == wording]
            if len(mine) != 6:
                raise ValueError(f"{model}/{wording}: expected 6 trials, got {len(mine)}")
            rates[wording] = sum(r["first_runtime"] == "R" for r in mine) / 6
        if len(rates) != 12:
            raise ValueError(f"{model}/{condition}: expected 12 wordings, got {len(rates)}")
        out[condition] = rates
    return model, rows, out


def delta(rates):
    a = sum(rates["r-eco"].values()) / 12
    b = sum(rates["software"].values()) / 12
    return a - b


def quantile(sorted_values, probability):
    if not sorted_values:
        raise ValueError("empty bootstrap distribution")
    position = (len(sorted_values) - 1) * probability
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    fraction = position - lower
    return sorted_values[lower] * (1 - fraction) + sorted_values[upper] * fraction


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference", type=pathlib.Path, default=REC / "trials.csv")
    ap.add_argument("--candidate", type=pathlib.Path, default=REC / "trials-kimi.csv")
    ap.add_argument("--out", type=pathlib.Path, default=REC / "judgment" / "cross-model.json")
    ap.add_argument("--reference-effect", type=pathlib.Path,
                    default=REC / "judgment" / "cue-effect.json")
    ap.add_argument("--candidate-effect", type=pathlib.Path,
                    default=REC / "judgment" / "cue-effect-kimi.json")
    ap.add_argument("--summary", type=pathlib.Path,
                    default=REC / "summary" / "cross-model.csv")
    ap.add_argument("--display", type=pathlib.Path,
                    default=REC / "summary" / "cross-model-display.csv")
    ap.add_argument("--wordings", type=pathlib.Path,
                    default=REC / "summary" / "cross-model-wordings.csv")
    ap.add_argument("--reps", type=int, default=10000)
    ap.add_argument("--seed", type=int, default=20261121)
    args = ap.parse_args()
    if args.reps < 1:
        print("--reps must be positive", file=sys.stderr)
        return 2

    ref_model, ref_rows, ref = load_trials(args.reference)
    cand_model, cand_rows, cand = load_trials(args.candidate)
    if ref_model == cand_model:
        print("reference and candidate must be different models", file=sys.stderr)
        return 2
    if set(ref) != set(cand):
        print("condition sets differ", file=sys.stderr)
        return 2
    for condition in ref:
        if set(ref[condition]) != set(cand[condition]):
            print(f"wording sets differ in {condition}", file=sys.stderr)
            return 2

    ref_delta = delta(ref)
    cand_delta = delta(cand)
    observed = cand_delta - ref_delta
    rng = random.Random(args.seed)
    r_words = sorted(ref["r-eco"])
    s_words = sorted(ref["software"])
    distribution = []
    for _ in range(args.reps):
        r_sample = [rng.choice(r_words) for _ in r_words]
        s_sample = [rng.choice(s_words) for _ in s_words]
        rd = (sum(ref["r-eco"][w] for w in r_sample) / 12
              - sum(ref["software"][w] for w in s_sample) / 12)
        cd = (sum(cand["r-eco"][w] for w in r_sample) / 12
              - sum(cand["software"][w] for w in s_sample) / 12)
        distribution.append(cd - rd)
    distribution.sort()
    ci = [quantile(distribution, 0.025), quantile(distribution, 0.975)]

    def condition_summary(rows, rates, model):
        return {
            "model": model,
            "trials": len(rows),
            "r_eco_R": sum(r["first_runtime"] == "R" for r in rows if r["condition"] == "r-eco"),
            "software_R": sum(r["first_runtime"] == "R" for r in rows if r["condition"] == "software"),
            "r_eco_rate": sum(rates["r-eco"].values()) / 12,
            "software_rate": sum(rates["software"].values()) / 12,
            "delta": delta(rates),
        }

    ref_summary = condition_summary(ref_rows, ref, ref_model)
    cand_summary = condition_summary(cand_rows, cand, cand_model)
    ref_effect = json.loads(args.reference_effect.read_text(encoding="utf-8"))
    cand_effect = json.loads(args.candidate_effect.read_text(encoding="utf-8"))
    for effect, computed in ((ref_effect, ref_delta), (cand_effect, cand_delta)):
        primary = effect["contrasts"][0]
        if abs(primary["difference"] - computed) > 1e-12:
            raise ValueError("effect JSON and trial-table Delta disagree")

    out = {
        "estimand": "Delta(candidate) - Delta(reference)",
        "reference": ref_summary,
        "candidate": cand_summary,
        "difference_of_deltas": observed,
        "paired_wording_bootstrap": {
            "reps": args.reps,
            "seed": args.seed,
            "ci95": ci,
            "unit": "the same 24 wording clusters resampled in both models",
        },
        "_scope": "Between-batch heterogeneity, not a randomized model effect; host version and calendar batch also differ.",
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes((json.dumps(out, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

    args.summary.parent.mkdir(parents=True, exist_ok=True)
    with args.summary.open("w", encoding="utf-8", newline="") as fh:
        fields = ["reference_model", "candidate_model", "reference_delta", "candidate_delta",
                  "difference_of_deltas", "ci95_low", "ci95_high", "reps", "seed"]
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerow({
            "reference_model": ref_model,
            "candidate_model": cand_model,
            "reference_delta": ref_delta,
            "candidate_delta": cand_delta,
            "difference_of_deltas": observed,
            "ci95_low": ci[0],
            "ci95_high": ci[1],
            "reps": args.reps,
            "seed": args.seed,
        })

    with args.display.open("w", encoding="utf-8", newline="") as fh:
        fields = ["model", "r_eco", "software", "delta", "p"]
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for summary, effect in ((ref_summary, ref_effect), (cand_summary, cand_effect)):
            writer.writerow({
                "model": summary["model"],
                "r_eco": f"{summary['r_eco_R']}/72",
                "software": f"{summary['software_R']}/72",
                "delta": f"{summary['delta']:+.4f}",
                "p": f"{effect['contrasts'][0]['p_one_sided']:.4f}",
            })

    with args.wordings.open("w", encoding="utf-8", newline="") as fh:
        fields = ["condition", "wording", "reference_model", "candidate_model",
                  "reference_rate", "candidate_rate"]
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for condition in ("r-eco", "software"):
            for wording in sorted(ref[condition]):
                writer.writerow({
                    "condition": condition,
                    "wording": wording,
                    "reference_model": ref_model,
                    "candidate_model": cand_model,
                    "reference_rate": ref[condition][wording],
                    "candidate_rate": cand[condition][wording],
                })

    print(f"reference {ref_model}: Delta = {ref_delta:+.4f}")
    print(f"candidate {cand_model}: Delta = {cand_delta:+.4f}")
    print(f"difference of deltas   = {observed:+.4f}")
    print(f"paired wording 95% CI  = [{ci[0]:+.4f}, {ci[1]:+.4f}] "
          f"({args.reps} resamples, seed {args.seed})")
    print(f"-> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
