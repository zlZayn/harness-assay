# analysis/ — 分析层手册

只吃 `records/index.jsonl`，**从不读 run 目录**。记录层已经做过一次解析与哈希，这里不重做。

本目录只有**仪器层**：把索引变成整洁表，以及作图的工艺。某一项研究的表、估计与图，住在该研究的 `analysis/` 下——见[研究组织规则](../studies/README.md)与[当前研究](../studies/workspace-name-cue/)。

## 文件

| 文件 | 职责 | 输入 → 输出 | 改后必验 |
|---|---|---|---|
| `index_tables.R` | 三张整洁表：条件（一行一个 arm）/ 观测（一行一个 trial）/ 调用（一行一次工具调用） | `records/index.jsonl` → `records/tables/*.csv` | `verify_index` 仍通过；行数 = 索引行数；调用表行数必须等于观测表 `tool_calls` 的总和 |
| `theme_assay.R` | 作图工艺：字号阶梯、三层文字主次、来源脚注、排版自检。**不含配色** | 无 → 被研究的报告脚本 `source()` | 加新图后跑 `assay_audit_ok`；字号必须全在阶梯内 |
| `tolerance_notes.R` | 容差从哪来：把「4 位有效数字」换算成相对误差 | 无 → 屏显 | 换题或改精度要求时重跑，把数字抄进研究自己的 `criteria/*.json` |

## 变更影响路由

- 改列名或增删列 → `tools/grade.py` 读的 `answer_json` / `task_prompt_sha` 不能动；动了要同批改判定层。
- 改统计口径（例如加模型、加区间）→ 写进[架构文档](../docs/ARCHITECTURE.md)的边界一节，并把结论附带的 `(observation_id, criteria_version)` 说清。
- `theme_assay.R` 的**三层文字**是硬要求：粗体一行结论、灰色一行读法、极浅小字来源。设计理由与口径链留在正文，不塞进脚注；文件头写了为什么。
- 想要新的派生变量或新的图 → 那是研究的事，加在该研究的 `analysis/` 里，不要在仪器层开分支。

工作约束见 [AGENTS.md](AGENTS.md)。
