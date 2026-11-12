# harness-assay

Measuring what an agent **harness** does to an agent — not what a model can do.

A harness is the row list a session runs with: the system prompt, the tool table, the
injected context. Change one of those and behaviour moves. The point of this repo is to
make that movement **believable after the fact**: the observation happens once, the
judgement criteria will drift, and later readers only have what was written down.

## The split that makes it work

Records are produced by [`dsh-harness-dispatcher`](https://github.com/zlZayn) and land in
`$DSH_HOME/harness-dispatcher/runs/<runId>/`. That layer is deliberately left alone. What
lives here is the **overlay**: reading those records into something computable, and making
sure a conclusion can be traced back to the conditions that produced it.

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
study/            one study's own declarations
  expectations.json  pairs whose relationship is already known, so the index self-checks
fixtures/         task data
records/          generated index (gitignored)
```

Study-specific things — arm names, cue words, what counts as a pass — belong under
`study/`, never in `tools/`. Elsewhere a different task should reuse `tools/` unchanged.

## Running it

```bash
python tools/record_index.py                       # writes records/index.jsonl
python tools/verify_index.py \
  --index records/index.jsonl \
  --expect study/expectations.json
```

No dependencies: the record layer is Python standard library only. The analysis layer (R)
is not in this repo yet; it consumes `records/index.jsonl`.

## What this repo will not do

It does not score anything. There is no `mean()` in the record layer. Judgement belongs in
a versioned criteria file applied *outside*, so that a criterion can be replaced and the
observation re-judged without paying for the observation twice.
