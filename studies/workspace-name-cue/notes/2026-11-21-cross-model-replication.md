# 跨模型复制：R 生态目录名 cue 在 Kimi-K3.1-Pro 中明显减弱

状态：生效

（依据类记录。研究仍为 `workspace-name-cue`，新增的是同一研究内的跨模型复制，不是新研究目录。预注册见 [norris-r4-v1](../prereg/norris-r4-v1.json)，计划为 `norris-ols-k6-r07-e6eaa4aa89c3`。）

## 结果

在 **Kimi-K3.1-Pro** 上完成与 original 设计相同的 288 次试次。模型名称在叙述中写作 Kimi-K3.1-Pro 与 DeepSeek-V4.1-Flash-1017，不带渠道名或前缀；完整路由 ID 只留在运行记录与预注册的操作元数据中。

主对比仍为：

\[
P(Y=R\mid r\text{-}eco)-P(Y=R\mid software)
\]

| 模型 | `r-eco` | `software` | Δ | 精确单侧 p |
|---|---:|---:|---:|---:|
| DeepSeek-V4.1-Flash-1017 | 30/72 = 41.67% | 11/72 = 15.28% | +0.2639 | 0.000243 |
| Kimi-K3.1-Pro | 7/72 = 9.72% | 0/72 = 0% | +0.0972 | 0.108696 |

Kimi 的精确置换检验为 **293930 / 2704156 = 0.108696**。原研究的大效应没有以同等强度复现；但“未达显著”不等于“证明无效”，因为点估计仍与同方向。

跨模型差（Kimi 减 original）为 **−0.1667**。按预注册对 24 个措辞做配对聚类 bootstrap 10000 次（seed 20261121），95% 区间为 **[−0.3056，约 0.00]**。区间右端贴零，所以模型间差异也不应被包装成已经完全确定的机制结论。

## 结局是否可靠

- Kimi 的 7 次首次 R **全部实际执行了 R 代码**，所以 `ever executes R` 与首次点名结局相同：7/72 vs 0/72，p = 0.108696。
- 首次双命中仅 2 次；若改记为“首次只命中 R”，对比为 5/72 vs 0/72，p = 0.500。这个替代估计量与原文一样只作口径说明，不当作主结论。
- 288 条全部完成、全部交出结构化答案，零工具调用 0/288；使用运行时 272/288，混用仅 2/288。
- 数值判定为 271 pass / 17 fail，无结构化 missing。正确性仍是次级结果，不用于替代主结局。
- Kimi 剩余 R 信号集中在少数名字：`rlang` 5/6、`dplyr` 与 `forcats` 各 1/6，其余 R 包名为 0。不能把单名字表现推广成普遍的包名效应。
- 工作量在 Kimi 各条件内部基本一致，但 Kimi 整体 steps/tool calls 低于原模型。跨模型图因此分别显示模型差异与条件内部差异，不把“努力程度不同”当作 cue 的唯一解释。

## 仪器与记录

- 交付工具表与系统提示摘要分别为 `6218479a` 和 `75222986`，与原批一致；题面与 schema 均匹配计划。
- 路径暴露、控制变量、工作区模板、记录完整性和实际启动位置检查均通过；无试次因结局被丢弃。
- 宿主补丁已按真实应用/还原往返校准到当前 rc.3 字节，最终恢复 `original` 且无备份残留。
- 所有 288 条结构化答案在分析表往返中保持零变化。分析层的 JSON 输出改为 17 位有效数字，以覆盖 double 的完整往返精度；原始 run 记录未改。

派生证据：

- [Kimi 主检验](../../../records/workspace-name-cue/judgment/cue-effect-kimi.json)
- [跨模型差与区间](../../../records/workspace-name-cue/judgment/cross-model.json)
- [跨模型对照表](../../../records/workspace-name-cue/summary/cross-model-display.csv)
- [Kimi 结局口径表](../../../records/workspace-name-cue/summary-kimi/rules.csv)
- [双模型图](../../../records/workspace-name-cue/figures/fig-cross-model.png) 与原五类图的双模型版本（`fig-contrast` / `fig-rank` / `fig-blocks` / `fig-mixed` / `fig-effort`）

## 结论边界

这次复制增强研究可信度的方式不是“再次证明同一个大效应”，而是暴露了**模型间异质性**：DeepSeek-V4.1-Flash-1017 中的强 cue 在 Kimi-K3.1-Pro 中只剩较弱且未达显著的同向信号。

两批仍绑定不同宿主版本与日历批次，因此跨模型差不是随机化的纯模型效应。两个模型也不足以识别训练语料先验。报告应保留原结果，同时明确限制其外推；不应写“所有模型都有 26 点效应”，也不应写“cue 已被证明无效”。
