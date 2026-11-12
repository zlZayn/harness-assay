"""Exposure report: does the operator's own directory reach the subject, and did the
intended manipulation actually happen?

Deliberately reports the *first* question before the second. A comparison of outcomes only
means something once the delivered context has been shown to differ.
"""
import json
import pathlib
import re
import statistics

ROOT = pathlib.Path(__file__).resolve().parent.parent
rows = [json.loads(l) for l in (ROOT / "records" / "index.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
runs = sorted((r for r in rows if (r.get("task_id") or "").startswith("op")), key=lambda r: r["task_id"])

FROM = re.compile(r'changed from\s+"([^"]+)"\s+to\s+"([^"]+)"', re.I)


def parent_of(run):
    """The 'from' path in the working-directory notice, if the host injected one."""
    texts = [t for t in (run["stimulus"] or {}).get("messages", {}).get("each", [])]
    # index.jsonl keeps per-message digests, not text; fall back to the run directory
    run_dir = pathlib.Path.home() / ".dsh" / "harness-dispatcher" / "runs" / run["run_id"]
    events = run_dir / "events.jsonl"
    if not events.exists():
        return None
    for line in events.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        ev = json.loads(line)
        if ev.get("type") != "user/message" or ev.get("trial") != run["trial"]:
            continue
        body = "".join(b.get("text", "") for b in ev["data"].get("content", []) if isinstance(b, dict))
        m = FROM.search(body)
        if m:
            return m.group(1).replace("\\\\", "\\")
    return None


def outcome(run):
    o = run["observed"]
    tu = o.get("token_usage") or {}
    return {
        "calls": (o.get("trace") or {}).get("toolCalls"),
        "steps": o.get("steps"),
        "wall_ms": o.get("wall_ms"),
        "in_total": (tu.get("uncachedInputTokens") or 0) + (tu.get("cacheReadTokens") or 0),
        "out_tokens": tu.get("outputTokens"),
        "answer": json.dumps(o.get("structured"), ensure_ascii=False),
    }


print("=" * 78)
print("1. WHAT ACTUALLY REACHED THE SUBJECT")
print("=" * 78)
print(f"{'run':<8}{'slot':<9}{'parent path injected'}")
print("-" * 78)
parents = {}
for r in runs:
    p = parent_of(r)
    parents[r["task_id"]] = p
    print(f"{r['task_id']:<8}{r['workspace']['cwd_name']:<9}{p}")

distinct = sorted({p for p in parents.values()})
print()
print(f"distinct parent paths across {len(runs)} runs: {len(distinct)}")
for p in distinct:
    who = [k for k, v in parents.items() if v == p]
    print(f"  {p}   <- {', '.join(who)}")

print()
print("=" * 78)
print("2. DID THE MANIPULATION HAPPEN?")
print("=" * 78)
arms = {"opA": [r for r in runs if r["task_id"].startswith("opA")],
        "opB": [r for r in runs if r["task_id"].startswith("opB")]}
a_parent = {parents[r["task_id"]] for r in arms["opA"]}
b_parent = {parents[r["task_id"]] for r in arms["opB"]}
if a_parent == b_parent:
    print("NO. Both arms received the same parent path, so this is one condition, not two.")
    print("    The operator cwd is NOT the live working directory; changing it did not")
    print("    change what the child was told. Any difference below is sampling noise.")
else:
    print(f"YES. opA parent={a_parent}  opB parent={b_parent}")

print()
print("=" * 78)
print("3. OUTCOMES, and what a naive comparison would have claimed")
print("=" * 78)
print(f"{'arm':<6}{'run':<8}{'calls':<7}{'steps':<7}{'wall_ms':<9}{'in_total':<10}{'out_tok':<9}answer")
print("-" * 78)
for arm, group in arms.items():
    for r in group:
        o = outcome(r)
        print(f"{arm:<6}{r['task_id']:<8}{str(o['calls']):<7}{str(o['steps']):<7}"
              f"{str(o['wall_ms']):<9}{str(o['in_total']):<10}{str(o['out_tokens']):<9}{o['answer']}")

print()
for arm, group in arms.items():
    outs = [outcome(r) for r in group]
    for field in ("calls", "wall_ms", "in_total", "out_tokens"):
        vals = [o[field] for o in outs if o[field] is not None]
        if vals:
            print(f"  {arm} {field:<11} mean={statistics.mean(vals):>9.1f}  "
                  f"spread={min(vals)}-{max(vals)}  (n={len(vals)})")
    print()

a_wall = statistics.mean([o["wall_ms"] for o in (outcome(r) for r in arms["opA"])])
b_wall = statistics.mean([o["wall_ms"] for o in (outcome(r) for r in arms["opB"])])
print(f"naive verdict: opA is {(a_wall / b_wall - 1) * 100:+.1f}% slower than opB.")
print("that verdict is void: the two arms were never told anything different.")
