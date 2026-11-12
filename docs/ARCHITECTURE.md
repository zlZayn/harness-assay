# harness-assay 架构说明

本文只写不变的设计与约束（为什么）。文件级职责见各目录 `README.md`，规则见各 `AGENTS.md`，统计口径见各研究自己的 `DESIGN.md`（当前 → [workspace-name-cue](../studies/workspace-name-cue/DESIGN.md)）。

## 目标

让「harness 对 agent 行为的影响」在**事后**仍可被相信。

前提是硬性的：观测只发生一次，判定标准会漂移，后来者只能看到留下的记录。三条不可破坏的约束由此推出。

## 不可破坏的约束

### 1. 观测与判定分离

观测贵且一次性，判定便宜且会变。所以记录里没有分数、没有 `mean()`、没有 pass 列。

`judgment = grade(observation, criteria)` 必须是纯函数：改准则就重跑判定，**不重跑观测**。

代价与收益都是实测的：把容差从 `5e-4` 收到 `2e-4`，三条判定由 pass 翻成 fail，而 `observations_sha` 一动不动。

### 2. 结论锚在刺激，不锚在产生刺激的文件

同一份刺激可以由不同字节的文件产生——例如只改了行顺序的 harness，挂载后工具表被规范化成同一张。

所以记两个身份：

| 身份 | 回答 | 覆盖 |
|---|---|---|
| `input_id` | 哪份 spec 产出它 | harness 字节、题面、schema、工作区路径 |
| `stimulus_id` | 这是不是同一个实验 | 系统提示、工具表逐字、每条注入消息、题面 |

分组用 `stimulus_id`。文件可替换，交付的上下文不可替换——这就是「换条件而不牵连结论」的机械版本。

### 3. 记录层不认识任何研究

`tools/`、`analysis/` 里不出现 arm 名、cue 词、通过标准、run id。研究自己的一切都在 `studies/<id>/`。

研究名同样是数据：根 `study.json` 指当前的，`$ASSAY_STUDY` 覆盖。工具读清单，不写默认值——写死的默认值会在有第二个研究那天静默指向错的那个。

理由不是洁癖：通用脚本一旦长出项目知识，第二个任务就得复制一份，然后两份各自漂。

### 4. 宿主静止态零残留

对宿主包的任何改动都必须是**窗口**：开窗前/关窗后用哈希断言状态，关窗后逐字节还原并删掉备份。

补丁若不在启动时加载，就必须靠 `dsh_hot_reload` 生效——**磁盘不是宿主**。

## 数据流

```
$DSH_HOME/harness-dispatcher/runs/<runId>/     dispatcher 产出，只读
        │
        │  tools/record_index.py        （读三文件，算两个身份）
        ▼
records/index.jsonl                            中性条件记录 ——— 仪器级，覆盖所有 run
        │
        │  analysis/index_tables.R      （R 只读索引，不碰 run 目录）
        ▼
records/tables/{conditions,observations,calls}.csv   条件表 / 观测表 / 调用表 ——— 仪器级
        │
        ├── tools/grade.py + studies/<id>/criteria/*.json
        │        ▼
        │   records/<id>/judgment/<criteria_id>.json      判定（带两个输入的 sha）
        │
        └── studies/<id>/analysis/*    （该研究的表、估计、图）
                 ▼
            records/<id>/{trials.csv,figures/}
```

工作区是条件的一部分，走另一条路：`studies/<id>/ws-template/` → 复制成 `<slot>` → 前后各算一次树哈希。

产物按**谁拥有它**分目录，不按类型分：`records/` 根下是仪器级的（这台机器上所有 run），`records/<id>/` 下是某一研究的。混放会让第二个研究覆盖第一个的 plan 与判定，而覆盖是静默的。

## 三条边界

| 边界 | 一边 | 另一边 |
|---|---|---|
| 记录 / 分析 | Python 标准库，逐字节精确，零依赖 | R + tidyverse，只吃整洁表 |
| 仪器 / 研究 | `tools/`、`analysis/` 不知道任何研究存在 | `studies/<id>/` 装该研究的一切声明与分析 |
| 条件 / 观测 | 研究声明要跑什么 | `records/` 记录跑了什么 |

语言分工不是偏好：记录层做的是一次解析与哈希，标准库够且不引入环境；分析层做统计与图，R 更直接。

## 防错清单（都是踩过的）

| 陷阱 | 机制 | 守住的方式 |
|---|---|---|
| 规范化哈希看不见真实差异 | `sort_keys` 抹平 JSON Schema 的属性顺序，而模型看得见 | 优先用宿主自己的 `systemPrompt.digest` / `toolSchemaDigest` |
| token 记账把缓存当成行为 | `inputTokens` 是**未缓存**部分，命中缓存时读数小 8 倍 | 一律用 `uncached + cacheRead` |
| 子串不等于字节 | 内容片段还在，文件却大了 171 字节、全是 CRLF | 状态一律由 sha256 判定；改文件用字节操作 |
| 磁盘不是宿主 | 写回文件不改变运行中的进程 | 窗口两端都要 `dsh_hot_reload` |
| 残留补丁与干净会话在记录里同形 | 两者都表现为「通知里没有操作者路径」 | `tools/exposure_check.py` 读最新一条 run 判定 |
| 手打两遍的 schema 会不一致 | 属性顺序一变，交付的工具表就变 | 题面与 schema 只在 `studies/<id>/tasks/*.json` 写一次 |
| 主结局可能不在记录里 | 正确性到天花板时，唯一能用的结局是"用了什么方法"，而它只存在于工具调用原文 | `record_index` 折 `observed.tool_calls`；怎么读是研究自己的 `interpreters.json` 的事 |
| 臂与位置共线 | 一臂的重复挤在一个时间块里，漂移和臂效应事后分不开 | 按重复交错；`order` 进 plan 也进 `plan_id` |
| 派生变量只在代码里 | 口径埋在 `mutate()` 里，只有作者能审 | 研究声明 `features.json`，脚本双向断言覆盖 |

## 不做什么

- 不打分。判定在仓外、按版本化准则执行。
- 不重复 dispatcher 的记录格式。`records/` 是它的产出，我们只读。
- 不改宿主的常驻状态。要改就开窗，关窗留证。
