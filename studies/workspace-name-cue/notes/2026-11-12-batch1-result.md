# 依据：W5 批次 1 读出了什么（2026-11-12）

状态：生效

## 背景

第一批 cue 实验：`lang` 家族 4 臂 × k=7 = 28 trial，交错执行，全部落在同一个宿主窗口内（通知不再点名操作者路径）。

- 目标结局：过程层——受试体**用了哪个运行时**。正确性在本题上是天花板，答对与否分不开臂。
- 复现：`tools/record_index.py` → `analysis/process_report.py`；统计量是那张 2×2 表上的 Fisher 精确检验。
- 每臂：`python`/`tidyverse` 是 cue 臂，`cobden`/`hedgerow` 是同 token 成本的中性臂。

## 结论

### 1. 操纵确实发生了

28 条试次里 `stimulus_id` 全不相同，且**唯一**变化的就是那两条点名槽位的注入消息（28 个不同摘要）；系统提示、工具表、题面、schema、路由、sealed 全部单值。所以这不是"改了个变量其实没送到"。

### 2. R 只在 tidyverse 臂出现

| 臂 | n | R | python | 只用 pwsh |
|---|---|---|---|---|
| python | 7 | 0 | 7 | 0 |
| tidyverse | 7 | **2** | 3 | 2 |
| cobden（中性） | 7 | 0 | 5 | 2 |
| hedgerow（中性） | 7 | 0 | 4 | 3 |

形状与理论一致：唯一出现 R 的是那个点名了 R 生态包的臂。但强度不够看：

| 对比 | 表 | Fisher 单侧 p |
|---|---|---|
| R 使用，cue vs 中性 | 2/14 vs 0/14 | 0.241 |
| R 使用，tidyverse vs 两中性 | 2/7 vs 0/14 | 0.100 |
| python 使用，python vs 中性 | 7/7 vs 9/14 | 0.098 |

**没有一项过 0.05。** 这批数据的方向和理论一致，但它还不是证据。诚实说法是：R 的出现被限制在预测的那个臂里，样本量不足以称之为效应。

### 3. 设计高估了效应量

批次 1 是照着 p₁ = 0.4 规划 k=7（那个假设下 power 0.88）。实测 tidverse 臂 2/7 ≈ 0.29、cue 臂合并 2/14 ≈ 0.14——**都低于规划值**，于是在同一张表下 power 掉到 0.33–0.61。第二批的 k 要按这些读数重算，不能沿用。

### 4. 一个自己造成的缺陷，被宿主抓到了

28 次调用里我手打了 28 份 schema。第 1 份是 `{type, properties, required}`（与 `tasks/wells-meansd.json` 一致），第 2 份起变成 `{properties, required, type}`。语义相同，**交付的字节不同**。

- 我们自己的规范哈希（`sort_keys`）看不见：`schema_sha` 28 条全是 `c920a8f49e94`。
- 宿主的 `toolSchemaDigest` 看得见：`25b8fa3e`（python-01，1 条）vs `8cacc1d6`（其余 27 条）。

这正好是 `docs/ARCHITECTURE.md` 陷阱表的第一条，而我踩了。补的守卫是 `batch_plan --verify` 现在断言：一个批次内宿主摘要必须单值，否则 exit 2。它在真实数据上当场 FAIL 过一次，然后才被记录。

影响范围可量化：把 python-01 剔掉，R 表一格不动（2/13 vs 0/13），只有 python 臂的 7/7 变 6/6。**结论对这条缺陷不敏感。**

## 支撑的决策

- [跑批清单](../../../tools/batch_plan.py) 的 `delivered_by_host()`：比较臂之间是否收到同样的字节，用宿主的摘要而不是我们的。
- 第二批（`letter` 家族）的 k 按本批实测率重算，不沿用 0.4 的假设。

## 影响

- `records/workspace-name-cue/plan/wells-meansd-k7-e4ebb4165f7a.jsonl` 是这批的完整顺序与 cwd；`records/workspace-name-cue/ws/<slot>.{create,after}.json` 是 28 个槽位的前后树哈希（全部 2 文件、树哈希一致——没有一个试次在工作区留下东西）。
- 宿主已还原：`--check` 读 original，包目录只剩 `index.js` 与 `types/`。
- 这条不能证明"目录名会改变 agent 的语言选择"。它能证明的是：该问的量已经进了记录、操纵已确认送达、效应量比预想的小——第二批该投多少试次，现在有依据了。
