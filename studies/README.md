# studies/ — 一个研究一个目录

每个子目录是一个完整的研究：它声明的输入、它的预注册、它的分析、它的产物。

## 为什么按研究分目录

`tools/` 与 `analysis/` 是**仪器**：能把 dispatcher 的 run 目录读成可计算的东西、能开工窗、能查交付字节。它们不知道任何研究存在。

一旦某个东西是「这一项研究特有的」——cue 词表、条件分组、真值、容差、预注册、派生变量口径——它就属于 `studies/<id>/`，不属于根目录。否则第二个研究会与第一个抢同一批文件，而冲突是静默的。

## 一个研究目录的约定

通用工具只认下面这些**键**（写在 `study.json` 里），不认任何具体研究的名字：

| 键 | 指向 | 谁读 |
|---|---|---|
| `arms` | 臂表 | `tools/batch_plan.py` |
| `tasks` | 题面目录 | `tools/batch_plan.py` |
| `template` | 工作区模板 | `tools/workspace.py`、两个 audit |

其余文件（`conditions.json`、`interpreters.json`、`prereg/`、`criteria/`、`analysis/`…）由该研究自己的脚本按相对路径读取。

## 当前用哪个

根目录的 [`study.json`](../study.json) 指一个，`$ASSAY_STUDY=<id>` 临时覆盖。**工具里不写默认值**——写死的默认值会在有第二个研究那天静默地指向错的那个。

## 现有的研究

| 研究 | 问的是什么 |
|---|---|
| [workspace-name-cue](workspace-name-cue/) | 工作目录名里的一个词，会不会改变 agent 挑哪个运行时 |

## 新增一个研究

1. 建目录，写 `study.json` 声明 `arms` / `tasks` / `template`。
2. 在根 `study.json` 里切过去，或用 `$ASSAY_STUDY`。
3. 这一项研究特有的脚本放它自己的 `analysis/`，产物落 `records/<id>/`。

仪器层不需要改一行。
