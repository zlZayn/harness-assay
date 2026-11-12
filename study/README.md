# study/ — 研究声明

这一层放**这一个研究特有**的东西：要跑什么、拿什么算对、词表是什么。换一个研究就换一份 `study/`，`tools/` 不用动。

## 内容

| 路径 | 是什么 | 谁读 |
|---|---|---|
| `expectations.json` | 已知识别关系的断言对（折叠 / 分开） | `tools/verify_index.py` |
| `criteria/<ver>.json` | 真值、容差、以及容差自己的已知漏洞 | `tools/grade.py` |
| `cue-arms.json` | 臂表：按实测 token 声明，含切分器与版本 | `tools/batch_plan.py`、`analysis/cue_tokens.py` |
| `lexicon.json` | 「出现在路径里就已经是 cue」的词 | `tools/exposure_check.py` |
| `tasks/<id>.json` | 题面 + output schema，**唯一来源** | `tools/batch_plan.py` |
| `ws-template/` | 工作区的唯一起点 | `tools/workspace.py` |

## 三条不变式

- **题面与 schema 只在这里写一次**。手打两遍必然不一致：属性顺序一变，交付的工具表就变，两个 arm 就不再可比。
- **容差写来源，不写感觉**。`criteria/*.json` 的 `_derivation` 指向怎么算出来的，`known_limits` 写它管不住什么。
- **臂表按实测声明，不追等长**。字符长度相等不意味着 token 成本相等；`cue-arms.json` 记切分器名与版本，并留下代理与宿主不一致的那一处。

## 变更影响路由

- 改 `criteria/*.json` → 用新 `criteria_id`；旧判定留在 `records/judgment/`，不覆盖。
- 改 `tasks/*.json` 的题面或 schema → 视为新任务，旧 run 不再与之可比；`batch_plan` 的 `prompt_sha` / `schema_sha` 会变。
- 改 `ws-template/` → `template_tree_sha` 变，此前所有槽位与该模板不再同源。
- 改 `lexicon.json` → 重跑 `exposure_check`，历史 run 的判定可能翻面。

工作约束见 [AGENTS.md](AGENTS.md)。
