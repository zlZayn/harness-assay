#!/usr/bin/env python3
"""Apply or revert a minimal host patch, inside an explicit window.

What this is for
----------------
`@deepseek-ai/dsh-working-directory` injects a notice naming both ends of a directory
change, including the parent session's cwd -- the operator's root, copied into every
delegated child by `childSessionMeta`. For a study whose treatment is a directory name,
that is a cue arriving through a channel nobody declared.

The host must not stay modified. So the patch is a **repo-owned artifact applied inside a
window**, and this script owns both ends of that window:

    python tools/patch_host_notice.py --apply --expect original    # open the window
    python tools/patch_host_notice.py --revert --expect patched    # close it

Why a window and not a plugin: the notice is emitted by a service the child composes
before the dispatcher's trial begins, and the service's only config key is
`defaultDirectory`. The alternatives -- a repo-owned cordis row that re-registers the
service -- mean subclassing a host service and depending on scope shadowing that this repo
has not verified. A one-line edit with a checked window is the smaller, more honest risk.

The reload boundary matters more than the file
----------------------------------------------
The host holds the module in memory. Writing the file changes nothing until the module is
reloaded (`dsh_hot_reload { module: '@deepseek-ai/dsh-working-directory' }`), and reverting
likewise needs a reload to take effect. So the window is bounded by reloads, not by writes:
a revert without a reload leaves the running host patched.

`--expect` is what makes that checkable in a script: it exits non-zero when the file is not
in the requested state, so a batch can refuse to start, or refuse to claim it cleaned up.

Nothing here guesses. It matches one exact original string, keeps one backup, and refuses
to edit a file it does not recognise -- an upstream rewrite should stop the run, not be
silently overwritten.

Usage:
    python tools/patch_host_notice.py --check
    python tools/patch_host_notice.py --apply  [--expect original]
    python tools/patch_host_notice.py --revert [--expect patched]
"""

from __future__ import annotations

import argparse
import hashlib
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

# Known bytes, so "is the host clean?" is answered by a hash rather than by a substring.
# Measured on @deepseek-ai/dsh-working-directory 0.2.2-rc.1, 2026-11-12. A new upstream
# version will not match these, which is exactly when a human should look.
KNOWN_SHA256 = {
    "76b2f53517bc3312084bc062ce8bbc4111f3b723d96da080157046c2b6d4766a": "original",
    "a1599cf6dfe9b2dbb1d62f83dde6f725ecbc969c44e3142367e8a68eea51ba13": "patched",
}

BACKUP_SUFFIX = ".bak-assay"

RELOAD_HINT = (
    "the file is not the host: reload the module for this to take effect\n"
    "  dsh_hot_reload { module: '@deepseek-ai/dsh-working-directory' }\n"
    "  then: python tools/exposure_check.py --lexicon study/lexicon.json"
)


def candidates() -> list[pathlib.Path]:
    """Every installed copy of the host we can find, so a second install is not missed."""
    found: list[pathlib.Path] = []
    npm_root = pathlib.Path.home() / "AppData" / "Roaming" / "npm" / "node_modules"
    if (npm_root / RELATIVE).exists():
        found.append(npm_root / RELATIVE)
    try:
        global_root = subprocess.run(
            ["npm", "root", "-g"], capture_output=True, text=True, check=False
        ).stdout.strip()
        if global_root:
            extra = pathlib.Path(global_root) / RELATIVE
            if extra.exists() and extra not in found:
                found.append(extra)
    except OSError:
        pass
    return found


def state_of(path: pathlib.Path) -> str:
    """Hash first: a substring can be right while 171 stray CRLF bytes are not."""
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest in KNOWN_SHA256:
        return KNOWN_SHA256[digest]
    text = path.read_bytes()
    if PATCHED.encode("utf-8") in text:
        return "patched-unrecognised"
    if ORIGINAL.encode("utf-8") in text:
        return "original-unrecognised"
    return "unknown"


