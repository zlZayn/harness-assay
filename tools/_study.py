"""Which study a tool is talking about -- resolved once, here, and nowhere else.

Why this module exists
----------------------
The record layer must not name a study. Its scripts have to point at *a* study's arm
table, tasks and workspace template, and the naive way to do that is to write the path in
each script -- at which point adding a second study means editing five files and getting
one of them wrong silently.

So the name is data. `study.json` at the repo root says which study is current, and
`$ASSAY_STUDY` overrides it for a one-off. Each study declares the paths this layer needs
in its own `study.json`, under keys this module knows and that no study owns.

    repo/
      study.json                    {"current": "<study-id>"}
      studies/<study-id>/
        study.json                  {"arms": ..., "tasks": ..., "template": ...}
        ...

Stdlib only, like the rest of the record layer.
"""

from __future__ import annotations

import json
import os
import pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent


def study_id() -> str:
    """The current study's directory name, from `$ASSAY_STUDY` or the root pointer.

    Never guessed. A default baked in here would be a study name inside the layer that is
    supposed to know none, and it would pick the wrong study the day a second one exists.
    """
    chosen = (os.environ.get("ASSAY_STUDY") or "").strip()
    if chosen:
        return chosen
    pointer = REPO / "study.json"
    if not pointer.is_file():
        raise SystemExit(
            f"no study pointer at {pointer}\n"
            "  set $ASSAY_STUDY=<id>, or write {\"current\": \"<id>\"} there"
        )
    return json.loads(pointer.read_text(encoding="utf-8"))["current"]


def study_dir() -> pathlib.Path:
    path = REPO / "studies" / study_id()
    if not path.is_dir():
        raise SystemExit(f"no study at {path} (from $ASSAY_STUDY or study.json)")
    return path


def manifest() -> dict:
    path = study_dir() / "study.json"
    if not path.is_file():
        raise SystemExit(f"study {study_id()} has no study.json at {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def declared(key: str) -> pathlib.Path:
    """A path the study declares for itself. Unknown key => loud failure, not a guess."""
    got = manifest().get(key)
    if not isinstance(got, str) or not got:
        raise SystemExit(
            f"study {study_id()}'s study.json declares no '{key}'\n"
            f"  keys present: {sorted(manifest())}"
        )
    return study_dir() / got


def records_dir() -> pathlib.Path:
    """Where this study's own derived artifacts go.

    Study-scoped on purpose: the instrument-level index and its tidy tables cover every
    run on the machine and live at `records/`; a plan, a judgement or a figure belongs to
    one study and must not be overwritten by the next one.
    """
    return REPO / "records" / study_id()
