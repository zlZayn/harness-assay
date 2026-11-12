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
Rscript analysis/index_tables.R                     # -> records/tables/{observations,conditions,calls}.csv
Rscript analysis/cue_tables.R                       # -> records/tables/trials.csv
Rscript analysis/cue_report.R                       # -> 估计 + records/figures/*.png
python tools/grade.py --criteria study/criteria/v1.json
python -X utf8 analysis/process_report.py           # 每个 trial 用了哪个解释器
python -X utf8 analysis/cue_effect.py               # prereg 声明的对比 + 精确置换
python tools/exposure_check.py --lexicon study/lexicon.json
python tools/batch_plan.py --task wells-meansd --k 7 --family lang --verify
python tools/patch_host_notice.py --check
```

需要槽位的脚本都要求 `$ASSAY_SLOTS`，它们不猜默认根（见下「活跃坑」）。

检查选择：改 `tools/` → 跑对应脚本的 `--help` 与一次真实调用；改 `study/` → `verify_index` + `batch_plan --verify`；改 `.md` → 链接校验。

## 验证快照

- 记录层：330 条 run 上 `verify_index` 3/3 通过；`index_tables.R` 出 330 观测 / 329 条件 / 2034 调用；索引 `index_schema=2`，带 `observed.tool_calls` 原文。
- 研究层表：`cue_tables.R` 出 `trials.csv` 288 行（= plan 行数），48 个措辞全部落在声明过的条件里；索引里另有 42 条属于批次 1 或探针，按范围排除并在输出里点名。
- 判定层：`answer-v1` 39 pass / 3 missing；`norris-v1` 282 pass / 6 missing，`observations_sha` 稳定。`answer_json` 往返自检 321 条全等。
- 过程层：批次 1 的 28 条全在臂表内；批次 2 的 288 条 `r-eco` R=30/72、`py-eco` python=66/72、`software` R=11/72、`plain` R=16/72；零工具调用 0/288。
- 对比：`P(Y=R | r-eco) − P(Y=R | software)` = **+0.2639**，措辞层面精确置换单侧 **p = 0.0002**；措辞层面 bootstrap 95% 区间 **[+0.153, +0.389]**，六个 block 同向，留一措辞全部仍 > 0。见 [依据记录](.agents/notes/2026-11-12-cue-effect-result.md)。
- 通道体检：PASS（288 条都在窗口内跑，通知不点名操作者路径）；更早 11 条仍是 FAIL 的历史记录。
- 交付字节：批次 2 两份子批里各漂过一次，都被每 12 条一次的 `check_delivery` 抓住并丢弃重跑；最终 288 条 `toolSchemaDigest` 单一（`6218479a`）、`systemPrompt` 单一（`75222986`）。
- 顺序：`order_fidelity` 在 288 条上 Spearman **+1.000**、零漂移、零逆序。
- 控制变量：`audit_controls` PASS，17 个控制变量单值、288 个不同路径/消息/`stimulus_id`。
- 宿主：`--check` 读 original，包目录只剩 `index.js` 与 `types/`；`audit_environment` RESULT: clean。
- 无 CI：本地即为全部验证。

## 待办

- [x] W5 第一批：`lang` 4 臂 × k=7 = 28 trial —— 已跑完，结论见 [依据记录](.agents/notes/2026-11-12-batch1-result.md)
- [x] W5 第二批：`norris-ols` 题，4 条件 × 12 措辞 × 6 重复 = 288 trial —— 已跑完，结论见 [依据记录](.agents/notes/2026-11-12-cue-effect-result.md)
- [ ] `letter` 2 臂：暂缓；k 按第二批实测的措辞离散度重算（r-eco sd 0.181 / software sd 0.111），现在定不了
- [ ] 跨模型复制：单一模型路径下 Python 语料先验与 cue 分不开，只有换模型重跑能分开
- [ ] 下游分析继续往 `cue_report.R` 加（只读 `trials.csv`）；要新字段先加到 `trials.csv`，别让下一个人回去解析 JSON
- [ ] 给 `analysis/` 一个 R 侧环境锁（`renv.lock`），当前无版本锁定
- [ ] 补 CI 与本地钩子（L3 要求，暂缺）

## 活跃坑

- 工作目录通知里的 `from` 是**会话根**，不是活的 cwd；`cd` 移不动它。想消掉只能开窗或换会话根 → [依据记录](.agents/notes/2026-11-12-operator-path-leak.md)
- 手打两份 schema = 两份 schema。键序一变，规范哈希看不见、宿主 `toolSchemaDigest` 看得见；**两处都错得一模一样时只有 `declared_vs_received` 看得见** → [依据记录](.agents/notes/2026-11-12-batch1-result.md)
- `harness_run` 的 `sealed` 住在 `harness` 对象里，不是顶层参数。传顶层会被**静默忽略**，被试看到宿主全部工具而不是 harness 的四个；`run.json` 里只有 `sealed=false` 与 `stimulus.fingerprint` 变了会露出，`harness.digest` 不变。
- 输出 schema 每次调用都得重新打一遍，键序漂移是**复发**故障（批次 2 又中一次，`034e7014` vs `6218479a`）。每 12 条一次的 `check_delivery` 就是为它设的，不要跳过。
- 位置效应**没有**复现：6 条上 ρ=−0.83，28 条上 ρ=+0.59。交错仍然要做，理由是"事后无法排除"，不是"已知有漂移" → [决策记录](.agents/notes/2026-11-12-run-order-confound.md)
- **选题不许看结局**。基线率是报告对象，不是选择对象 → [DESIGN.md](study/DESIGN.md)
- `inputTokens` 是未缓存部分，命中缓存时读数小 8 倍；记账一律 `uncached + cacheRead`。
- harness 文件必须住 `~/.dsh/profiles/web/harness/`，裸模块名只在那里解析得到；`spec/` 里的源要同步过去。
- 槽位目录被清空会让历史记录变成悬空引用，且没有任何代码会报错。
- 槽位根不是常量：token 成本与 plan 里的绝对 cwd 都依赖它，所以 `batch_plan` / `cue_tokens` 要求 `$ASSAY_SLOTS` 而不是猜一个。

## 文档地图

- 用户入口 → [README.md](README.md)
- 架构与约束 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 统计设计（估计量、禁忌、预注册）→ [study/DESIGN.md](study/DESIGN.md)
- 记录层手册 → [tools/README.md](tools/README.md)
- 分析层手册 → [analysis/README.md](analysis/README.md)
- 研究声明 → [study/README.md](study/README.md)
- 决策与依据 → [.agents/notes/](.agents/notes/)