def clean(path: pathlib.Path) -> bool:
    """True when the file is byte-identical to the stock host."""
    return state_of(path) == "original"


def differs_from_backup(path: pathlib.Path, backup: pathlib.Path) -> bool:
    """Bytes, not content.

    The first version of this script skipped the revert when the file merely *contained*
    the original pattern, and the file was 171 bytes larger with CRLF endings everywhere
    else. Content state said "original", the hash said otherwise. Reverting is a byte
    operation, so it is decided by bytes.
    """
    return path.read_bytes() != backup.read_bytes()


def edit_bytes(path: pathlib.Path, old: str, new: str) -> None:
    """Replace one exact byte sequence, preserving every other byte.

    Deliberately binary. A text-mode read/write pair normalises line endings, which turned
    a 7030-byte LF file into a 7201-byte CRLF file on the first attempt here: the content
    looked right and the hash did not. Reverting a host patch has to be byte-exact, or the
    "clean" state is just a second mutation nobody accounted for.
    """
    data = path.read_bytes()
    needle = old.encode("utf-8")
    if needle not in data:
        raise ValueError(f"pattern not found in {path}")
    path.write_bytes(data.replace(needle, new.encode("utf-8")))


def main() -> int:
    ap = argparse.ArgumentParser()
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true", help="report state, change nothing")
    group.add_argument("--apply", action="store_true", help="open the window")
    group.add_argument("--revert", action="store_true", help="close the window")
    ap.add_argument("--expect", choices=["original", "patched"],
                    help="exit non-zero unless every copy is in this state")
    args = ap.parse_args()

    targets = candidates()
    if not targets:
        print("no installed copy of @deepseek-ai/dsh-working-directory found", file=sys.stderr)
        return 1

    status = 0
    for path in targets:
        backup = path.with_suffix(path.suffix + BACKUP_SUFFIX)
        state = state_of(path)

        if args.check:
            print(f"{path}\n  state: {state}  backup: {'present' if backup.exists() else 'none'}")
            continue

        if args.apply:
            if state == "patched":
                print(f"{path}\n  already patched")
            elif state in ("unknown", "patched-unrecognised"):
                print(f"{path}\n  state is {state}; upstream may have changed.\n"
                      f"  Refusing to edit. Re-measure and update ORIGINAL/PATCHED/KNOWN_SHA256.",
                      file=sys.stderr)
                status = 2
            else:
                if not backup.exists():
                    backup.write_bytes(path.read_bytes())
                edit_bytes(path, ORIGINAL, PATCHED)
                print(f"{path}\n  patched")

        if args.revert:
            if not backup.exists():
                # No backup: the only honest revert is a byte-identical restore, which a
                # hash can confirm but this script cannot perform.
                if clean(path):
                    print(f"{path}\n  already byte-identical to the stock host")
                else:
                    print(f"{path}\n  state {state} but no backup at {backup.name}.\n"
                          f"  Cannot restore byte-for-byte; reinstall the package.", file=sys.stderr)
                    status = 2
            elif not differs_from_backup(path, backup):
                print(f"{path}\n  already identical to the backup, nothing to revert")
            else:
                path.write_bytes(backup.read_bytes())
                print(f"{path}\n  reverted byte-for-byte from {backup.name}")

            # A backup left behind is residue too. Once the file hashes to a known stock
            # state the backup cannot add anything, so closing the window removes it and
            # the host directory goes back to having exactly the files npm installed.
            if clean(path) and backup.exists():
                backup.unlink()
                print("  backup removed: the host directory holds only what npm installed")

        final = state_of(path)
        if args.expect and final != args.expect:
            print(f"  EXPECTED {args.expect}, found {final}", file=sys.stderr)
            status = 3

    if args.apply:
        print(f"\n{RELOAD_HINT}")
    elif args.revert:
        print("\nreload the module again so the running host drops the patch:\n"
              "  dsh_hot_reload { module: '@deepseek-ai/dsh-working-directory' }")
    return status


if __name__ == "__main__":
    sys.exit(main())
