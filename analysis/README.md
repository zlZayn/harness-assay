# analysis/ — 分析层手册

只吃 `records/index.jsonl`，**从不读 run 目录**。记录层已经做过一次解析与哈希，这里不重做。

分三层：**记录层的表**（`index_tables.R`，不带任何研究知识）→ **研究层的表**（`cue_tables.R`，把条件、运行时分类、plan 顺序接上）→ **报告与图**（`cue_report.R`，只读 `trials.csv`）。后面要做新的分析，加在第三层，不再碰 JSON。

## 文件

| 文件 | 职责 | 输入 → 输出 | 改后必验 |
|---|---|---|---|
| `index_tables.R` | 三张整洁表：条件（一行一个 arm）/ 观测（一行一个 trial）/ 调用（一行一次工具调用） | `records/index.jsonl` → `records/tables/*.csv` | `verify_index` 仍通过；行数 = 索引行数；调用表的行数必须等于观测表 `tool_calls` 的总和 |
| `cue_tables.R` | 研究层的一张表：一行一个 trial，接上条件、措辞、运行时分类、plan 顺序、判定 | `records/tables/*.csv` + `study/conditions.json` + `interpreters.json` + `prereg/` + plan + judgment → `records/tables/trials.csv` | `trials.csv` 行数 = plan 行数；`first_runtime` 只能取 `interpreters.json` 声明过的值；条件不得缺失 |
| `cue_report.R` | 描述与估计：逐条件、逐措辞、措辞层面 bootstrap 区间、分块一致性、成本、正确性交叉表；三张图 | `records/tables/trials.csv` → 屏显 + `records/figures/*.png` | 换 `trials.csv` 后重跑；区间与 `cue_effect.py` 的点估计必须一致 |
| `tolerance_notes.R` | 容差从哪来：把「4 位有效数字」换算成相对误差 | 无 → 屏显 | 换题或改精度要求时重跑，把数字抄进 `study/criteria/*.json` |
| `cue_tokens.py` | 各臂的路径 token 成本，切分器与版本一并声明 | `study/cue-arms.json` 的候选 → 同名文件 | 改候选列表后重跑，并核对 `_calibration` 那段仍成立 |
| `exposure_report.py` | 那次操纵到底发生了没有 | 索引 → 屏显 | 同题两组刺激应不同；若相同即为未操纵 |
| `process_report.py` | 每个 trial 用了哪个解释器，按臂汇总 | 索引 + `study/interpreters.json` + 臂表 → 屏显 | 换解释器词表后重跑；`mixed` 列应能解释清楚 |
| `cue_effect.py` | 执行 prereg 里声明的对比：措辞层面精确置换，穷举 C(n,k) | 索引 + `study/conditions.json` + `interpreters.json` + `prereg/` → `records/judgment/cue-effect.json` | 改条件表或 `plan_id` 后重跑；`C(n,k)` 那一行必须仍打印 `== enumerated` |
| `cue_tokens_check.py` | 代理切分器 vs 宿主计数器 | 索引 + 真机 run → 屏显 | 有新建的同臂 run 时重跑 |

`cue_tokens.py` 需要 `tiktoken`，用 `uv run --with tiktoken==0.12.0` 跑；R 侧需要 tidyverse + jsonlite + scales；其余脚本标准库即可。

## 变更影响路由

- 改列名或增删列 → `tools/grade.py` 读的 `answer_json` / `task_prompt_sha` 不能动；动了要同批改判定层。`trials.csv` 是下游唯一入口，加列优先加在那里。
- 改统计口径（例如加模型、加区间）→ 写进 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 的边界一节，并把结论附带的 `(observation_id, criteria_version)` 说清。
- 改 `cue_tokens.py` 的候选列表 → 同步 `study/cue-arms.json` 的生成结果，并重跑 `batch_plan`。
- `process_report.py` **只描述、不判定**。要出 p 值就写进 `study/criteria/`，别在这里加。
- `cue_effect.py` 不新增规则：它只执行 `study/prereg/*.json` 里已经声明的对比与检验形式。要换对比就另开一份 prereg，`plan_id` 会跟着变。
- `cue_report.R` 的区间是**描述**，不是检验：它重采样措辞，说的是"这 48 个名字"，不构成对"名字总体"的推断。留一措辞稳定性只能作为读数报出，**不许**据它删词再重跑主检验。
- `cue_tables.R` 的 `verdict` 列是从 `records/judgment/` 搬进来的，本层不算判定。要改达标口径只能换 `criteria_id`。

工作约束见 [AGENTS.md](AGENTS.md)。
