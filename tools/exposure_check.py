#!/usr/bin/env python3
"""Guard against a cue that arrives without anyone choosing it.

The subject is told, in an injected message, both where it now is and where it came from:

    The working directory changed from "<operator path>" to "<slot path>".

The operator path is the session's origin directory -- not the live cwd, which is why a
`cd` does not move it. So a session opened in a directory whose name contains a language
token makes *every* trial of that session a cued trial, and the record does not mark it as
a variable at all.

This script reads the delivered paths back out of each run and says whether anything
outside the slot path carries a token from the study's lexicon. Run it before a batch:
a contaminated session is cheaper to abandon than to explain.

The slot path is reported separately and never fails the check: a slot path carrying a cue
is the experiment. What must not happen is a cue arriving through the operator path, which
nobody chose.

Stdlib only.

Usage:
    python tools/exposure_check.py --lexicon studies/<id>/lexicon.json [--root RUNS_ROOT]
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys

DEFAULT_ROOT = pathlib.Path(os.environ.get("DSH_HOME") or pathlib.Path.home() / ".dsh") \
    / "harness-dispatcher" / "runs"

ABS_PATH = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s\"'<>|?*\n]*")
FROM = re.compile(r'changed from\s+"([^"]+)"\s+to\s+"([^"]+)"', re.I)


def segments(path: str):
    return [s for s in re.split(r"[\\/]+", path) if s]


def words(segment: str) -> list[str]:
    """Split a path segment into words.

    Three boundaries: a non-alphanumeric character, a lower/digit followed by upper, and a
    upper followed by upper-then-lower. The last one is what makes 'RDirectory' read as
    ['R', 'Directory'] -- the way a human reads it. Without it the guard passes a path that
    is obviously an R cue, which is worse than having no guard.
    """
    out, cur = [], ""
    for i, ch in enumerate(segment):
        if not ch.isalnum():
            if cur:
                out.append(cur)
            cur = ""
            continue
        if cur:
            prev = segment[i - 1]
            starts_word = (
                (ch.isupper() and prev.islower())
                or (ch.isupper() and prev.isupper() and ch.isupper()
                    and i + 1 < len(segment) and segment[i + 1].islower())
            )
            if starts_word:
                out.append(cur)
                cur = ""
        cur += ch
    if cur:
        out.append(cur)
    return out


def hits(path: str, tokens) -> list[dict]:
    found = []
    for seg in segments(path):
        low = seg.lower()
        for tok in tokens:
            text = tok["text"].lower()
            if tok.get("match") == "substring":
                if text in low:
                    found.append({"token": tok["text"], "segment": seg})
            else:
                if text in (w.lower() for w in words(seg)):
                    found.append({"token": tok["text"], "segment": seg})
    return found


def scan_run(run_dir: pathlib.Path) -> dict | None:
    run_json = run_dir / "run.json"
    events_path = run_dir / "events.jsonl"
    if not run_json.exists() or not events_path.exists():
        return None

    run = json.loads(run_json.read_text(encoding="utf-8"))
    slot = run.get("task", {}).get("cwd")
    task_id = run.get("task", {}).get("taskId")

    parents, others = set(), set()
    sections: list[str] = []
    for line in events_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        ev = json.loads(line)
        if ev.get("type") != "user/message":
            continue
        source = ev.get("data", {}).get("source") or {}
        sections += [s.get("name") for s in (source.get("sections") or [])]
        body = "".join(b.get("text", "") for b in ev.get("data", {}).get("content", [])
                       if isinstance(b, dict))
        m = FROM.search(body)
        if m:
            parents.add(m.group(1).replace("\\\\", "\\"))
        for p in ABS_PATH.findall(body):
            others.add(p.rstrip(".,;:)").replace("\\\\", "\\"))

    return {
        "task_id": task_id,
        "run_id": run_dir.name,
        "started_at": run.get("startedAt"),
        "slot": slot,
        "harness": run.get("stimulus", {}).get("harness", {}).get("digest"),
        "parents": sorted(parents),
        "sections": sections,
        # paths named in the context that are neither the slot nor its parent
        "others": sorted(p for p in others if p != slot and p not in parents),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lexicon", type=pathlib.Path, required=True)
    ap.add_argument("--root", type=pathlib.Path, default=DEFAULT_ROOT)
    args = ap.parse_args()

    lexicon = json.loads(args.lexicon.read_text(encoding="utf-8"))
    tokens = lexicon["tokens"]

    runs = [r for r in (scan_run(d) for d in sorted(args.root.iterdir()) if d.is_dir()) if r]
    if not runs:
        print(f"no runs under {args.root}")
        return 1

    # Newest first: the guard answers "is this environment usable now", and the most recent
    # run is the evidence for that. Older runs are history -- a run recorded before a fix is
    # a true record of the old behaviour and must not keep the gate red forever.
    runs.sort(key=lambda r: r.get("started_at") or 0, reverse=True)

    violations = 0
    print(f"{'run':<10}{'task':<18}{'source path named by the notice':<36}cue tokens in it")
    print("-" * 92)
    for r in runs:
        sources = r["parents"] or ["(notice named no source path)"]
        for p in sources:
            h = hits(p, tokens) if r["parents"] else []
            flag = ", ".join(f"{x['token']}@{x['segment']}" for x in h)
            if h:
                violations += 1
            print(f"{r['run_id'][-8:]:<10}{(r['task_id'] or '')[:17]:<18}{p[:35]:<36}{flag or '-'}")

    print()
    slot_hits = 0
    for r in runs:
        if not r["slot"]:
            continue
        h = hits(r["slot"], tokens)
        if h:
            slot_hits += 1
    print(f"slot paths carrying a lexicon token: {slot_hits}/{len(runs)} "
          f"(expected -- that is the treatment, not contamination)")

    distinct = sorted({p for r in runs for p in r["parents"]})
    print(f"distinct operator paths across {len(runs)} runs: {len(distinct)}")
    for p in distinct:
        print(f"  {p}")

    stray = sorted({p for r in runs for p in r["others"]})
    if stray:
        print("\nother absolute paths named in the context:")
        for p in stray:
            print(f"  {p}")

    # A harness whose persona row does not set includeRuntimeContext:false gets every
    # optional snapshot section, not just the working directory. That is a control-variable
    # issue rather than a cue issue, so it warns instead of failing -- but it must be seen,
    # because it silently widens what the subject is told.
    print("\nruntime-context sections per harness:")
    by_harness: dict[str, set] = {}
    for r in runs:
        by_harness.setdefault(r.get("harness") or "?", set()).add(tuple(r["sections"]))
    wide = False
    for harness, variants in by_harness.items():
        for sections in variants:
            extra = [s for s in sections if s and s != "working-directory:current"]
            if extra:
                wide = True
            print(f"  {harness}: {len(sections)} section(s)"
                  f"{'  <- optional contexts NOT suppressed: ' + ', '.join(extra) if extra else ''}")
    if wide:
        print("  WARN: a harness without a persona row that sets includeRuntimeContext:false")
        print("        delivers extra sections, and the harness checkout path with them.")

    print()
    newest = runs[0]
    newest_hits = hits(newest["parents"][0], tokens) if newest["parents"] else []
    historical = violations - len(newest_hits)

    if historical:
        print(f"note: {historical} older run(s) still record a contaminated source path.")
        print("      They are true records of the behaviour before the fix and stay as they were.")

    if newest_hits:
        flagged = ", ".join(f"{h['token']}@{h['segment']}" for h in newest_hits)
        print(f"FAIL: the most recent run ({newest['run_id'][-8:]}) names {flagged}")
        print("      in its working-directory notice.")
        print("  This environment is not usable for a cue study: the subject is told the")
        print("  operator's path. Run tools/patch_host_notice.py, or start the run from a")
        print("  session rooted at a neutral path.")
        return 2

    print("PASS: the most recent run's notice names no source path, so no cue reaches the")
    print("      subject through the operator path.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
