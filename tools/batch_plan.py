#!/usr/bin/env python3
"""Turn a study's arm table into a run plan, and check it before anything is spent.

A batch is expensive and irreversible: each trial is a model call, and a slot is one run.
So the plan is a file, checked twice -- once when it is made, and again after the batch,
against what actually landed on disk.

Reads:   study/cue-arms.json      which slots, what each one is meant to test
         study/tasks/<id>.json    the prompt and schema, as the single source of them
Writes:  records/plan/<plan_id>.jsonl    one line per trial to run
         records/plan/<plan_id>.md        the same, for a human to read before approving

Nothing here calls a model.

    python tools/batch_plan.py --task wells-meansd --k 5 [--out ...]
    python tools/batch_plan.py --task wells-meansd --k 5 --verify

--verify compares the plan against the slots that exist and the runs recorded so far, and
reports three separate things: missing (not yet run), duplicated (one slot, two runs), and
unexpected (a run whose slot is not in the plan).

Stdlib only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
ARMS = HERE / "study" / "cue-arms.json"
TASKS = HERE / "study" / "tasks"
PLAN_DIR = HERE / "records" / "plan"
RUNS = pathlib.Path(os.environ.get("DSH_HOME") or pathlib.Path.home() / ".dsh") \
    / "harness-dispatcher" / "runs"


def slots_root() -> pathlib.Path:
    """Where the batch's workspaces will live. Stated, never assumed.

    A literal default here would be a machine path inside a tool that is meant to know no
    study, and it would silently disagree with the root the arm table was counted against.
    """
    chosen = (os.environ.get("ASSAY_SLOTS") or "").strip()
    if not chosen:
        raise SystemExit(
            "slot root unknown: set ASSAY_SLOTS (the same root the arm table records)\n"
            "  the plan embeds absolute cwds, so the root has to be stated"
        )
    return pathlib.Path(chosen)


def canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def sha(obj, n: int = 12) -> str:
    text = obj if isinstance(obj, str) else canon(obj)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:n]


def build(selected: list[dict], task: dict, k: int, plan_id: str, root: pathlib.Path) -> list[dict]:
    """One row per trial, interleaved by replicate.

    The slot name carries the cue, so the replicate is a suffix -- but the *sequence* is not
    a detail. On six runs of one identical condition (same harness, same task, same schema)
    the outcomes fell monotonically with position: Spearman(order, wall time) = -0.83,
    (order, steps) = -0.90, (order, output tokens) = -0.83. Six points cannot settle whether
    that is drift or noise, and that is exactly the problem: a plan that spends all five
    replicates of one arm before touching the next cannot separate an arm effect from a
    position effect, and the ambiguity is unresolvable after the fact.

    Interleaving does not remove drift. It spreads it across arms, which is the most one
    batch can do. `order` is written into the plan so the sequence is evidence rather than a
    convention somebody has to remember.
    """
    rows = []
    order = 0
    for rep in range(1, k + 1):
        for arm in selected:
            order += 1
            slot = f"{arm['slot'].rsplit('-', 1)[0]}-{rep:02d}"
            rows.append({
                "plan_id": plan_id,
                "order": order,
                "slot": slot,
                "rep": rep,
                "family": arm["family"],
                "cue": arm["cue"],
                "expected_path_tokens": arm["tokens"],
                "expected_delta": arm["delta_vs_shortest"],
                "cwd": str(root / slot),
                "task_id": task["id"],
                "prompt_sha": sha(task["prompt"]),
                "schema_sha": sha(task["schema"]),
            })
    return rows


def verify(rows: list[dict], task: dict, expect_complete: bool, root: pathlib.Path) -> int:
    """Is the board in the state the plan assumes?

    Four states, and only three of them are problems:

      done       exactly one recorded run -- fine
      pending    no slot, no run            -- normal before a batch
      OCCUPIED   a slot exists but no run   -- a leftover directory; create would refuse it
      DUPLICATE  one slot, several runs     -- two trials stacked into one history

    `--expect-complete` turns pending into a problem too, which is the post-batch reading.
    Rows are listed in plan order, not sorted by name: the board is read in the sequence it
    will run, so a mis-ordered plan is visible here rather than discovered afterwards.
    """
    problems = 0

    recorded: dict[str, list[pathlib.Path]] = {}
    for d in sorted(RUNS.iterdir()) if RUNS.is_dir() else []:
        rj = d / "run.json"
        if not rj.exists():
            continue
        run = json.loads(rj.read_text(encoding="utf-8"))
        cwd = run.get("task", {}).get("cwd") or ""
        recorded.setdefault(pathlib.PureWindowsPath(cwd).name, []).append(d)

    done = pending = 0
    print(f"{'order':<7}{'slot':<14}{'on disk':<10}{'runs':<6}state")
    print("-" * 60)
    for row in rows:
        slot = row["slot"]
        exists = (root / slot).is_dir()
        runs = recorded.get(slot, [])
        if len(runs) > 1:
            state, bad = f"DUPLICATE ({len(runs)})", True
        elif len(runs) == 1:
            state, bad = "done", False
            done += 1
        elif exists:
            state, bad = "OCCUPIED (leftover slot)", True
        else:
            state, bad = "pending", expect_complete
            if not expect_complete:
                pending += 1
        problems += 1 if bad else 0
        print(f"{row['order']:<7}{slot:<14}{str(exists):<10}{len(runs):<6}{state}")

    unexpected = sorted(set(recorded) - {r["slot"] for r in rows})
    if unexpected:
        print("\nruns recorded outside this plan (older probes -- not a failure):")
        for name in unexpected:
            for d in recorded[name]:
                print(f"  {name:<14} {d.name}")

    # The task bytes are the one thing that must be identical across every arm.
    shas_prompt = {r["prompt_sha"] for r in rows}
    shas_schema = {r["schema_sha"] for r in rows}
    print(f"\nprompt sha(s) across the plan : {sorted(shas_prompt)}")
    print(f"schema sha(s) across the plan : {sorted(shas_schema)}")
    if len(shas_prompt) != 1 or len(shas_schema) != 1:
        print("  FAIL: the task is not byte-identical across arms")
        problems += 1

    print(f"\n{len(rows)} planned: {done} done, {pending} pending, "
          f"{problems} problem(s)")
    return 0 if problems == 0 else 2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True, help="a file name under study/tasks, without .json")
    ap.add_argument("--k", type=int, default=5, help="replicates per arm")
    ap.add_argument("--family", default="",
                    help="comma-separated families to include; default every arm in the table")
    ap.add_argument("--verify", action="store_true", help="check the plan against disk")
    ap.add_argument("--expect-complete", action="store_true",
                    help="with --verify: also fail on trials that have not run yet")
    args = ap.parse_args()

    arms = json.loads(ARMS.read_text(encoding="utf-8"))
    task_path = TASKS / f"{args.task}.json"
    if not task_path.exists():
        print(f"no task at {task_path}", file=sys.stderr)
        return 1
    task = json.loads(task_path.read_text(encoding="utf-8"))

    wanted = [f.strip() for f in args.family.split(",") if f.strip()]
    selected = [a for a in arms["arms"] if not wanted or a["family"] in wanted]
    if not selected:
        known = sorted({a["family"] for a in arms["arms"]})
        print(f"no arm in families {wanted}; the table declares {known}", file=sys.stderr)
        return 1

    # Order is part of the plan's identity: the same arms in a different sequence are a
    # different experiment, and the id should not let the two look like the same thing.
    plan_id = f"{args.task}-k{args.k}-" \
              f"{sha(selected + [task['prompt'], task['schema'], 'rep-major'])}"
    root = slots_root()
    rows = build(selected, task, args.k, plan_id, root)

    if args.verify:
        print(f"plan {plan_id}\n")
        return verify(rows, task, args.expect_complete, root)

    PLAN_DIR.mkdir(parents=True, exist_ok=True)
    out = PLAN_DIR / f"{plan_id}.jsonl"
    with out.open("w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(canon(r) + "\n")

    md = PLAN_DIR / f"{plan_id}.md"
    lines = [f"# plan {plan_id}", "",
             f"task `{task['id']}` - {len(rows)} trials, k={args.k}, "
             f"{len(selected)} arm(s): {', '.join(a['slot'] for a in selected)}", "",
             "Interleaved by replicate, not by arm: one replicate of every arm, then the",
             "next. The sequence below is the order to run in.", "",
             "| order | slot | family | cue | cwd |", "|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['order']} | `{r['slot']}` | {r['family']} | "
                     f"{r['cue'] or '-'} | `{r['cwd']}` |")
    lines += ["", f"prompt sha `{rows[0]['prompt_sha']}`, schema sha `{rows[0]['schema_sha']}`",
              "", "Every trial: `harness_run` with this task's prompt and schema, `cwd` from",
              "the table, then `workspace.py snapshot <slot>` when the batch is done."]
    md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"{len(rows)} trials -> {out}")
    print(f"           -> {md}")
    print(f"\ntokenizer: {arms['tokenizer']['name']} {arms['tokenizer']['version']} "
          f"/ {arms['tokenizer']['encoding']}  (proxy)")
    print(f"{'order':<7}{'slot':<14}{'family':<10}{'cue':<12}{'expected path tokens':<22}")
    print("-" * 66)
    for r in rows:
        print(f"{r['order']:<7}{r['slot']:<14}{r['family']:<10}"
              f"{str(r['cue'] or '-'):<12}{r['expected_path_tokens']:<22}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
