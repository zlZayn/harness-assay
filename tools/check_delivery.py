"""Gate after every group of 12: did the delivered bytes stay identical?

The prompt and the output schema have to be re-typed into every harness_run call, so each
call is an independent chance to drift -- and drift is invisible to our canonical hash.
This is the check that made the difference between catching it after 2 trials and after 28.
"""
import hashlib
import json
import os
import sys

RUNS = r'C:\Users\speak\.dsh\harness-dispatcher\runs'
PLAN = r'D:\RDirectory\harness-assay\records\plan\norris-ols-k6-7a8e2a45c2f1.jsonl'

plan = {}
for line in open(PLAN, encoding='utf-8'):
    r = json.loads(line)
    plan[r['slot']] = r

rows = []
for d in sorted(os.listdir(RUNS)):
    p = os.path.join(RUNS, d)
    rj_path = os.path.join(p, 'run.json')
    if not os.path.exists(rj_path):
        continue
    rj = json.load(open(rj_path, encoding='utf-8'))
    slot = os.path.basename(rj['task']['cwd'])
    if slot not in plan:
        continue
    trials = os.path.join(p, 'trials.jsonl')
    # a run directory appears at dispatch and its trials.jsonl fills in as trials finish;
    # reading it the instant it exists would count an in-flight trial as a broken one
    try:
        with open(trials, encoding='utf-8') as fh:
            first = fh.readline()
        if not first.strip():
            continue
        t = json.loads(first)
    except (OSError, json.JSONDecodeError):
        continue
    mi = t.get('modelInput') or {}
    rows.append({
        'slot': slot,
        'order': plan[slot]['order'],
        'tool': mi.get('toolSchemaDigest'),
        'sys': (mi.get('systemPrompt') or {}).get('digest'),
        'prompt': hashlib.sha256((rj['task']['prompt'] or '').encode()).hexdigest()[:16],
        'want_prompt': plan[slot]['prompt_sha'],
        'stop': t['stopReason'],
        'answer': t.get('structured'),
    })

rows.sort(key=lambda r: r['order'])
print(f"{'ord':<5}{'slot':<15}{'tool':<11}{'sys':<11}{'prompt':<18}{'match'}")
print('-' * 66)
for r in rows:
    # the plan stores a 12-char prefix, this file hashes to 16 -- compare prefixes
    ok = 'ok' if r['prompt'].startswith(r['want_prompt']) else 'PROMPT-DRIFT'
    print(f"{r['order']:<5}{r['slot']:<15}{str(r['tool']):<11}{str(r['sys']):<11}"
          f"{r['prompt']:<18}{ok}")

tools = {r['tool'] for r in rows}
sysd = {r['sys'] for r in rows}
prompts = {r['prompt'].startswith(r['want_prompt']) for r in rows}
print()
print('toolSchemaDigest set :', sorted(tools))
print('systemPrompt set     :', sorted(sysd))
print('all prompts match plan:', prompts == {True})
print('stop reasons         :', sorted({r['stop'] for r in rows}))
print()
if len(tools) == 1 and len(sysd) == 1 and prompts == {True}:
    print(f'GATE PASS -- {len(rows)} trials, one delivered tool table')
    sys.exit(0)
print('GATE FAIL -- discard this group and re-run it')
sys.exit(2)
