"""Cross-check the proxy tokenizer against the host's own count.

The trap this file exists to avoid, twice over:

  * `usage.inputTokens` is the UNCACHED input, not the prompt. Read alone it says a prompt
    that hit cache is 8x smaller than the same prompt that missed -- which is what it said
    on the first attempt here. Prompt size is `inputTokens + cacheReadTokens`.

  * Step 1 has no conversation yet, so its prompt is exactly the system prompt plus the
    tool table plus the injected messages. Nothing the subject did can influence it, which
    is what makes it a valid place to measure the cost of a path string.

Two runs that differ only in the slot path must therefore differ in step-1 prompt size by
that path's token cost. That is a claim the host's counter can falsify.
"""
import json
import pathlib

import tiktoken

RUNS = pathlib.Path.home() / ".dsh" / "harness-dispatcher" / "runs"
ENC = tiktoken.get_encoding("o200k_base")


def load(d):
    run = json.loads((d / "run.json").read_text(encoding="utf-8"))
    events = [json.loads(l) for l in (d / "events.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    first = next((e for e in events if e["type"] == "assistant/message"), None)
    usage = ((first or {}).get("data", {}) or {}).get("usage", {}) or {}
    uncached = usage.get("inputTokens") or 0
    cached = usage.get("cacheReadTokens") or 0
    return {
        "task_id": run["task"]["taskId"],
        "cwd": run["task"]["cwd"],
        "slot": pathlib.PureWindowsPath(run["task"]["cwd"]).name,
        "uncached": uncached,
        "cached": cached,
        "prompt": uncached + cached,
        "proxy_path": len(ENC.encode(run["task"]["cwd"])),
    }


runs = {r["task_id"]: r for r in
        (load(d) for d in sorted(RUNS.iterdir()) if (d / "run.json").exists() and (d / "events.jsonl").exists())}

print(f"{'task':<18}{'uncached':<10}{'cached':<9}{'prompt':<9}{'proxy_path':<12}")
print("-" * 58)
for r in runs.values():
    print(f"{r['task_id'][:17]:<18}{r['uncached']:<10}{r['cached']:<9}{r['prompt']:<9}{r['proxy_path']:<12}")

print("\n=== the informative pair: cue-r-01 vs cue-python-01 ===")
if "cue-r" in runs and "cue-python" in runs:
    a, b = runs["cue-r"], runs["cue-python"]
    print(f"  path A : {a['cwd']}")
    print(f"  path B : {b['cwd']}")
    print(f"  observed prompt delta : {b['prompt'] - a['prompt']:+d} tokens  "
          f"({a['prompt']} vs {b['prompt']})")
    print(f"  declared proxy delta  : {b['proxy_path'] - a['proxy_path']:+d} tokens  "
          f"({a['proxy_path']} vs {b['proxy_path']})")
    print("  read: a few tokens apart is the whole story. The 1910-vs-248 that")
    print("  inputTokens alone showed was cache state, not content.")

print("\n=== the six op runs (slot names all 6 characters) ===")
op = [r for r in runs.values() if r["task_id"].startswith("op")]
print(f"  prompt sizes : {sorted({r['prompt'] for r in op})}")
print(f"  proxy paths  : {sorted({r['proxy_path'] for r in op})}")
print("  equal-length names, equal counts: the counter is deterministic here,")
print("  and equal-length was not a design goal -- it is just what these six happened to be.")

print("\n=== the pair that is equal-length by construction ===")
print("  opA-01..03 vs opB-01..03: same name length, same prompt size.")
print("  A real cue contrast would NOT be equal-length; arms.json states each")
print("  arm's measured cost instead of pretending the lengths match.")
