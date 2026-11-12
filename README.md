# harness-assay

测量 **harness**（系统提示 + 工具表 + 注入上下文）对 agent 行为的影响——不是测模型能做什么。

观测只发生一次，判定标准会漂移，后来者只有记录可看。这个仓的存在理由是让那之后的结论**仍然可信**。

## 能力

- **记录认人**：把 dispatcher 的 run 目录读成中性条件记录，两个身份分开——来源（`input_id`）与刺激（`stimulus_id`）。
- **条件可构造**：工作区从模板复制，初态是一个哈希而不是一句说明；槽位一名一次，复用会响亮失败。
- **观测与判定分离**：观测存原始产物，判定按版本化准则重算，改准则不重跑观测。
- **通道体检**：检查受试体实际收到的上下文里，有没有没人声明过的提示词通道。
- **跑批前有清单**：臂表 + 题面 → 待跑表，跑前跑后各查一次。
- **分析在 R**：只吃整洁表，不碰 run 目录。

## 快速开始

需要 DSH 与 [`dsh-harness-dispatcher`](https://github.com/dsh-plugin-lab/dsh-harness-dispatcher) 产出的 run 记录。

```bash
python tools/record_index.py                       # run 目录 -> records/index.jsonl
python tools/verify_index.py \
  --index records/index.jsonl \
  --expect study/expectations.json                 # 3 项已知识别关系

Rscript analysis/index_tables.R                    # -> records/tables/*.csv
python tools/grade.py --criteria study/criteria/v1.json
```

记录层只用 Python 标准库；分析层用 R + tidyverse。

## 边界

- 本仓**不打分**。判定由 `study/criteria/*.json` 在仓外应用，可替换。
- **不改宿主常驻状态**。需要时开窗、关窗、留哈希证据。
- 记录留在 `$DSH_HOME/harness-dispatcher/runs`，本仓只做覆盖层。

## 维护者入口

- 文档地图与项目规则 → [AGENTS.md](AGENTS.md)
- 设计与约束（为什么） → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 测过什么、什么失败了 → [.agents/notes/](.agents/notes/)

## 许可

未声明许可证。
