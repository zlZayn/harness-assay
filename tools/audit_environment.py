#!/usr/bin/env python3
"""Environment audit for a batch in flight.

Separates three things that are easy to confuse:

  expected   the patch is applied because the window is open, and a backup exists because
             that is how the window gets closed. Not residue.
  residue    anything else: a second backup, a temp file, a file written into the
             repository, a loose file in the slot root.
  unknown    a slot whose tree no longer matches the template because a trial ran in it.
             Not a failure -- but it must be snapshotted before the window closes, or the
             record of what the subject left behind is lost.

Reads the plan, the slots, the host package and git. Writes nothing.

    set ASSAY_SLOTS=D:\\assay\\slots
    python tools/audit_environment.py --plan records/<study>/plan/<id>.jsonl
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _study  # noqa: E402  (which study -- resolved in one place, not four)

PKG = (pathlib.Path.home() / "AppData/Roaming/npm/node_modules/@deepseek-ai/dsh"
       / "node_modules/@deepseek-ai/dsh-working-directory/lib")
RUNS = pathlib.Path(os.environ.get("DSH_HOME") or pathlib.Path.home() / ".dsh") \
    / "harness-dispatcher"


def tree_sha(entries: list[dict]) -> str:
    text = "\n".join(f"{e['rel']}\t{e['sha256']}" for e in entries)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def walk(root: pathlib.Path) -> list[dict]:
    return [{"rel": p.relative_to(root).as_posix(),
             "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in sorted(root.rglob("*")) if p.is_file()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", type=pathlib.Path, required=True)
    ap.add_argument("--through", type=int, default=None,
                    help="only audit trials up to this order; later slots legitimately "
                         "do not exist yet while a batch is in flight")
    args = ap.parse_args()

    slots_root = (os.environ.get("ASSAY_SLOTS") or "").strip()
    if not slots_root:
        raise SystemExit("set ASSAY_SLOTS to the root the plan was built against")
    slots_root = pathlib.Path(slots_root)

    plan = [json.loads(l) for l in args.plan.read_text(encoding="utf-8").splitlines() if l.strip()]
    if args.through is not None:
        plan = [r for r in plan if r["order"] <= args.through]
        print(f"auditing orders 1-{args.through} of the plan "
              f"(later slots do not exist yet)\n")
    problems = 0

    print("1. HOST -- a patched module with a backup is the window, not residue")
    print("-" * 78)
    if PKG.is_dir():
        files = sorted(p.name for p in PKG.iterdir() if p.is_file())
        subs = sorted(p.name for p in PKG.iterdir() if p.is_dir())
        print(f"  package lib/ files   : {files}")
        print(f"  package lib/ subdirs : {subs}")
        known = {"index.js", "index.js.bak-assay"}
        extra = set(files) - known
        if extra:
            problems += 1
            print(f"  RESIDUE: {sorted(extra)}")
        state = subprocess.run([sys.executable, str(HERE / "tools/patch_host_notice.py"),
                                "--check"], capture_output=True, text=True, encoding="utf-8")
        for line in state.stdout.splitlines():
            if "state:" in line:
                print(f"  patch               :{line.strip()[6:]}")
    else:
        print("  package not found at the expected path")

    print()
    print("2. SLOTS -- every planned slot exists and started from one template")
    print("-" * 78)
    template = json.loads(json.dumps(walk(_study.declared("template"))))
    template_sha = tree_sha(template)
    print(f"  template            : {template_sha}  {[e['rel'] for e in template]}")
    untouched, changed, missing = 0, [], []
    for row in plan:
        d = slots_root / row["slot"]
        if not d.is_dir():
            missing.append(row["slot"])
        elif tree_sha(walk(d)) == template_sha:
            untouched += 1
        else:
            changed.append(row["slot"])
    print(f"  untouched {untouched}, changed by a run {len(changed)}, missing {len(missing)}")
    if missing:
        problems += 1
        print(f"  FAIL missing: {missing[:8]}{' ...' if len(missing) > 8 else ''}")
    if changed:
        print(f"  need a snapshot: {', '.join(sorted(changed)[:12])}"
              f"{' ...' if len(changed) > 12 else ''}")

    print()
    print("3. RESIDUE -- anything written outside a slot")
    print("-" * 78)
    git = subprocess.run(["git", "status", "--porcelain", "--ignored"], cwd=HERE,
                         capture_output=True, text=True, encoding="utf-8").stdout
    lines = [l for l in git.splitlines() if l]
    modified = [l for l in lines if not l.startswith(("??", "!!")) and l[:2].strip()]
    untracked = [l for l in lines if l.startswith("??")]
    print(f"  modified tracked files : {len(modified)}")
    for l in modified[:8]:
        print(f"      {l}")
    print("      (a trial cannot write here -- its cwd is a slot, so this is the operator)")
    print(f"  untracked files        : {len(untracked)}")
    for l in untracked[:8]:
        print(f"      {l}")
    print(f"  ignored                : {[l[3:] for l in lines if l.startswith('!!')]}")
    loose = [p.name for p in slots_root.iterdir() if p.is_file()]
    print(f"  loose files in root    : {loose or 'none'}")
    if loose:
        problems += 1

    # The property worth asserting is containment, not cleanliness: if the slot root were
    # inside the repository, a subject could write into tracked files and no diff would
    # ever attribute it. Checked as a path relationship rather than as a git status.
    try:
        inside = slots_root.resolve().is_relative_to(HERE.resolve())
    except AttributeError:
        inside = str(HERE.resolve()) in str(slots_root.resolve())
    print(f"  slot root outside repo : {'YES' if not inside else 'NO -- FAIL'}")
    if inside:
        problems += 1
        print("      a subject could write into the repository; move the slot root")

    print()
    print("4. RECORDS -- every trial of this plan left a complete directory")
    print("-" * 78)
    ours = {r["slot"] for r in plan}
    total, mine, incomplete = 0, 0, []
    if (RUNS / "runs").is_dir():
        for d in sorted((RUNS / "runs").iterdir()):
            if not (d / "run.json").exists():
                continue
            total += 1
            cwd = json.loads((d / "run.json").read_text(encoding="utf-8")).get("task", {}).get("cwd") or ""
            if pathlib.PureWindowsPath(cwd).name not in ours:
                continue
            mine += 1
            need = {"run.json", "trials.jsonl", "events.jsonl", "README.txt"}
            have = {p.name for p in d.iterdir()}
            if not need <= have or not list(d.glob("harness.*")):
                incomplete.append(d.name[-8:])
    print(f"  run dirs total         : {total}  (this plan: {mine} of {len(plan)})")
    print(f"  incomplete for plan    : {incomplete or 'none'}")
    if incomplete:
        problems += 1
    q = RUNS / "discarded"
    if q.is_dir():
        dirs = sorted(p.name[-8:] for p in q.iterdir() if p.is_dir())
        loose_q = sorted(p.name for p in q.iterdir() if p.is_file())
        print(f"  discarded run dirs     : {len(dirs)}  {dirs}")
        print(f"  discarded other files  : {loose_q or 'none'}")
        if not (q / "WHY.txt").exists():
            problems += 1
            print("  FAIL: discarded runs without a WHY.txt")

    print()
    print("RESULT:", "clean" if problems == 0 else f"{problems} problem(s)")
    return 0 if problems == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
