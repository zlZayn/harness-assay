#!/usr/bin/env python3
"""Materialize a workspace from a template, and snapshot it after a run.

Why a template rather than a copy of some workspace that happened to be used: the initial
state then becomes *constructive*. Same template bytes + the same copy step = the same
starting point, and a hash proves it. The alternative -- trusting an operator's note that
two directories "were the same" -- is exactly the thing that fails when the observation
cannot be replayed.

Two records per slot, both written with exclusive-create (like the plugin's own run
directory), so a slot cannot be quietly reused:

    records/<study>/ws/<slot>.create.json   what was there before the run
    records/<study>/ws/<slot>.after.json    what the subject left behind

Usage:
    python workspace.py create   <slot> [--root DIR] [--template DIR]
    python workspace.py snapshot <slot> [--root DIR] [--out DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _study  # noqa: E402  (which study -- resolved in one place, not four)

RECORD_DEFAULT = _study.records_dir() / "ws"


def default_root() -> pathlib.Path:
    """Where slots live. `$ASSAY_SLOTS` wins; the TEMP fallback is for a quick look only.

    TEMP is swept by the OS, and a slot is evidence: `<slot>.create.json` names its
    absolute path, so a cleared root turns every past run into a dangling reference --
    silently, since nothing re-reads the files. Set ASSAY_SLOTS to a durable directory
    for anything worth keeping.
    """
    chosen = os.environ.get("ASSAY_SLOTS", "").strip()
    if chosen:
        return pathlib.Path(chosen)
    return pathlib.Path(os.environ.get("TEMP") or "/tmp") / "harness-assay" / "ws"


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def walk(root: pathlib.Path) -> list[dict]:
    """Every regular file under root, relative and hashed, in a stable order."""
    entries = []
    for p in sorted(root.rglob("*")):
        if p.is_file():
            entries.append({
                "rel": p.relative_to(root).as_posix(),
                "sha256": file_sha(p),
                "bytes": p.stat().st_size,
            })
    return entries


def tree_sha(entries: list[dict]) -> str:
    """One number for a whole tree: proves two trees hold the same bytes."""
    text = "\n".join(f"{e['rel']}\t{e['sha256']}" for e in entries)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def write_once(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8") as fh:
            fh.write(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    except FileExistsError:
        raise SystemExit(f"refusing to overwrite {path}\n"
                         f"  a slot is one run; delete the file only to discard that run")


def create(slot: str, root: pathlib.Path, template: pathlib.Path) -> dict:
    if not template.is_dir():
        raise SystemExit(f"no template at {template}")
    dest = root / slot
    if dest.exists():
        raise SystemExit(f"slot already exists: {dest}\n"
                         f"  pick a new name, or delete it to start over")

    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(template, dest)

    entries = walk(template)
    payload = {
        "slot": slot,
        "path": str(dest),
        "template": str(template),
        "template_tree_sha": tree_sha(entries),
        "files": entries,
    }
    write_once(RECORD_DEFAULT / f"{slot}.create.json", payload)
    return payload


def snapshot(slot: str, root: pathlib.Path, out: pathlib.Path) -> dict:
    dest = root / slot
    if not dest.is_dir():
        raise SystemExit(f"no such slot: {dest}")

    entries = walk(dest)
    payload = {
        "slot": slot,
        "path": str(dest),
        "tree_sha": tree_sha(entries),
        "file_count": len(entries),
        "files": entries,
    }
    write_once(out / f"{slot}.after.json", payload)
    return payload


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create")
    c.add_argument("slot")
    c.add_argument("--root", type=pathlib.Path, default=default_root())
    c.add_argument("--template", type=pathlib.Path, default=None,
                   help="defaults to the template the study's manifest declares")

    s = sub.add_parser("snapshot")
    s.add_argument("slot")
    s.add_argument("--root", type=pathlib.Path, default=default_root())
    s.add_argument("--out", type=pathlib.Path, default=RECORD_DEFAULT)

    args = ap.parse_args()
    if args.cmd == "create":
        template = args.template or _study.declared("template")
        payload = create(args.slot, args.root, template)
        print(f"created   {payload['path']}")
        print(f"template  {payload['template_tree_sha']}  ({len(payload['files'])} files)")
    else:
        payload = snapshot(args.slot, args.root, args.out)
        print(f"snapshot  {payload['path']}")
        print(f"tree      {payload['tree_sha']}  ({payload['file_count']} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
