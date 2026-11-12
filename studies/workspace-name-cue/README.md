# workspace-name-cue

> 工作目录名里的一个词，会不会改变 agent 挑哪个运行时来计算。

## 结论

`P(Y=R | r-eco) − P(Y=R | software)` = **+0.2639**（30/72 vs 11/72），措辞层面精确置换单侧 **p = 0.0002**。

| 条件 | 12 个措辞 | `P(Y=R)` |
|---|---|---|
| `r-eco` | dplyr ggplot knitr patchwork purrr readr rlang scales shiny stringr forcats | 30/72 = 0.4167 |
| `software` | ansible cilium consul etcd gitlab grafana istio jenkins kafka minio nginx prometheus | 11/72 = 0.1528 |

两边**都是软件项目名**，所以"像不像软件项目"被固定住，只有"是不是 R"在变。区间 [+0.153, +0.389]，六个 block 全部同向，零工具调用 0/288（不是在背答案）。

**这条提升里有一部分是"试一下"，不是"改用"。** 61 条首用 R 的 trial 中 26 条同时点了 python，而 202 条首用 python 的里只有 1 条回头用 R。按条件：`r-eco` 26/72、`plain` 16/72、`software` 11/72、`py-eco` 4/72。所以主结论应读成"cue 把 R 提进了候选"，不是"cue 把语言换掉了"；两者的区别见 [fig-mixed](../../records/workspace-name-cue/figures/fig-mixed.png)。

六对 pairwise 已补齐（[`cue_effect.py`](analysis/cue_effect.py) §3b）。`r-eco vs py-eco` 在 `P(Y=R)` 上是 +0.3611，p < 0.0001（43/2704156），所以效应不是"软件味"带来的。完整依据、两次仪器故障、以及这批数据管不住什么 → [notes/2026-11-12-cue-effect-result.md](notes/2026-11-12-cue-effect-result.md)。

## 为什么叫这个名字

`workspace` 是这个仓库自己的词（`tools/workspace.py`、`ws-template`、记录里的 `workspace.cwd_name` / `cwd_injected`）。被操纵的是**那个名字的词汇内容**，它经由一条注入消息抵达、而不是经由题目——这正是仓库其它地方 `cue` 的意思。

名字只说明**暴露**，不说明结局：换一个结局变量可以复用同一套暴露，而不必继承这个目录。

## 文件

| 路径 | 是什么 | 谁读 |
|---|---|---|
| `study.json` | 清单：这个研究的 arms / tasks / template / 各声明文件在哪。**通用工具只认这个形状** | `tools/batch_plan.py`、`workspace.py`、两个 audit |
| [`DESIGN.md`](DESIGN.md) | 统计设计：估计量、三条禁忌、量程受限、容差推导 | 人；改设计前必读 |
| `arms.json` | 臂表：按实测 token 声明，含切分器与版本 | `batch_plan`、`cue_tokens` |
| `conditions.json` | 四条件 × 12 措辞，每条路径恰好 11 token | `cue_tokens.py`、`cue_effect.py`、`cue_tables.R` |
| `interpreters.json` | 「哪段命令文本算用了哪个运行时」 | `process_report`、`cue_tables.R`、`cue_effect.py` |
| `lexicon.json` | 「出现在路径里就已经是 cue」的词 | `tools/exposure_check.py` |
| `features.json` | 分析变量口径：每列怎么定义、由什么派生、**看不见什么** | `cue_tables.R`（双向断言） |
| `expectations.json` | 已知识别关系的断言对 | `tools/verify_index.py` |
| `prereg/<id>.json` | 开跑前写死：题、臂、措辞、k、对比、判定规则、`plan_id` | 人；跑批前必读，跑完必对照 |
| `criteria/<id>.json` | 真值、容差、以及容差自己的已知漏洞 | `tools/grade.py` |
| `tasks/<id>.json` | 题面 + output schema，**唯一来源** | `tools/batch_plan.py` |
| `ws-template/` | 工作区的唯一起点 | `tools/workspace.py` |
| `analysis/` | 本研究的分析脚本，见下 | — |
| `notes/` | 本研究的依据记录 | 人 |

