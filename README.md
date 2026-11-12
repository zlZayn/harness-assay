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
analysis/         R, over the index only — never over a run directory
  index_tables.R    two tidy tables: conditions (per arm), observations (per trial)
  tolerance_notes.R where the numeric tolerance comes from
study/            one study's own declarations
  expectations.json  pairs whose relationship is already known, so the index self-checks
  criteria/v1.json   truth, tolerance, and the known limits of that tolerance
  ws-template/       the only source of truth for what a workspace starts as
records/          generated (gitignored)
```

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

## What the operator leaks into every trial

The host injects a working-directory notice naming **two** paths — the destination and the
one it came from:

```
The working directory changed from "D:\RDirectory\harness-assay" to "D:\assay\slots\opB-01".
```

The "from" side is the operator's directory, and it is **not** the live working directory.
Changing the session's cwd and re-running changed nothing: six runs issued half from
`D:\workdir\harness-assay` recorded the same parent path 6/6. It is a per-session constant.

What that cost, measured on 2026-11-12: those six runs had identical delivered context —
step-1 prompt size `1886` tokens in every one — yet the naive arm-vs-arm comparison
reported a **+14.4% wall-time difference**. The verdict was noise, and only the record's
own step-1 accounting could show it.

Two consequences for any study here:

- the operator path is a **constant to declare**, not a variable to control;
- `RDirectory` is an R-flavoured token sitting in the context of every trial of a session
  rooted there. A study of language cues must either declare it or run from elsewhere.

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
