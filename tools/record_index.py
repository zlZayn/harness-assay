#!/usr/bin/env python3
"""Record index: one run directory -> neutral condition records.

Stdlib only. **This file knows nothing about any particular study.** It names no cue,
no arm, no run id and no hypothesis. Everything it emits is a property of the dispatcher's
own records, so another study over a different task can use it unchanged.

What stays out of here on purpose, and where it goes instead:

  * which runs belong to which arm / study   -> the study's own spec file
  * what a cue means, and which words count  -> the study's own spec file
  * what "passed" means                      -> the study's criteria file
  * expectations used to verify this layer   -> the study's expectations file

Two identities, kept apart because they answer different questions:

  input_id     provenance. What the operator supplied -- harness bytes, task text,
               output schema, workspace path. Same inputs => same id. Answers
               "which spec produced this?".

  stimulus_id  treatment. What the subject actually received -- system prompt text, the
               tool table verbatim, every injected message in order, the task prompt.
               Same stimulus => same id. Answers "was this the same experiment?".

Both sources are folded in, the host's first: trials.jsonl carries
modelInput.systemPrompt.digest and modelInput.toolSchemaDigest, computed by the host over
what it actually assembled. Our own hashing uses canonical JSON (sort_keys), which is
blind to some real differences -- the order of a JSON-schema object's properties, for one.
So the host digests are authoritative and ours are the fallback and the cross-check.

A conclusion must rest on stimulus_id, not input_id: the harness file is replaceable,
the delivered context is not. Note that stimulus_id necessarily includes the workspace
path, because the host delivers it inside an injected message.

Measured quirk, 2026-11-12, host 0.2.2: the working-directory message spells the path with
doubled separators ("C:\\\\Users\\\\<name>\\\\...") while run.json holds the normal form,
so a naive `cwd in message_text` check returns False on every run. `same_path()` collapses
separator runs before comparing; use it rather than `in`.

Usage:
    python record_index.py [--root RUNS_ROOT] [--out INDEX_JSONL]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re

INDEX_SCHEMA = 1

# Host default, overridable by $DSH_HOME. Not study-specific.
DEFAULT_ROOT = pathlib.Path(os.environ.get("DSH_HOME") or pathlib.Path.home() / ".dsh") \
    / "harness-dispatcher" / "runs"


def canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def sha(obj, n: int = 16) -> str:
    text = obj if isinstance(obj, str) else canon(obj)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:n]


def same_path(a: str | None, b: str | None) -> bool:
    """Compare paths tolerating the doubled separators the host writes into messages."""
    if not a or not b:
        return False
    norm = lambda s: re.sub(r"[\\/]+", r"\\", s).lower()
    return norm(a) == norm(b)


def path_delivered(path: str | None, texts: list[str]) -> bool:
    """True when this path reached the subject inside any injected message."""
    if not path:
        return False
    target = re.sub(r"[\\/]+", r"\\", path).lower()
    return any(target in re.sub(r"[\\/]+", r"\\", t).lower() for t in texts)


# Any absolute path a message spelled out, whatever put it there. Generic on purpose: the
# host injects the working directory itself, so a study that varies paths needs to know
# which ones arrived, and cannot learn it from run.json.
ABS_PATH = re.compile(r"[A-Za-z]:[\\/][^\s\"'<>|?*\n]*")


def paths_in(texts: list[str]) -> list[str]:
    found = set()
    for t in texts:
        for hit in ABS_PATH.findall(t):
            found.add(re.sub(r"[\\/]+", r"\\", hit.rstrip(".,;:)")))
    return sorted(found)


def read_jsonl(path: pathlib.Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    return "".join(b.get("text", "") for b in (content or [])
                   if isinstance(b, dict) and b.get("type") == "text")


def split_cwd(cwd: str | None) -> tuple[str | None, str | None]:
    """Last segment / the rest. Generic: any study that varies the workspace path wants this."""
    if not cwd:
        return None, None
    p = pathlib.PureWindowsPath(cwd) if ("\\" in cwd or ":" in cwd) else pathlib.PurePosixPath(cwd)
    return p.name, str(p.parent)


def delivered(events: list[dict], trial) -> dict | None:
    """The delivered context of one trial, as digests. None when events were not recorded."""
    mine = sorted((e for e in events if e.get("trial") == trial), key=lambda x: x.get("seq", 0))
    if not mine:
        return None

    system_text = None
    messages: list[dict] = []
    texts: list[str] = []
    tools = None
    extra_headers: list[str] = []
    observed_route = None

    for e in mine:
        etype, data = e.get("type"), e.get("data") or {}
        if etype == "system/message" and system_text is None:
            system_text = text_of((data.get("message") or {}).get("content"))
        elif etype == "user/message":
            body = text_of(data.get("content"))
            texts.append(body)
            messages.append({
                "kind": (data.get("source") or {}).get("kind"),
                "chars": len(body),
                "sha": sha(body),
            })
        elif etype == "request/header":
            header = data.get("header") or {}
            if tools is None:
                tools = header.get("tools")
                cfg = header.get("config") or {}
                observed_route = {k: cfg.get(k) for k in
                                  ("provider", "model", "reasoningEffort", "maxTokens")}
            else:
                extra_headers.append(sha(header.get("tools")))

    if system_text is None and tools is None and not messages:
        return None

    names = [t.get("name") for t in (tools or [])]
    return {
        "system_prompt": {"sha": sha(system_text) if system_text is not None else None,
                          "chars": len(system_text) if system_text is not None else None},
        "tools": {"sha": sha(canon(tools)) if tools is not None else None,
                  "names": names, "count": len(names), "later_headers": extra_headers},
        "messages": {"sha": sha(canon([m["sha"] for m in messages])),
                     "kinds": [m["kind"] for m in messages],
                     "count": len(messages),
                     "each": messages},
        "observed_route": observed_route,
        "_texts": texts,   # internal only, dropped before writing
    }


def index_run(run_dir: pathlib.Path) -> list[dict]:
    run = json.loads((run_dir / "run.json").read_text(encoding="utf-8"))
    trials = read_jsonl(run_dir / "trials.jsonl")
    events = read_jsonl(run_dir / "events.jsonl")

    decl = run.get("stimulus") or {}
    task = run.get("task") or {}
    cwd = task.get("cwd")
    cwd_name, cwd_parent = split_cwd(cwd)

    inputs = {
        "harness_sha": (decl.get("harness") or {}).get("digest"),
        "harness_source": (decl.get("harness") or {}).get("source"),
        "harness_origin": (decl.get("harness") or {}).get("originPath"),
        "sealed": decl.get("sealed"),
        "max_depth": decl.get("maxDepth"),
        "faults": decl.get("faults"),
        "declared_route": decl.get("route"),
        "task_prompt_sha": sha(task.get("prompt") or ""),
        "output_schema_sha": sha(canon(task.get("outputSchema"))) if task.get("outputSchema") else None,
        "cwd": cwd,
    }
    input_id = sha(inputs)

    rows = []
    for rec in trials:
        trial_no = rec.get("trial")
        deliv = delivered(events, trial_no)
        texts = deliv.pop("_texts") if deliv else []

        # The host digests what it actually assembled; our own hashing canonicalizes
        # (sort_keys), which erases, for example, the order of a JSON-schema object's
        # properties -- a difference the model does see. So the host's verbatim digests
        # are authoritative where present, and ours are the fallback.
        mi = rec.get("modelInput") or {}
        host_sys = mi.get("systemPrompt") or {}
        host_digests = {
            "system_prompt": host_sys.get("digest"),
            "system_prompt_chars": host_sys.get("chars"),
            "tools": mi.get("toolSchemaDigest"),
            "tools_names": mi.get("tools"),
            "route": mi.get("route"),
        }

        stimulus_id = None if deliv is None else sha({
            # authoritative when the host reported it
            "host_system_prompt": host_digests["system_prompt"],
            "host_tools": host_digests["tools"],
            "host_tools_names": host_digests["tools_names"],
            # our own reading of the same things, kept so the identity survives a run
            # recorded without modelInput, and so the two sources can be compared
            "text_system_prompt": deliv["system_prompt"]["sha"],
            "text_tools": deliv["tools"]["sha"],
            "text_messages": deliv["messages"]["sha"],
        })

        host = (rec.get("host") or {}).get("values") or {}
        rows.append({
            "index_schema": INDEX_SCHEMA,
            "run_id": run_dir.name,
            "trial": trial_no,
            "task_id": rec.get("taskId"),
            "record_schema": run.get("recordSchema"),

            "input_id": input_id,
            "stimulus_id": stimulus_id,
            "stimulus_unavailable": deliv is None,

            "inputs": inputs,
            "stimulus": {**(deliv or {}), "host_digests": host_digests},

            "workspace": {
                "cwd_name": cwd_name,
                "cwd_parent": cwd_parent,
                # Did the path itself reach the subject as context? Generic and worth knowing:
                # if false, varying the workspace path changes nothing observable in the prompt.
                "cwd_injected": path_delivered(cwd, texts),
                "messages_mention_cwd": sum(1 for t in texts if path_delivered(cwd, [t])),
                # Every absolute path that arrived, including ones we never set -- the
                # operator's own working directory reaches the subject this way.
                "paths_delivered": paths_in(texts),
            },

            "observed": {
                "stop_reason": rec.get("stopReason"),
                "timed_out": rec.get("timedOut"),
                "wall_ms": rec.get("wallMs"),
                "structured": rec.get("structured"),
                "trace": rec.get("trace"),
                "steps": (host.get("sessionStats") or {}).get("steps"),
                "token_usage": host.get("tokenUsage"),
            },
        })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=pathlib.Path, default=DEFAULT_ROOT)
    ap.add_argument("--out", type=pathlib.Path, default=None)
    args = ap.parse_args()

    if not args.root.is_dir():
        print(f"not a directory: {args.root}")
        return 1

    runs = sorted(p for p in args.root.iterdir() if p.is_dir() and (p / "run.json").exists())
    rows = []
    for d in runs:
        rows.extend(index_run(d))

    out = args.out or pathlib.Path(__file__).resolve().parent.parent / "records" / "index.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(canon(r) + "\n")

    print(f"{'run':<10}{'tr':<4}{'task':<20}{'ws_name':<20}{'cwd_inj':<9}{'input_id':<18}{'stimulus_id':<18}")
    print("-" * 100)
    for r in rows:
        print(f"{r['run_id'][-8:]:<10}{r['trial']:<4}{(r['task_id'] or '-')[:19]:<20}"
              f"{(r['workspace']['cwd_name'] or '-')[:19]:<20}"
              f"{str(r['workspace']['cwd_injected']):<9}"
              f"{r['input_id']:<18}{(r['stimulus_id'] or 'UNAVAILABLE'):<18}")
    print(f"\n{len(rows)} records -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
