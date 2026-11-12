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
python tools/exposure_check.py --lexicon study/lexicon.json
python tools/batch_plan.py --task wells-meansd --k 5 --verify
python tools/patch_host_notice.py --check
```

检查选择：改 `tools/` → 跑对应脚本的 `--help` 与一次真实调用；改 `study/` → `verify_index` + `batch_plan --verify`；改 `.md` → 链接校验。

## 验证快照

- 记录层：12 条历史 run 上 `verify_index` 3/3 通过；`index_tables.R` 出 6 观测 / 5 条件。
- 判定层：`answer-v1` 6 pass；`answer-v2-strict` 3 pass / 3 fail，`observations_sha` 不变。
- 通道体检：最新一条 run 为 FAIL（宿主已还原、未开窗），说明 guard 会响。
- 跑批清单：30 pending / 0 problem，prompt 与 schema 各单值。
- 无 CI：本地即为全部验证。

## 待办

- [ ] W5 第一轮 cue 实验：6 臂 × k=5 = 30 trial
- [ ] 给 `analysis/` 一个 R 侧环境锁（`renv.lock`），当前无版本锁定
- [ ] 补 CI 与本地钩子（L3 要求，暂缺）

## 活跃坑

- 工作目录通知里的 `from` 是**会话根**，不是活的 cwd；`cd` 移不动它。想消掉只能开窗或换会话根 → [依据记录](.agents/notes/2026-11-12-operator-path-leak.md)
- `inputTokens` 是未缓存部分，命中缓存时读数小 8 倍；记账一律 `uncached + cacheRead`。
- harness 文件必须住 `~/.dsh/profiles/web/harness/`，裸模块名只在那里解析得到；`spec/` 里的源要同步过去。
- 槽位目录被清空会让历史记录变成悬空引用，且没有任何代码会报错。

## 文档地图

- 用户入口 → [README.md](README.md)
- 架构与约束 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 记录层手册 → [tools/README.md](tools/README.md)
- 分析层手册 → [analysis/README.md](analysis/README.md)
- 研究声明 → [study/README.md](study/README.md)
- 决策与依据 → [.agents/notes/](.agents/notes/)
