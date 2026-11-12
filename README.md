# harness-assay

Measuring what an agent **harness** does to an agent — not what a model can do.

A harness is the row list a session runs with: the system prompt, the tool table, the
injected context. Change one of those and behaviour moves. The point of this repo is to
make that movement **believable after the fact**: the observation happens once, the
judgement criteria will drift, and later readers only have what was written down.

## The split that makes it work

Records are produced by
[`dsh-harness-dispatcher`](https://github.com/dsh-plugin-lab/dsh-harness-dispatcher) and
land in `$DSH_HOME/harness-dispatcher/runs/<runId>/`. That layer is deliberately left
alone. What lives here is the **overlay**: reading those records into something
computable, and making sure a conclusion can be traced back to the conditions that
produced it.

```
records/<runId>/          the dispatcher's own output — never edited, never duplicated
        run.json          identity of the run + the task + the surface that actually mounted
        trials.jsonl      one line per trial: condition, outcome, host projections, answer
        events.jsonl      the subject's committed session events, verbatim — the evidence layer
        harness.*         a verbatim copy of the harness under test
```

## Two identities, kept apart

| id | answers | built from |
|---|---|---|
| `input_id` | which spec produced this? | harness bytes, task text, output schema, workspace path |
| `stimulus_id` | was this the same experiment? | system prompt text, tool table verbatim, every injected message, task prompt |

A conclusion must rest on `stimulus_id`. The harness file is replaceable; the delivered
context is not. Two files that differ only in row order mount to the same tool table, so
they share a `stimulus_id` and differ in `input_id` — which is exactly the distinction
that lets a condition be swapped without silently rewriting the meaning of past results.

The dispatcher's own `stimulus.fingerprint` does **not** include the workspace path, so
two runs differing only in `task.cwd` share a fingerprint. `stimulus_id` closes that hole.

## Layout

```
tools/            generic record layer — names no study, no arm, no hypothesis
  record_index.py   run directory -> neutral condition records (stdlib only)
  verify_index.py   check the index against a study's declared expectations
  workspace.py      materialize a workspace from a template; snapshot it afterwards
  grade.py          judge observations against a criteria file
  exposure_check.py does the delivered context carry a cue nobody declared?
  patch_host_notice.py  applies/reverts the host notice patch inside a checked window
  batch_plan.py     arm table + task -> a checked list of trials to run
analysis/         R, over the index only — never over a run directory
  index_tables.R    two tidy tables: conditions (per arm), observations (per trial)
  tolerance_notes.R where the numeric tolerance comes from
  cue_tokens.py     per-arm token cost, with the tokenizer named and pinned
  exposure_report.py  did the intended manipulation actually happen?
study/            one study's own declarations
  expectations.json  pairs whose relationship is already known, so the index self-checks
  criteria/v1.json   truth, tolerance, and the known limits of that tolerance
  cue-arms.json      arms declared by measured token cost, not by character length
  lexicon.json       tokens that would themselves be a cue if a path carried them
  tasks/<id>.json    the prompt and schema — the single source of both
  ws-template/       the only source of truth for what a workspace starts as
docs/notes/       what was measured and what failed
records/          generated (gitignored)
```

## A batch has a plan before it has trials

`tools/batch_plan.py` turns the arm table plus one task into a list of trials, and can be
asked to check the board against it. Nothing in it calls a model.

```bash
python tools/batch_plan.py --task wells-meansd --k 5            # write the plan
python tools/batch_plan.py --task wells-meansd --k 5 --verify   # pre-flight
python tools/batch_plan.py --task wells-meansd --k 5 --verify --expect-complete   # post-batch
```

The pre-flight separates four states and treats only three as problems: `done`, `pending`
(normal before a batch), `OCCUPIED` (a leftover slot `create` would refuse) and
`DUPLICATE` (two runs stacked into one history). It also asserts the prompt and schema
hashes are single-valued across the plan, because a schema typed twice is a schema that
differs — the first cue probe lost its comparability exactly that way.

Study-specific things — arm names, cue words, what counts as a pass — belong under
`study/`, never in `tools/`. Elsewhere a different task should reuse `tools/` unchanged.

## Workspaces are built, not remembered

The starting state of a workspace is **constructive**: `study/ws-template/` is copied to a
fresh directory per slot, so "the two directories were identical" is a hash, not a note.
`template_tree_sha` in `records/ws/<slot>.create.json` is that hash; `tree_sha` in
`<slot>.after.json` is what the subject left behind.

Slots live wherever `$ASSAY_SLOTS` points. The fallback is a TEMP path, and that is only
for a quick look: a slot is evidence, `<slot>.create.json` names its absolute path, and
nothing re-reads that path — so a swept TEMP root turns past runs into dangling
references silently.

Both records are written with exclusive-create, so a slot is one run. Reusing a name fails
loudly rather than silently stacking two runs into one history.

## Two tidy tables

`analysis/index_tables.R` turns the index into two files under `records/tables/`:

| table | one row per | holds |
|---|---|---|
| `conditions` | `stimulus_id` — an **arm** | only what the subject received: system prompt, tool table, injected messages, route |
| `observations` | a **trial** | provenance (`input_id`, `harness_sha`) + workspace + outcome |

The split is what keeps a condition replaceable: two harness files that differ only in
row order collapse into **one** `conditions` row (`n_inputs = 2`) while staying two
`observations`. Replace the file, and no conclusion changes meaning — it was never
about the file.

`in_total` is `uncachedInputTokens + cacheReadTokens`. Only the sum is a property of the
prompt; the split between the two buckets is a cache artifact and moves between runs with
identical context.

Nothing in these tables is a score. No pass column, no filter — a criteria file applies
outside, and can be replaced without re-reading a record.

## Judgement is a function of the record, not part of it

```
judgment = grade(observation, criteria)
```

`study/criteria/v1.json` holds the truth values, the tolerance and — as important — the
tolerance's known limits. `tools/grade.py` applies it and writes
`records/judgment/<criteria_id>.json`, carrying the sha of both inputs.

Because the observation is expensive and the criteria are not, re-judging costs nothing.
Measured: tightening `rel` from `5e-4` to `2e-4` under a new `criteria_id` flipped three
verdicts from pass to fail while `observations_sha` stayed `dc455df4d6f66c09`. The
measurements did not move; only the rule did.

The criteria file states its own hole rather than hiding it: a relative tolerance cannot
enforce *reported precision*, so the Welch p-value answered as `0.0832` — three digits
where four were asked for — still lands at `4.7e-4` and passes. v2 of the criteria would
need a digit-count rule on the answer's literal text; v1 records the gap.

## What the operator leaks into every trial, and the window that closes it

The host injects a working-directory notice naming **two** paths — the destination and the
one it came from:

```
The working directory changed from "D:\RDirectory\harness-assay" to "D:\assay\slots\opB-01".
```

The "from" side is `parentHeader.cwd`, copied into the child's session header by
`childSessionMeta` and then compared in `WorkingDirectoryService.commit()`. It is **not**
the live working directory: changing the session's cwd and re-running changed nothing (six
runs issued half from `D:\workdir\harness-assay` recorded the same parent path 6/6).

