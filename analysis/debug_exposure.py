"""What the runtime-context snapshot actually contains, per run.

The working directory is only one section of it. A session rooted here reaches the subject
through two channels, and the second -- the snapshot -- also carries policy text and, in
some configurations, the harness checkout path. Knowing which sections arrive is the
difference between declaring one constant and missing three.
"""
import json
import pathlib

ROOT = pathlib.Path.home() / ".dsh" / "harness-dispatcher" / "runs"

rows = []
for d in sorted(ROOT.iterdir()):
    if not (d / "events.jsonl").exists():
        continue
    run = json.loads((d / "run.json").read_text(encoding="utf-8"))
    events = [json.loads(l) for l in (d / "events.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    rc = [e for e in events if e["type"] == "user/message"
          and (e["data"].get("source") or {}).get("kind") == "runtime-context"]
    sections = []
    body = ""
    for e in rc:
        sections += [s.get("name") for s in ((e["data"].get("source") or {}).get("sections") or [])]
        body += "".join(b.get("text", "") for b in e["data"].get("content", []) if isinstance(b, dict))
    rows.append({
        "task": run["task"]["taskId"],
        "harness": run["stimulus"]["harness"]["digest"],
        "char": len(body),
        "sections": sections,
        "node_modules": "node_modules" in body,
        "rdir": "RDirectory" in body,
    })

print(f"{'task':<18}{'harness':<10}{'chars':<8}{'node_modules':<14}{'RDirectory':<12}sections")
print("-" * 96)
for r in rows:
    print(f"{r['task']:<18}{r['harness']:<10}{r['char']:<8}{str(r['node_modules']):<14}"
          f"{str(r['rdir']):<12}{r['sections']}")

print("\nharness -> whether the checkout path leaked")
by_harness = {}
for r in rows:
    by_harness.setdefault(r["harness"], set()).add(r["node_modules"])
for h, vals in by_harness.items():
    print(f"  {h}: {sorted(vals)}")
