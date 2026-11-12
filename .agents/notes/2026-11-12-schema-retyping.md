# 依据：重打 schema 是本项目唯一反复发生的故障（2026-11-12）

状态：生效

## 背景

批次的输出 schema 必须在每次 `harness_run` 调用里重新键入一份。工具接口只接受字面量，没有"从 `study/tasks/*.json` 读出来传进去"这条路。

于是同一个缺陷发生了两次：

| 时间 | 批次 | 后果 |
|---|---|---|
| 批次 1 | `wells-meansd` 28 条 | 第 1 条与其余 27 条 `toolSchemaDigest` 不同（`25b8fa3e` vs `8cacc1d6`），当时没发现，跑完才被 `delivered_by_host` 抓出 |
| 批次 2 | `norris-ols` 第 2 条 | 顶层键序与属性顺序同时漂移（`6218479a` vs `034e7014`），当场抓住，丢弃该子批 |

两次都是**键序**漂移，不是内容错。内容错会被 `declared_vs_received` 抓；键序只有宿主摘要看得见。

## 结论

**这不是"操作不够仔细"，而是接口形状决定的必然。** 只要 schema 需要人工重复键入 N 次，就会有 N 次独立的机会出错，且错误不可见——我们的规范哈希对键序是瞎的。

所以缓解手段只能是**检查**，不能是**纪律**：

- 开跑第一条之后立刻比对 `toolSchemaDigest`，此后每组 12 条复查一次。
- 一旦漂移，按 prereg 的 `decision_rules` 丢弃受影响子批，不动其他子批。
- 已存在的守卫分工：`delivered_by_host` 看臂间是否一致（看不见键序以外的内容差），`declared_vs_received` 看记录与声明是否同内容（看不见键序）。两者都过，才说明交付字节一致。

## 支撑的决策

- 批次 2 的 96 条子批以"每组 12 条复查摘要"为执行纪律，写进 [prereg](../../studies/workspace-name-cue/prereg/norris-r3-v1.json) 的 `execution.gate_after_each_sub_batch` 之外的每次复查。
- 两次事故的 run 目录都保留在 `$DSH_HOME/harness-dispatcher/discarded/`（不在 `runs/` 下，不进索引），附 `WHY.txt`。

## 长期方向

真正的解法是让 schema 不经过人手：要么宿主/调度器支持从文件取 schema，要么把六个数改成文本格式由解析层抽取（代价是判定层要能读非结构化输出）。两者都未做，记为待办。

在此之前，**任何一次跑批，第一条之后的摘要比对是必须的，不是可选的。**
