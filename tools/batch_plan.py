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
SLOTS = pathlib.Path(os.environ.get("ASSAY_SLOTS") or "D:/assay/slots")


def canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def sha(obj, n: int = 12) -> str:
    text = obj if isinstance(obj, str) else canon(obj)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:n]


def build(arms: dict, task: dict, k: int, plan_id: str) -> list[dict]:
    """One row per trial. The slot name carries the cue, so the replicate is a suffix."""
    rows = []
    for arm in arms["arms"]:
        for rep in range(1, k + 1):
            slot = f"{arm['slot'].rsplit('-', 1)[0]}-{rep:02d}"
            rows.append({
                "plan_id": plan_id,
                "slot": slot,
                "rep": rep,
                "family": arm["family"],
                "cue": arm["cue"],
                "expected_path_tokens": arm["tokens"],
                "expected_delta": arm["delta_vs_shortest"],
                "cwd": str(SLOTS / slot),
                "task_id": task["id"],
                "prompt_sha": sha(task["prompt"]),
                "schema_sha": sha(task["schema"]),
            })
    return rows


def verify(rows: list[dict], task: dict, expect_complete: bool) -> int:
    """Is the board in the state the plan assumes?

    Four states, and only three of them are problems:

      done       exactly one recorded run -- fine
      pending    no slot, no run            -- normal before a batch
      OCCUPIED   a slot exists but no run   -- a leftover directory; create would refuse it
      DUPLICATE  one slot, several runs     -- two trials stacked into one history

    `--expect-complete` turns pending into a problem too, which is the post-batch reading.
    """
    by_slot = {r["slot"]: r for r in rows}
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
    print(f"{'slot':<14}{'slot on disk':<14}{'runs':<6}state")
    print("-" * 60)
    for slot in sorted(by_slot):
        exists = (SLOTS / slot).is_dir()
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
        print(f"{slot:<14}{str(exists):<14}{len(runs):<6}{state}")

    unexpected = sorted(set(recorded) - set(by_slot))
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

    plan_id = f"{args.task}-k{args.k}-{sha(arms['arms'] + [task['prompt'], task['schema']])}"
    rows = build(arms, task, args.k, plan_id)

    if args.verify:
        print(f"plan {plan_id}\n")
        return verify(rows, task, args.expect_complete)

    PLAN_DIR.mkdir(parents=True, exist_ok=True)
    out = PLAN_DIR / f"{plan_id}.jsonl"
    with out.open("w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(canon(r) + "\n")

    md = PLAN_DIR / f"{plan_id}.md"
    lines = [f"# plan {plan_id}", "",
             f"task `{task['id']}` - {len(rows)} trials, k={args.k}", "",
             "| slot | family | cue | cwd |", "|---|---|---|---|"]
    for r in rows:
        lines.append(f"| `{r['slot']}` | {r['family']} | {r['cue'] or '-'} | `{r['cwd']}` |")
    lines += ["", f"prompt sha `{rows[0]['prompt_sha']}`, schema sha `{rows[0]['schema_sha']}`",
              "", "Every trial: `harness_run` with this task's prompt and schema, `cwd` from the table,",
              "then `workspace.py snapshot <slot>` when the batch is done."]
    md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"{len(rows)} trials -> {out}")
    print(f"           -> {md}")
    print(f"\ntokenizer: {arms['tokenizer']['name']} {arms['tokenizer']['version']} "
          f"/ {arms['tokenizer']['encoding']}  (proxy)")
    print(f"{'slot':<14}{'family':<10}{'cue':<12}{'expected path tokens':<22}")
    print("-" * 60)
    for r in rows:
        print(f"{r['slot']:<14}{r['family']:<10}{str(r['cue'] or '-'):<12}"
              f"{r['expected_path_tokens']:<22}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