No dispatcher-side option can prevent it. The notice is emitted before `harness_run` sees
the trial, the service's only config key is `defaultDirectory`, and this host has no
out-of-process subagent provider.

### The host is never left modified

`tools/patch_host_notice.py` rewrites the notice to name only the destination, and the
patch is a **repo-owned artifact applied inside a window**:

```bash
python tools/patch_host_notice.py --apply  --expect patched    # open
python tools/patch_host_notice.py --revert --expect original    # close
```

`--expect` exits non-zero when the file is not in the wanted state, so a batch refuses to
start, or refuses to claim it cleaned up. Nothing the subject needs is lost: the
runtime-context snapshot still carries `Current working directory: "<cwd>"`. What goes away
is the source side, which is operator state rather than stimulus.

Verified, same harness and task:

| run | paths delivered to the subject |
|---|---|
| `opA-01` (stock host) | `D:\RDirectory\harness-assay`, `D:\assay\slots\opA-01` |
| `patch-check-01` (patched) | `D:\assay\slots\patch-check-01` |
| `revert-check-01` (reverted) | `D:\RDirectory\harness-assay`, `D:\assay\slots\revert-check-01` |

### Three things that had to be learned the hard way

**A substring says nothing about bytes.** The first revert compared *content* and skipped
work when the original pattern was present — while the file was 171 bytes larger with CRLF
endings everywhere else. State is now decided by sha256 against hashes recorded for
`0.2.2-rc.1`, and revert restores the backup byte-for-byte.

**The file is not the host.** The running process holds the module in memory. The window is
bounded by `dsh_hot_reload`, not by writes: a revert without a reload leaves the host
patched. Both ends of the window need the reload.

**A stale patch is indistinguishable from a clean session** in the record — which is why
`tools/exposure_check.py` exists and why the batch should read its verdict, not assume it.

## Running it

```bash
python tools/record_index.py                       # records/index.jsonl
python tools/verify_index.py \
  --index records/index.jsonl \
  --expect study/expectations.json

Rscript analysis/index_tables.R                    # records/tables/*.csv
python tools/grade.py --criteria study/criteria/v1.json

python tools/workspace.py create   <slot>          # fresh workspace under %TEMP%
python tools/workspace.py snapshot <slot>          # what the subject left behind
```

No dependencies: the record layer is Python standard library only. The analysis layer (R)
is not in this repo yet; it consumes `records/index.jsonl`.

## What this repo will not do

It does not score anything. There is no `mean()` in the record layer. Judgement belongs in
a versioned criteria file applied *outside*, so that a criterion can be replaced and the
observation re-judged without paying for the observation twice.
