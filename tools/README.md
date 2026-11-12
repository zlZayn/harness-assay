# tools/ — 记录层手册

通用记录层：把 dispatcher 的 run 目录读成可计算的东西。**不认识任何研究**——arm 名、cue 词、通过标准一律在 `study/`。

## 文件

| 文件 | 职责 | 被谁依赖 | 改后必验 |
|---|---|---|---|
| `record_index.py` | run 目录 → 中性条件记录（两个身份 + 交付路径 + 工具调用原文 + 结局） | `verify_index`、`index_tables.R`、`process_report`、`exposure_check` | 跑一次，`verify_index` 3/3 |
| `verify_index.py` | 拿研究的期望文件校验索引 | — | 同上，PASS/FAIL 都要看到 |
| `workspace.py` | 从模板造工作区；跑完快照 | `batch_plan` 用同名槽位约定 | `create` 两次同名必须失败 |
| `grade.py` | 按准则判定观测 | — | 换 `criteria_id` 重算，观测 sha 不变 |
| `exposure_check.py` | 交付上下文里有没有没人声明的 cue | 跑批前的闸门 | 占一个词表里的槽位必须 FAIL |
| `patch_host_notice.py` | 宿主通知的窗口补丁 | 跑批前后各一次 | `--apply --expect patched` 后 `--check` 读 patched；`--revert` 后读 original 且包目录只剩原件 |
| `batch_plan.py` | 臂表 + 题面 → 待跑表（按重复交错）；跑前跑后各查一次，并断言一个批次内宿主摘要单值 | 跑批 | `--verify` 在占位槽位上 exit 2；交付字节不一致也 exit 2 |

全部只用 Python 标准库，无第三方依赖。

## 变更影响路由

- 改 `record_index.py` 的字段或身份构成 → 同步 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 的「两个身份」，并重跑 `analysis/index_tables.R`（列名对应）。
- 改 `patch_host_notice.py` 的两个已知哈希 → 必须来自一次真实的 `apply`/`revert` 往返，且记下宿主版本。
- 新增脚本 → 写进本表，并在根 [AGENTS.md](../AGENTS.md) 的常用命令里给一行。

工作约束见 [AGENTS.md](AGENTS.md)。
