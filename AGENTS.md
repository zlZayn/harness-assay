# harness-assay — 维护索引

## 全局规则

- 设计与不可破坏的约束 → [架构文档](docs/ARCHITECTURE.md)
- **仪器层不知道研究存在**。`tools/`、`analysis/` 里出现研究名、cue 词、通过标准、具体 run id 就是放错了地方——那些属于 `studies/<id>/`，规则见 [研究组织](studies/README.md)。
- 研究名是**数据不是代码**：根 [study.json](study.json) 指当前研究，`$ASSAY_STUDY` 覆盖。工具里不写默认值。
- 记录留在 `$DSH_HOME/harness-dispatcher/runs`，不复制、不改写；`records/` 全是派生，gitignore。
- 改宿主包只能是窗口：`--apply --expect patched` 开、`--revert --expect original` 关，关窗后宿主必须逐字节等于 npm 原件。
- 只改文件用编辑工具或字节操作，不经文本模式往返（会把 CRLF 写进去）。

## 常用命令（仪器层）

```bash
export ASSAY_SLOTS=<槽位根>                 # 需要槽位的脚本不猜默认根
python tools/record_index.py               # run 目录 -> records/index.jsonl
Rscript analysis/index_tables.R            # -> records/tables/{observations,conditions,calls}.csv
python tools/batch_plan.py --task <id> --k 6 --family <a,b> --verify
python tools/patch_host_notice.py --check
```

各脚本的职责与改后必验见 [记录层手册](tools/README.md)、[分析层手册](analysis/README.md)；研究自身的步骤见该研究的 README。

检查选择：改 `tools/` → `--help` 与一次真实调用；改 `studies/` → `verify_index` + `batch_plan --verify` + 该研究的表格断言；改 `.md` → 链接校验 + 换行校验。

## 验证快照（仪器层）

- 记录层：330 条 run 上 `verify_index` 3/3 通过；`index_tables.R` 出 330 观测 / 329 条件 / 2034 调用；索引 `index_schema=2`，带 `observed.tool_calls` 原文。
- `answer_json` 往返自检 321 条全等（零容差）；调用表行数 = 观测表 `tool_calls` 总和。
- 顺序：`order_fidelity` Spearman **+1.000**、零漂移；`audit_controls` PASS（17 个控制变量单值）。
- 交付：`check_delivery` 单一 `toolSchemaDigest` / `systemPrompt`，prompt 全匹配 plan。
- 宿主：`--check` 读 original，包目录只剩 `index.js` 与 `types/`；`audit_environment` RESULT: clean。
- 通道：`exposure_check` PASS。
- 研究的判定与效应数字 → 该研究的 [README](studies/workspace-name-cue/README.md)。

## 待办

- [ ] `letter` 2 臂：暂缓；k 按实测措辞离散度重算，现在定不了
- [ ] 跨模型复制：单一模型路径下语料先验与 cue 分不开
- [ ] `tools/check_delivery.py` 的 `--plan` 已必填；其余工具也应去掉隐式默认
- [ ] 给 `analysis/` 一个 R 侧环境锁（`renv.lock`），当前无版本锁定
- [ ] 补 CI 与本地钩子（L3 要求，暂缺）

## 活跃坑

- `harness_run` 的 `sealed` 住在 `harness` 对象里，不是顶层参数。传顶层会被**静默忽略**，被试看到宿主全部工具而不是 harness 的四个；`run.json` 里只有 `sealed=false` 与 `stimulus.fingerprint` 变了会露出，`harness.digest` 不变。
- 输出 schema 每次调用都得重新打一遍，键序漂移是**复发**故障（`034e7014` vs `6218479a`）→ [依据记录](.agents/notes/2026-11-12-schema-retyping.md)。每 12 条一次的 `check_delivery` 就是为它设的。
- 工作目录通知里的 `from` 是**会话根**，不是活的 cwd；`cd` 移不动它 → [依据记录](.agents/notes/2026-11-12-operator-path-leak.md)
- 位置效应**没有**复现：6 条上 ρ=−0.83，28 条上 ρ=+0.59。交错仍然要做，理由是"事后无法排除" → [决策记录](.agents/notes/2026-11-12-run-order-confound.md)
- `inputTokens` 是未缓存部分，命中缓存时读数小 8 倍；记账一律 `uncached + cacheRead`。
- harness 文件必须住 `~/.dsh/profiles/web/harness/`，裸模块名只在那里解析得到；`spec/` 里的源要同步过去。
- 槽位目录被清空会让历史记录变成悬空引用，且没有任何代码会报错。
- 槽位根不是常量：token 成本与 plan 里的绝对 cwd 都依赖它，所以 `batch_plan` / `cue_tokens` 要求 `$ASSAY_SLOTS`。
- **换行统一会改「输入字节」**。`arms.json` 进 `plan_id`，`ws-template/fixtures/*` 的字节进模板树哈希。对全仓跑 `--target lf --write` 会让 288 条 trial 的 `plan_id` 与模板哈希同时变。跑换行归一前必须排除这两处；模板里 `wells.csv` 是 CRLF，保持原样。
- **`ws-template/fixtures/` 的字节是输入**：模板树哈希记在每条槽位记录里，统一换行会让历史 trial 看起来来自另一个模板 → [研究 README](studies/workspace-name-cue/README.md#已知坑)
- `pathlib` 的 `write_text` 在 Windows 会把 `\n` 换成 CRLF——写 JSON / 状态一律用字节。

## 文档地图

- 用户入口 → [README](README.md)
- 架构与约束 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 研究组织规则、如何加第二个研究 → [studies/README.md](studies/README.md)
- 当前研究：问题是、结论、文件、怎么跑 → [studies/workspace-name-cue/](studies/workspace-name-cue/)
- 记录层手册 → [tools/README.md](tools/README.md)
- 分析层手册 → [analysis/README.md](analysis/README.md)
- 仪器层决定与依据 → [.agents/notes/](.agents/notes/)
