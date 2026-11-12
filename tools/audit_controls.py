#!/usr/bin/env python3
"""Is this batch actually a controlled comparison?

Two different questions, and a run can pass one while failing the other:

  constant    the control variables must not move between trials -- harness, route,
              system prompt, tool table, message structure, task, output schema, and
              the bytes each workspace started from.
  varying     the treatment must move -- the workspace path, and the injected message
              that carries it. A trial where the path never reached the subject is not
              a cheaper trial; it is a different condition.

So this reports both. A batch where everything is constant PASSES the first check and
FAILS the second, which is exactly the failure mode of an experiment that quietly stopped
manipulating anything.

Reads:  records/index.jsonl, records/ws/<slot>.create.json, a plan file
Stdlib only. Writes nothing.

    python tools/audit_controls.py --plan records/plan/<id>.jsonl
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
INDEX = HERE / "records" / "index.jsonl"
WS = HERE / "records" / "ws"
TEMPLATE = HERE / "study" / "ws-template"


def tree_sha(entries: list[dict]) -> str:
    text = "\n".join(f"{e['rel']}\t{e['sha256']}" for e in entries)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def walk(root: pathlib.Path) -> list[dict]:
    out = []
    for p in sorted(root.rglob("*")):
        if p.is_file():
            out.append({"rel": p.relative_to(root).as_posix(),
                        "sha256": hashlib.sha256(p.read_bytes()).hexdigest()})
    return out


def get(d, *path):
    for k in path:
        if not isinstance(d, dict):
            return None
        d = d.get(k)
    return d


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", type=pathlib.Path, required=True)
    args = ap.parse_args()

    plan = [json.loads(l) for l in args.plan.read_text(encoding="utf-8").splitlines() if l.strip()]
    slots = {r["slot"]: r for r in plan}

    if not INDEX.exists():
        print(f"no index at {INDEX}\n  run: python tools/record_index.py", file=sys.stderr)
        return 1
    rows = [json.loads(l) for l in INDEX.read_text(encoding="utf-8").splitlines() if l.strip()]
    mine = [r for r in rows if (r["workspace"].get("cwd_name") or "") in slots]
    mine.sort(key=lambda r: slots[r["workspace"]["cwd_name"]]["order"])

    print(f"plan {args.plan.name}")
    print(f"{len(plan)} planned, {len(mine)} recorded so far\n")

    problems = 0

    # --- constant control variables ---------------------------------------------------
    controls = {
        "harness digest":      lambda r: get(r, "inputs", "harness_sha"),
        "sealed":              lambda r: get(r, "inputs", "sealed"),
        "max depth":           lambda r: get(r, "inputs", "max_depth"),
        "task prompt sha":     lambda r: get(r, "inputs", "task_prompt_sha"),
        "output schema sha":   lambda r: get(r, "inputs", "output_schema_sha"),
        "system prompt sha":   lambda r: get(r, "stimulus", "system_prompt", "sha"),
        "system prompt chars": lambda r: get(r, "stimulus", "system_prompt", "chars"),
        "tool table sha":      lambda r: get(r, "stimulus", "tools", "sha"),
        "tool names":          lambda r: tuple(get(r, "stimulus", "tools", "names") or ()),
        "host sys digest":     lambda r: get(r, "stimulus", "host_digests", "system_prompt"),
        "host tool digest":    lambda r: get(r, "stimulus", "host_digests", "tools"),
        "message count":       lambda r: get(r, "stimulus", "messages", "count"),
        "message kinds":       lambda r: tuple(get(r, "stimulus", "messages", "kinds") or ()),
        "route provider":      lambda r: get(r, "stimulus", "observed_route", "provider"),
        "route model":         lambda r: get(r, "stimulus", "observed_route", "model"),
        "route effort":        lambda r: get(r, "stimulus", "observed_route", "reasoningEffort"),
        "route maxTokens":     lambda r: get(r, "stimulus", "observed_route", "maxTokens"),
    }
    print("CONTROL VARIABLES -- must be identical in every trial")
    print("-" * 78)
    for name, f in controls.items():
        values = {}
        for r in mine:
            values.setdefault(str(f(r)), []).append(r["workspace"]["cwd_name"])
        if len(values) > 1:
            problems += 1
            print(f"  {name:<20}FAIL  {len(values)} distinct values")
            for v, who in sorted(values.items(), key=lambda kv: -len(kv[1])):
                print(f"      {v[:48]:<50}{len(who):>3} trial(s)")
        else:
            (v, _), = values.items()
            print(f"  {name:<20}SINGLE  {v}")

    print()
    print("INITIAL WORKSPACE -- every slot must start from the same bytes")
    print("-" * 78)
    template_now = tree_sha(walk(TEMPLATE))
    starts = {}
    for r in mine:
        slot = r["workspace"]["cwd_name"]
        p = WS / f"{slot}.create.json"
        if not p.exists():
            problems += 1
            print(f"  {slot:<15}MISSING create record -- this trial has no proven starting state")
            continue
        rec = json.loads(p.read_text(encoding="utf-8"))
        starts.setdefault(rec["template_tree_sha"], []).append(slot)
    if len(starts) == 1:
        (sha, who), = starts.items()
        state = "current" if sha == template_now else "STALE (template changed since)"
        print(f"  template at creation  SINGLE  {sha}  [{state}]")
        print(f"  template now          {template_now}")
        if sha != template_now:
            problems += 1
            print("  FAIL: slots were created from a different template than the one on disk")
    else:
        problems += 1
        for sha, who in sorted(starts.items(), key=lambda kv: -len(kv[1])):
            print(f"  template at creation  {sha}  {len(who)} slot(s)")

    print()
    print("TREATMENT -- must actually vary, or nothing was manipulated")
    print("-" * 78)
    paths = {get(r, "inputs", "cwd") for r in mine}
    print(f"  distinct workspace paths : {len(paths)}  (expected {len(mine)})")
    if len(paths) != len(mine):
        problems += 1
        print("  FAIL: two trials shared a workspace")
    injected = [r["workspace"]["cwd_injected"] for r in mine]
    print(f"  path reached the subject : {sum(1 for x in injected if x)}/{len(injected)}")
    if not all(injected):
        problems += 1
        print("  FAIL: the cue did not arrive in some trial")
    msg_sha = {get(r, "stimulus", "messages", "sha") for r in mine}
    print(f"  distinct message digests : {len(msg_sha)}  (expected {len(mine)})")
    if len(msg_sha) != len(mine):
        problems += 1
        print("  FAIL: two trials received byte-identical context, so the cue was identical")
    stimuli = {r["stimulus_id"] for r in mine}
    print(f"  distinct stimulus_id     : {len(stimuli)}  (expected {len(mine)})")

    print()
    if problems:
        print(f"{problems} problem(s) -- this is not a controlled comparison yet")
        return 2
    print("PASS: controls constant, treatment varied in every recorded trial")
    return 0


if __name__ == "__main__":
    sys.exit(main())
