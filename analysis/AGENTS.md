# analysis/ — 规则层

继承根规则，见 [../AGENTS.md](../AGENTS.md)。

本目录特有约束：

- **不读 run 目录**。需要新字段就回去改 `tools/record_index.py`，别在这里二次解析 `events.jsonl`。
- **不判定**。这里只做描述与估计；pass/fail 属于 `tools/grade.py` + 各研究的 `criteria/`。
- **不认识任何研究**。出现 arm 名、cue 词、通过标准、具体 run id，就搬去 `studies/<id>/analysis/`。
- 每个产出的数字必须能追到 `stimulus_id` 与 `criteria_id`；图与表都要能重新生成。
- 报告口径改动要留痕：换算法就换 `criteria_id` 或写一份依据记录，不静默改旧结论。
- R 脚本以项目根为工作目录，相对路径从根写起，不用 `setwd()`。

文件职责与改后必验见 [README.md](README.md)。
