# workspace-name-cue

> 工作目录名里的一个词，会不会改变 agent 挑哪个运行时来计算。

## 结论

在 DeepSeek-V4.1-Flash-1017 上，`P(Y=R | r-eco) − P(Y=R | software)` = **+0.2639**（30/72 vs 11/72），措辞层面精确置换单侧 **p = 0.0002**。

| 条件 | 12 个措辞 | `P(Y=R)` |
|---|---|---|
| `r-eco` | dplyr ggplot knitr patchwork purrr readr rlang scales shiny stringr forcats | 30/72 = 0.4167 |
| `software` | ansible cilium consul etcd gitlab grafana istio jenkins kafka minio nginx prometheus | 11/72 = 0.1528 |

两边**都是软件项目名**，共享“像软件项目”的背景；词频、熟悉度和社区联想并未完全匹配。主对比区间 [+0.153, +0.389]，原批六轮均为正，零工具调用 0/288（降低整批凭记忆直接作答的担忧，但不能识别每条答案来源）。

**这条提升是“进入首次候选”，不是已证实的“更换主语言”。** 288 次里只点名 R 的有 **5 次**，且全部在 `r-eco` 组；以 R 标签开头的 61 条里，56 条（92%）在整个试次中还点名 Python，且这 56 条的首次调用本身就同时命中两者；以 Python 开头的 202 条里只有 1 条（0.5%）还点名 R。最终完成计算的运行时未记录，见 [fig-mixed](../../records/workspace-name-cue/figures/fig-mixed.png)。按条件算的混用率（`r-eco` 26/72 等）不能回答这个问题：它同时取决于该组有多少次先用了 R。

六对 pairwise 已补齐（[`cue_effect.py`](analysis/cue_effect.py) §3b）。`r-eco vs py-eco` 在 `P(Y=R)` 上是 +0.3611，p < 0.0001（43/2704156），支持包名类别之间的差异，但不能据此排除词频、熟悉度或量程位置的影响。完整依据、两次仪器故障、以及这批数据管不住什么 → [notes/2026-11-12-cue-effect-result.md](notes/2026-11-12-cue-effect-result.md)。

**跨模型复制没有以同等强度复现。** Kimi-K3.1-Pro 的主对比为 **7/72 vs 0/72，Δ=+0.0972，p=0.1087**；与原模型的 Δ 差为 **−0.1667**，配对措辞 bootstrap 95% 区间约 **[−0.3056，约 0.00]**。Kimi-K3.1-Pro 的 7 次首次 R 全部有 Rscript 执行调用，所以这是较弱且未达显著的同向信号，不是"只点名、没有执行调用"，也不能反过来说 cue 已被证明无效。见 [跨模型报告](REPORT.qmd)、[预注册](prereg/norris-r4-v1.json) 与 [依据记录](notes/2026-11-21-cross-model-replication.md)。

## 为什么叫这个名字

`workspace` 是这个仓库自己的词（`tools/workspace.py`、`ws-template`、记录里的 `workspace.cwd_name` / `cwd_injected`）。被操纵的是**那个名字的词汇内容**，它经由一条注入消息抵达、而不是经由题目——这正是仓库其它地方 `cue` 的意思。

名字只说明**暴露**，不说明结局：换一个结局变量可以复用同一套暴露，而不必继承这个目录。

## 文件

| 路径 | 是什么 | 谁读 |
|---|---|---|
| `study.json` | 清单：这个研究的 arms / tasks / template / 各声明文件在哪。**通用工具只认这个形状** | `tools/batch_plan.py`、`workspace.py`、两个 audit |
| [`REPORT.qmd`](REPORT.qmd) | **给人读的完整叙述**：问题、设计、结果、局限与结论；正文不手算，表格读取派生文件 | 人；先读这个 |
| [`REPORT.html`](REPORT.html) | 上者的渲染产物，自包含（图内嵌、无 CDN），离线可看 | 人；分享用 |
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
| `cue_persistence.R` | 生成多数派、位置、双命中、结局敏感性与秩相关派生表；报告读取位置和规则表，其余留作依据。写 `records/<id>/summary/*.csv`，报告只读不算 |
| `cue_tables.R` | 一行一个 trial 的整洁表 `trials.csv`，接上条件/分类/顺序/判定 |
| `cue_report.R` | 估计与作图（读 `trials.csv`） |
| `cue_cross_model.py` | 两模型分别计算后的配对措辞 bootstrap 与跨模型差值区间 |
| `cue_cross_model_figure.R` | 跨模型主对比总览图 |
| `cue_cross_model_figures.R` | 原五类图的双模型版本：小多图、成对哑铃、模型轨迹与分面 |
| `cue_eda_inspect.R` | 对一份 tidy 表做七步数据质量检查：结构、缺失、重复、频数、分布与相关性 |
| `cue_eda.R` | 跨模型描述性 EDA：运行时构成、实际工具序列、3-and-3 子组、位置趋势与逐名字模式；不改变主判定 |