### analysis/

| 文件 | 职责 |
|---|---|
| `cue_tokens.py` | 量路径 token 成本，生成 `arms.json`（需 `tiktoken`） |
| `cue_tokens_check.py` | 代理切分器 vs 宿主计数器 |
| `exposure_report.py` | 那次操纵到底发生了没有 |
| `process_report.py` | 逐 trial 的运行时分类，按臂汇总（只描述，不出 p 值） |
| `cue_effect.py` | 执行 prereg 声明的对比：措辞层面精确置换，穷举 C(n,k) |
| `cue_tables.R` | 一行一个 trial 的整洁表 `trials.csv`，接上条件/分类/顺序/判定 |
| `cue_report.R` | 估计与作图（读 `trials.csv`） |

### 图

五张，各回答 permutation p 值回答不了的一个问题。产物在 `records/workspace-name-cue/figures/`（派生，不入库）。

| 图 | 回答什么 |
|---|---|
| `fig-contrast` | 差多少：四条件同一 0–1 轴，点=一个措辞，粗点=条件均值，灰条=95% bootstrap |
| `fig-rank` | 是类别还是一个名字：24 个措辞排序 + 各自 Wilson 95% 区间 |
| `fig-blocks` | 是不是某一批碰巧：六个 block 的哑铃，方向全部同向 |
| `fig-mixed` | 提升是"改用"还是"试一下"：首次运行构成 + 混用比例同轴 |
| `fig-effort` | 是不是只是更用力：steps / tool calls / out tokens 三视图 |

不成图的维度（逐 trial 的 `round`×条件 24 格、6 条 missing 明细）留在正文表里：把表画成图只是换个形式，不是多一个信息。

## 跑一遍

```bash
export ASSAY_SLOTS=<槽位根>
Rscript analysis/index_tables.R                          # 仪器层三张表
Rscript studies/workspace-name-cue/analysis/cue_tables.R # 本研究的 trials.csv
python  studies/workspace-name-cue/analysis/cue_effect.py
Rscript studies/workspace-name-cue/analysis/cue_report.R
```

产物分工：`records/index.jsonl` 与 `records/tables/*.csv` 是**仪器级**（覆盖这台机器上所有 run）；`records/workspace-name-cue/` 下才是**本研究**的 plan、judgment、ws、`trials.csv`、figures。

## 已知坑

- **`ws-template/fixtures/` 的字节是输入**。模板树哈希 `3850ab47762861f4` 记在每条槽位记录里，统一换行会让 288 条 trial 看起来来自另一个模板，`audit_controls` 会 FAIL。那三个 CSV 保持原样（`wells.csv` 是 CRLF）。
- **`arms.json` 由 `cue_tokens.py` 生成**，不是手写。手改会被下次生成覆盖，且 `plan_id` 会变。
- **`prereg/` 不能原地改**。改了 `plan_id` 就变，旧 prereg 是另一份声明，另开文件。
- **`cue_effect.py` 与 `cue_tables.R` 各算一遍 `first_runtime`**，是故意的：两套实现必须对上才报数（当前 61 / 202 / 25）。

## 三条不变式

- **题面与 schema 只在这里写一次**。手打两遍必然不一致：属性顺序一变，交付的工具表就变，两个 arm 就不再可比。
- **容差写来源，不写感觉**。`criteria/*.json` 的 `_derivation` 指向怎么算出来的，`known_limits` 写它管不住什么。
- **派生变量先声明再实现**。`features.json` 与 `trials.csv` 双向断言，代码里多一列没声明的就退 2。

改 [`DESIGN.md`](DESIGN.md) 的估计量或禁忌 = 换实验；改 `prereg/` 或它声明的任一输入 → `plan_id` 变，旧 prereg 另开文件不原地改；改 `criteria/` → 换 `criteria_id`；改 `tasks/` 或 `ws-template/` → 旧 run 不再可比。**选题不许看结局**，基线率是报告对象，不是选择对象。
