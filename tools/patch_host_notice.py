#!/usr/bin/env python3
"""Patch the host's working-directory notice so it stops naming where the session came from.

Why this exists
---------------
`@deepseek-ai/dsh-working-directory` injects a message whenever a session's directory
changes. The message names both ends:

    The working directory changed from "<parent cwd>" to "<child cwd>".

For a subagent, the parent cwd is the operator's session root -- copied into the child's
session header by `childSessionMeta`, then compared in `commit()`. So every delegated
subject is told the operator's directory, and no dispatcher-side option can prevent it:
the notice is emitted before the dispatcher's trial begins, and the service's only config
key is `defaultDirectory`.

Why removing it is safe
-----------------------
The subject still learns where it is: the runtime-context snapshot carries
`Current working directory: "<child cwd>"`. What the patch removes is only the *source*
side -- the operator's path, which is not part of any stimulus a study declares.

It also fixes five more sections' worth of the same problem for any harness that does not
carry a persona row setting `includeRuntimeContext: false`.

Durability
----------
This file lives inside a global npm install, so an upgrade restores the original. The
script is idempotent and refuses to guess: it matches one exact original string, writes a
backup once, and exits non-zero on anything it does not recognise. Re-run it after an
upgrade; tools/exposure_check.py is what tells you the patch is needed again.

Usage:
    python tools/patch_host_notice.py [--check] [--revert]
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

RELATIVE = pathlib.Path("@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-working-directory/lib/index.js")

ORIGINAL = (
    'text: recovered ? `The working directory ${JSON.stringify(previous)} is unavailable. '
    'The working directory is now ${JSON.stringify(directory)}.` : '
    '`The working directory changed from ${JSON.stringify(previous)} to ${JSON.stringify(directory)}.`'
)

PATCHED = (
    'text: recovered ? `The previous working directory is unavailable. '
    'The working directory is now ${JSON.stringify(directory)}.` : '
    '`The working directory is now ${JSON.stringify(directory)}.`'
)


def candidates() -> list[pathlib.Path]:
    """Every installed copy of the host we can find, so a second install is not missed."""
    out = []
    npm_root = pathlib.Path.home() / "AppData" / "Roaming" / "npm" / "node_modules"
    if (npm_root / RELATIVE.parent / "index.js").exists():
        out.append(npm_root / RELATIVE)
    try:
        global_root = subprocess.run(
            ["npm", "root", "-g"], capture_output=True, text=True, check=False
        ).stdout.strip()
        if global_root:
            p = pathlib.Path(global_root) / RELATIVE
            if p.exists() and p not in out:
                out.append(p)
    except OSError:
        pass
    return out


def state_of(path: pathlib.Path) -> str:
    text = path.read_text(encoding="utf-8")
    if PATCHED in text:
        return "patched"
    if ORIGINAL in text:
        return "original"
    return "unknown"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report state, change nothing")
    ap.add_argument("--revert", action="store_true", help="restore the backup")
    args = ap.parse_args()

    targets = candidates()
    if not targets:
        print("no installed copy of @deepseek-ai/dsh-working-directory found", file=sys.stderr)
        return 1

    worst = 0
    for path in targets:
        state = state_of(path)
        if args.check:
            print(f"{path}\n  state: {state}")
            continue

        if args.revert:
            backup = path.with_suffix(path.suffix + ".bak-assay")
            if not backup.exists():
                print(f"{path}\n  no backup at {backup.name}; nothing to revert", file=sys.stderr)
                worst = 1
                continue
            path.write_text(backup.read_text(encoding="utf-8"), encoding="utf-8")
            print(f"{path}\n  reverted from {backup.name}  (state now: {state_of(path)})")
            continue

        if state == "patched":
            print(f"{path}\n  already patched, nothing to do")
            continue
        if state == "unknown":
            print(f"{path}\n  does not match the expected original; upstream may have changed.\n"
                  f"  Refusing to edit. Update ORIGINAL/PATCHED in this script.", file=sys.stderr)
            worst = 2
            continue

        backup = path.with_suffix(path.suffix + ".bak-assay")
        if not backup.exists():
            backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        text = path.read_text(encoding="utf-8").replace(ORIGINAL, PATCHED)
        path.write_text(text, encoding="utf-8")
        print(f"{path}\n  patched  (state now: {state_of(path)})")

    if not args.check:
        print("\nRestart the host or hot-reload the module for the patch to take effect:")
        print("  dsh_hot_reload { module: '@deepseek-ai/dsh-working-directory' }")
        print("  then: python tools/exposure_check.py --lexicon study/lexicon.json")
    return worst


if __name__ == "__main__":
    sys.exit(main())
