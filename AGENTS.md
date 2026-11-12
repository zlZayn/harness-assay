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

- 记录层：14 条历史 run 上 `verify_index` 3/3 通过；`index_tables.R` 出 14 观测 / 13 条件；索引 `index_schema=2`，带 `observed.tool_calls` 原文。
- 判定层：`answer-v1` 13 pass / 1 missing（那条 run 没有 events），`observations_sha` 稳定。
- 过程层：`process_report` 在合成索引上按手算值核对过；真数据里 14 条全是跑批前的探针，无一条属臂表。
- 通道体检：最新一条 run 为 FAIL（宿主已还原、未开窗），说明 guard 会响。
- 跑批清单：`lang` 4 臂 × k=7 = 28 pending / 0 problem，prompt 与 schema 各单值。
- 无 CI：本地即为全部验证。

## 待办

- [ ] W5 第一批：`lang` 4 臂 × k=7 = 28 trial（含主结局的读数）
- [ ] W5 第二批：`letter` 2 臂，k 由第一批的效应量决定，现在还定不了
- [ ] 给 `analysis/` 一个 R 侧环境锁（`renv.lock`），当前无版本锁定
- [ ] 补 CI 与本地钩子（L3 要求，暂缺）

## 活跃坑

- 工作目录通知里的 `from` 是**会话根**，不是活的 cwd；`cd` 移不动它。想消掉只能开窗或换会话根 → [依据记录](.agents/notes/2026-11-12-operator-path-leak.md)
- 同一条件的连续 run 里，结局随位置单调变化（wall ρ=−0.83、steps ρ=−0.90）；arm-major 会让臂与位置完全共线 → [决策记录](.agents/notes/2026-11-12-run-order-confound.md)
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