### 图

六张：原五类图的双模型版本，加一张跨模型总览。产物在 `records/workspace-name-cue/figures/`（派生，不入库）。

| 图 | 回答什么 |
|---|---|
| `fig-contrast` | 差多少：四条件同一 0–100% 轴，小点=一个名字，粗点与横线=条件均值及 95% 聚类 bootstrap 区间 |
| `fig-rank` | 是类别还是单个名字：主对比 24 个名字的成对哑铃图；不逐个名字作推断 |
| `fig-blocks` | 是不是某一轮碰巧：六轮模型轨迹；DeepSeek-V4.1-Flash-1017 六轮均正，Kimi-K3.1-Pro 五正一零 |
| `fig-mixed` | R 是新增候选还是主语言替换：四条件的运行时组合；最终主语言未被记录 |
| `fig-effort` | 工作量分布：四条件共用纵轴，步数、工具调用和输出 token 分面；前两个面板底部以淡虚线标出 3 |
| `fig-cross-model` | 两模型四条件的首次 R 率总览：效应是否按原强度复现 |

不成图的维度（逐 trial 的 `round`×条件 24 格、missing 明细与额外 EDA）留在 `summary/` 和 `eda/` 派生表中：把表画成图只是换个形式，不是多一个信息。

## 跑一遍

```bash
export ASSAY_SLOTS=<槽位根>
Rscript analysis/index_tables.R                          # 仪器层三张表
Rscript studies/workspace-name-cue/analysis/cue_tables.R # 本研究的 trials.csv
Rscript studies/workspace-name-cue/analysis/cue_tables.R norris-r4-v1.json trials-kimi.csv
python  studies/workspace-name-cue/analysis/cue_effect.py
python  studies/workspace-name-cue/analysis/cue_effect.py --prereg studies/workspace-name-cue/prereg/norris-r4-v1.json --out records/workspace-name-cue/judgment/cue-effect-kimi.json
Rscript studies/workspace-name-cue/analysis/cue_persistence.R  # summary/*.csv
Rscript studies/workspace-name-cue/analysis/cue_persistence.R trials-kimi.csv summary-kimi
python  studies/workspace-name-cue/analysis/cue_cross_model.py  # 配对措辞 bootstrap 与对照表
Rscript studies/workspace-name-cue/analysis/cue_eda_inspect.R records/workspace-name-cue/trials.csv records/workspace-name-cue/eda/deepseek-inspector.md
Rscript studies/workspace-name-cue/analysis/cue_eda_inspect.R records/workspace-name-cue/trials-kimi.csv records/workspace-name-cue/eda/kimi-inspector.md
Rscript studies/workspace-name-cue/analysis/cue_eda.R       # 描述性 EDA，不进入主判定
Rscript studies/workspace-name-cue/analysis/cue_report.R
Rscript studies/workspace-name-cue/analysis/cue_cross_model_figure.R
Rscript studies/workspace-name-cue/analysis/cue_cross_model_figures.R  # 最终图均为双模型版本
cd studies/workspace-name-cue && quarto render REPORT.qmd   # 叙述报告，需先有 figures 与 summary/
```

报告的最终图由两个 `cue_cross_model_figure(s).R` 脚本生成，表格由 `cue_persistence.R` 与跨模型分析生成，新增 EDA 数字由 `cue_eda.R` 复算。渲染前必须运行对应脚本：缺图会渲染出裂图，缺表会让 `read.csv` 直接报错停下；新增文字结论则通过 EDA 对账检查，不能靠手工改写。

`REPORT.qmd` 里的图指向 `../../records/.../figures/*.png`，表读 `../../records/.../summary/*.csv`，路径都相对 qmd 文件本身；渲染结果 `REPORT.html` 把图内嵌成 base64，离开仓库也打得开。数学式以 MathML 输出（`html-math-method: mathml`），不加载 MathJax 或其他 CDN 资源。

产物分工：`records/index.jsonl` 与 `records/tables/*.csv` 是**仪器级**（覆盖这台机器上所有 run）；`records/workspace-name-cue/` 下才是**本研究**的 plan、judgment、ws、`trials.csv`、`summary/`、figures。

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
