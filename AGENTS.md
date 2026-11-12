# harness-assay — 维护索引

## 全局规则

- 设计与不可破坏的约束 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- `tools/` 不得出现研究特有的东西（arm 名、cue 词、通过标准、run id）；那些属于 `study/`。
- 记录留在 `$DSH_HOME/harness-dispatcher/runs`，不复制、不改写；`records/` 全是派生，gitignore。
- 改宿主包只能是窗口：`--apply --expect patched` 开、`--revert --expect original` 关，关窗后宿主必须逐字节等于 npm 原件。
- 只改文件用编辑工具或字节操作，不经文本模式往返（会把 CRLF 写进去）。

## 常用命令

```bash
python tools/record_index.py                        # run 目录 -> records/index.jsonl
python tools/verify_index.py --index records/index.jsonl --expect study/expectations.json
Rscript analysis/index_tables.R                     # -> records/tables/*.csv
python tools/grade.py --criteria study/criteria/v1.json
python -X utf8 analysis/process_report.py           # 每个 trial 用了哪个解释器
python tools/exposure_check.py --lexicon study/lexicon.json
python tools/batch_plan.py --task wells-meansd --k 7 --family lang --verify
python tools/patch_host_notice.py --check
```

需要槽位的脚本都要求 `$ASSAY_SLOTS`，它们不猜默认根（见下「活跃坑」）。

检查选择：改 `tools/` → 跑对应脚本的 `--help` 与一次真实调用；改 `study/` → `verify_index` + `batch_plan --verify`；改 `.md` → 链接校验。

## 验证快照

- 记录层：42 条 run 上 `verify_index` 3/3 通过；`index_tables.R` 出 42 观测 / 41 条件；索引 `index_schema=2`，带 `observed.tool_calls` 原文。
- 判定层：`answer-v1` 39 pass / 3 missing（3 条没交出结构化答案），`observations_sha` 稳定。
- 过程层：批次 1 的 28 条全在臂表内；R 仅出现在 `tidyverse` 臂（2/7），两中性臂 0/14。
- 通道体检：PASS（28 条都在窗口内跑，通知不点名操作者路径）；更早 11 条仍是 FAIL 的历史记录。
- 交付字节：`batch_plan --verify` 在批次 1 上 FAIL 过一次——1 条与其余 27 条的 `toolSchemaDigest` 不同，见`.agents/notes/2026-11-12-batch1-result.md`。
- 宿主：`--check` 读 original，包目录只剩 `index.js` 与 `types/`。
- 无 CI：本地即为全部验证。

## 待办

- [x] W5 第一批：`lang` 4 臂 × k=7 = 28 trial —— 已跑完，结论见 [依据记录](.agents/notes/2026-11-12-batch1-result.md)
- [ ] W5 第二批：`letter` 2 臂；k 按批次 1 的实测率重算（p₁≈0.29，不是规划时的 0.4）
- [ ] 重跑 `python`/`tidyverse` 的高 k 批次时，schema 必须按 `study/tasks/*.json` 的键序交付
- [ ] 给 `analysis/` 一个 R 侧环境锁（`renv.lock`），当前无版本锁定
- [ ] 补 CI 与本地钩子（L3 要求，暂缺）

## 活跃坑

- 工作目录通知里的 `from` 是**会话根**，不是活的 cwd；`cd` 移不动它。想消掉只能开窗或换会话根 → [依据记录](.agents/notes/2026-11-12-operator-path-leak.md)
- 手打两份 schema = 两份 schema。键序一变，规范哈希看不见、宿主 `toolSchemaDigest` 看得见 → [依据记录](.agents/notes/2026-11-12-batch1-result.md)
- 位置效应**没有**复现：6 条上 ρ=−0.83，28 条上 ρ=+0.59。交错仍然要做，理由是"事后无法排除"，不是"已知有漂移" → [决策记录](.agents/notes/2026-11-12-run-order-confound.md)
- `inputTokens` 是未缓存部分，命中缓存时读数小 8 倍；记账一律 `uncached + cacheRead`。
- harness 文件必须住 `~/.dsh/profiles/web/harness/`，裸模块名只在那里解析得到；`spec/` 里的源要同步过去。
- 槽位目录被清空会让历史记录变成悬空引用，且没有任何代码会报错。
- 槽位根不是常量：token 成本与 plan 里的绝对 cwd 都依赖它，所以 `batch_plan` / `cue_tokens` 要求 `$ASSAY_SLOTS` 而不是猜一个。

## 文档地图

- 用户入口 → [README.md](README.md)
- 架构与约束 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 记录层手册 → [tools/README.md](tools/README.md)
- 分析层手册 → [analysis/README.md](analysis/README.md)
- 研究声明 → [study/README.md](study/README.md)
- 决策与依据 → [.agents/notes/](.agents/notes/)
