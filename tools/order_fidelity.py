"""Did the batch run in the order the plan declared?

Concurrency is the only reason this needs checking. Under bounded concurrency the planned
order is approximated, not obeyed: four trials are in flight at once, so position is known
to about +-4. This measures how good that approximation actually was, from the host's own
start timestamps rather than from the order the calls were made.

Reported, not enforced. A weak correlation would not bias the contrast -- it would weaken
the claim that position was balanced across conditions -- so the number belongs in the
record either way.
"""
import json
import os
import pathlib
import sys

PLAN = sys.argv[1] if len(sys.argv) > 1 else \
    'records/plan/norris-ols-k6-7a8e2a45c2f1.jsonl'
RUNS = pathlib.Path(os.environ.get("DSH_HOME") or pathlib.Path.home() / ".dsh") \
    / "harness-dispatcher" / "runs"

plan = {}
for line in open(PLAN, encoding='utf-8'):
    r = json.loads(line)
    plan[r['slot']] = r['order']

actual = []
for d in RUNS.iterdir():
    p = d / 'run.json'
    if not p.exists():
        continue
    rj = json.loads(p.read_text(encoding='utf-8'))
    slot = pathlib.PureWindowsPath(rj['task']['cwd']).name
    if slot not in plan:
        continue
    actual.append((rj['startedAt'], plan[slot], slot))

actual.sort()
n = len(actual)
if n < 2:
    print('not enough trials to say anything')
    sys.exit(0)

by_start = [i for i, _ in enumerate(actual)]
by_order = [o for _, o, _ in actual]


def spearman(a, b):
    ra = [sorted(a).index(x) for x in a]
    rb = [sorted(b).index(x) for x in b]
    m = len(a)
    ma, mb = sum(ra) / m, sum(rb) / m
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = (sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb)) ** 0.5
    return num / den if den else 0.0


drift = [o - (i + 1) for i, o in enumerate(by_order)]
print(f'{n} trials\n')
print(f'Spearman(start sequence, planned order) = {spearman(by_start, by_order):+.3f}')
print(f'position drift   min {min(drift):+d}  max {max(drift):+d}  '
      f'mean {sum(drift) / len(drift):+.1f}')
print(f'inversions       {sum(1 for d in drift if d != 0)}')
print()
print('largest drift (planned order ran noticeably early or late):')
for (started, order, slot), d in sorted(zip(actual, drift), key=lambda x: -abs(x[1]))[:6]:
    print(f'  {slot:<15}planned {order:<4}drift {d:+d}')
