# harness-assay

Measure what **harness** — system prompt, tool table, injected context — does to an agent's behaviour, not what a model can do.

A run is observed once. Judgement criteria drift. A later reader has only the record. This repo exists so the conclusions drawn afterwards are still worth believing.

## 仪器 / 研究

| | 是什么 | 在哪 |
|---|---|---|
| **仪器** | 把 dispatcher 的 run 目录读成可计算的东西、开工窗、查交付字节。**不知道任何研究存在** | `tools/`、`analysis/` |
| **研究** | 一项具体研究：它声明的输入、预注册、分析、产物 | `studies/<id>/` |

一个研究一个目录。加第二个研究不需要改仪器层一行——见 [studies/README.md](studies/README.md)。

当前研究：[workspace-name-cue](studies/workspace-name-cue/) — 工作目录名里的一个词，会不会改变 agent 挑哪个运行时。

**想直接读结论**：[研究报告](studies/workspace-name-cue/REPORT.html)（自包含 HTML，图已内嵌，离线可看）。

## 快速开始

需要 DSH 与 [`dsh-harness-dispatcher`](https://github.com/dsh-plugin-lab/dsh-harness-dispatcher) 产出的 run 记录。

```bash
python tools/record_index.py                       # run 目录 -> records/index.jsonl
python tools/verify_index.py \
  --index records/index.jsonl \
  --expect studies/$(python -c "import json;print(json.load(open('study.json'))['current'])")/expectations.json

Rscript analysis/index_tables.R                    # 仪器层三张整洁表
```

`$ASSAY_STUDY` 指定研究，否则读根目录 `study.json`；`$ASSAY_SLOTS` 指定槽位根。两者都不猜默认值。

## 边界

- 本仓**不打分**。判定由各研究的 `criteria/*.json` 在仓外应用，可替换。
- **不改宿主常驻状态**。需要时开窗、关窗、留哈希证据。
- 记录留在 `$DSH_HOME/harness-dispatcher/runs`，本仓只做覆盖层。
- `records/index.jsonl` 与 `records/tables/*.csv` 覆盖这台机器上**所有** run；某项研究自己的产物在 `records/<study>/`。

## 维护者入口

- 项目规则与文档地图 → [AGENTS.md](AGENTS.md)
- 设计与约束（为什么） → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 测过什么、什么失败了 → [.agents/notes/](.agents/notes/)（仪器层的决定）、各研究的 `notes/`

## 许可

未声明许可证。
