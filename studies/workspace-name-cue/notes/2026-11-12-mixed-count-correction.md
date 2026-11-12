# 更正：混用条数的分子用错了

状态：生效

（依据类记录。起因是给"cue 改变的是语言还是候选集"补读数时算错一个分子，数字进了三处公开文本。）

## 背景

本轮补"它到底是改用 R，还是试一下 R"这一节，需要回答：以 R 开头的试次里，有多少同时也
用了 python。

写下的第一版是：

> 61 条以 R 开头的 trial 里，有 26 条同时点了 python。

**分子错了。** 26 是 `r-eco` 这一组的混用条数（26/72）。"以 R 开头且混用"的正确条数是
**56**。两个数来自两个不同的交叉表：一个是 `condition × mixed`，一个是
`first_runtime × mixed`。

错数字进了三处：提交 `d58cdfe` 的信息、[研究 README](../README.md)、以及
[结果记录](2026-11-12-cue-effect-result.md)。后两处已改；提交信息改不了，所以留这份记录。

## 结论

`records/workspace-name-cue/trials.csv` 上做 `first_runtime × mixed` 交叉：

| 第一步 | 次数 | 其中同时用了另一种 |
|---|---|---|
| R | 61 | **56（92%）** |
| python | 202 | **1（0.5%）** |
| none | 25 | 0 |

总计 57 条混用，与 `cue_effect.py` 报告的 `mixed-runtime count : 57` 对上。26 是其中
`r-eco` 一列，不是全部。

## 影响

- **结论方向不变，而且更强。** 56/61 = 92% 比 43% 更能说明"R 是被加进来的一步，不是替换掉
  的主语言"。主判定 `Δ_R` 与 p = 0.0002 完全不受影响——那个数的分母是各条件的 72 条，
  从来没用到这个交叉表。
- 三处文本已改到 56。图 `fig-mixed` 的标题随之改为"R arrives as an extra step; python
  arrives alone"，因为旧标题"a third of it comes with python alongside"虽然指的是
  `r-eco` 的 26/72（本身没错），但容易被读成"总体三分之一"，与 56/61 的读数指向不同。
- 提交 `d58cdfe` 的信息里仍写着 26/61。那是最初的错误陈述，保留可见，不靠改历史抹掉。

## 教训

**"按 X 分组算的占比"和"按 Y 分组的某个子集"不能在同一句话里互相顶替。** 它们看着像同一个
数，分母完全不同。凡出现这种混用，回到原始表重算一次，不要从上一张表里抓一个"看着像"的数字。

## 校验方式

```bash
Rscript -e 'library(dplyr);library(readr);
  t <- read_csv("records/workspace-name-cue/trials.csv", show_col_types=FALSE);
  print(t |> count(first_runtime, mixed))'
```

期望：R 行 `FALSE 5 / TRUE 56`，python 行 `FALSE 201 / TRUE 1`，none 行 `FALSE 25`。
