"""Declare the cue arms by measured token cost, with the tokenizer named and pinned.

Run once, paste-free: this writes study/cue-arms.json, which is the declaration of record.

    uv run --with tiktoken==0.12.0 python analysis/cue_tokens.py

Why a proxy tokenizer is honest here and a "same length" rule is not: the subject runs on
DeepSeek's own tokenizer, which is not published. What matters for the design is the *cost*
the cue adds to the prompt, and a named, pinned tokenizer measures that consistently. What
must not happen is claiming two cues are equivalent because their character counts match --
"python" and "hedgerow" are both 7 characters and nothing like the same prompt.

The cue is delivered inside an absolute path, so the unit counted is the whole slot path,
not the bare word. Two costs are reported:

  slot_tokens   the path as the subject sees it
  delta_vs_base cost above the shortest neutral baseline

`r` is declared on its own, not as a level of the python/tidyverse factor: a single letter
in a path is not the same kind of signal as an explicit language or package name, and
treating them as one factor would average two different hypotheses.
"""
import json
import os
import pathlib
import sys

import tiktoken

ENCODING = "o200k_base"
TOKENIZER = "tiktoken"
VERSION = tiktoken.__version__
ROOT = pathlib.Path(__file__).resolve().parent.parent

# Where slots will live. Never a literal: the token cost depends on this prefix, so the
# declaration records which root it was counted for. Set ASSAY_SLOTS or --slots.
BASE = (os.environ.get("ASSAY_SLOTS") or "").strip()
if len(sys.argv) > 1 and sys.argv[1] == "--slots" and len(sys.argv) > 2:
    BASE = sys.argv[2]
if not BASE:
    raise SystemExit(
        "slot root unknown: set ASSAY_SLOTS, or pass --slots <path>\n"
        "  the token cost of an arm depends on this prefix, so it has to be stated, not assumed"
    )

# candidate slot names; `role` says what each one is supposed to be able to show
CANDIDATES = [
    ("r-01",       "r",         "letter",   "single letter; ambiguous between the language and a letter"),
    ("q-01",       None,        "letter",   "neutral letter control at the same name length"),
    ("python-01",  "python",    "lang",     "explicit language name"),
    ("cobden-01",  None,        "lang",     "neutral, similar token cost to python"),
    ("tidyverse-01", "tidyverse", "lang",   "explicit package name; also a language pointer"),
    ("hedgerow-01", None,       "lang",     "neutral, similar token cost to tidyverse"),
    # One word per condition is n=1 wording: the result would be about that string, not
    # about the category. These give each condition three wordings so the wording can be
    # treated as a block/random effect (study/DESIGN.md section 5).
    ("dplyr-01",    "dplyr",    "r-eco",    "R package name"),
    ("ggplot-01",   "ggplot",   "r-eco",    "R package name"),
    ("tidyr-01",    "tidyr",    "r-eco",    "R package name"),
    ("marlow-01",   None,       "placebo",  "neutral, similar length to dplyr"),
    ("fenwick-01",  None,       "placebo",  "neutral, similar length to ggplot"),
    ("orwell-01",   None,       "placebo",  "neutral, similar length to tidyr"),
]


def main() -> int:
    enc = tiktoken.get_encoding(ENCODING)

    def count(s: str) -> int:
        return len(enc.encode(s))

    base_path = f"{BASE}\\{CANDIDATES[0][0]}"
    rows = []
    for slot, cue, family, note in CANDIDATES:
        path = f"{BASE}\\{slot}"
        rows.append({
            "slot": slot,
            "cue": cue,
            "family": family,
            "note": note,
            "path": path,
            "chars": len(path),
            "tokens": count(path),
            "cue_tokens": count(cue) if cue else 0,
        })

    shortest = min(r["tokens"] for r in rows)
    for r in rows:
        r["delta_vs_shortest"] = r["tokens"] - shortest
        # The absolute path is what the model sees; it is derived here, not stored, so the
        # declaration stays portable. Re-run this file if the slot root moves.
        del r["path"]

    rows.sort(key=lambda r: (r["family"], r["tokens"]))

    payload = {
        "tokenizer": {"name": TOKENIZER, "version": VERSION, "encoding": ENCODING,
                      "_caveat": "proxy. The subject runs on DeepSeek's tokenizer, which is not "
                                 "published. Absolute counts are approximate; differences between "
                                 "arms measured with this one tool are consistent."},
        "unit": "the full slot path as it reaches the subject, prefix + '/' + slot",
        "slots_root": BASE,
        "_root_matters": "tokens are counted with this prefix; move the root and re-run",
        "baseline": {"shortest_slot": min(rows, key=lambda r: r["tokens"])["slot"],
                     "tokens": shortest},
        "_calibration": {
            "_what": "Where the proxy and the host disagree, measured on 2026-11-12.",
            "pair": "cue-r-01 vs cue-python-01, same harness, same system prompt",
            "host_step1_prompt_delta": 2,
            "proxy_delta": 0,
            "_read": "The proxy saw '-r-01' and '-python-01' as the same cost (both four "
                     "tokens); the subject's own tokenizer charged two more for 'python'. "
                     "So the proxy is a planning instrument, not a measurement. Where a run "
                     "exists, use the host's step-1 prompt size (inputTokens + cacheReadTokens) "
                     "instead -- and note that inputTokens alone is uncached input, which "
                     "reads about 8x small on a cache hit.",
        },
        "arms": rows,
    }

    out = ROOT / "study" / "cue-arms.json"
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"tokenizer {TOKENIZER} {VERSION} / {ENCODING}   (proxy for the subject's own)\n")
    print(f"{'family':<14}{'slot':<14}{'cue':<11}{'chars':<7}{'tokens':<8}{'delta':<7}")
    print("-" * 62)
    for r in rows:
        print(f"{r['family']:<14}{r['slot']:<14}{str(r['cue'] or '-'):<11}"
              f"{r['chars']:<7}{r['tokens']:<8}{r['delta_vs_shortest']:<7}")
    print(f"\n-> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
