# Five report figures with model as a paired visual dimension.
# Statistics and denominators are unchanged; this script controls presentation only.
suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(ggplot2)
  library(scales)
})

source("analysis/theme_assay.R")

# Export close to report display size. Geom text uses points, not ggplot's millimetres.
ASSAY_FONT <- "Microsoft YaHei"
ASSAY_TYPE <- c(title = 15, subtitle = 10.5, axis_title = 10.5,
                axis_text = 9.5, annot = 9, caption = 8)
ASSAY_EXPORT$dpi <- 300
ASSAY_EXPORT$bg <- "#F7F7F3"
theme_pub <- function(scale = 1) {
  assay_theme(ink = "#17211B", body = "#3D4741", grid = "#E1E2DA", scale = scale)
}
text_size <- function(role = "annot") ASSAY_TYPE[[role]] / .pt
strip_style <- theme(
  strip.background = element_rect(fill = "#EEEEE7", colour = NA),
  strip.text = element_text(margin = margin(5, 7, 5, 7))
)

REC <- "records/workspace-name-cue"
FIG <- file.path(REC, "figures")
SUM <- file.path(REC, "summary")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
dir.create(SUM, recursive = TRUE, showWarnings = FALSE)

reference_name <- "DeepSeek-V4.1-Flash-1017"
candidate_name <- "Kimi-K3.1-Pro"
reference <- read_csv(file.path(REC, "trials.csv"), show_col_types = FALSE, progress = FALSE)
candidate <- read_csv(file.path(REC, "trials-kimi.csv"), show_col_types = FALSE, progress = FALSE)
trials <- bind_rows(reference, candidate) |>
  mutate(
    model = factor(model, levels = c(reference_name, candidate_name)),
    condition = factor(condition, levels = c("plain", "py-eco", "software", "r-eco"))
  )

model_palette <- c(
  "DeepSeek-V4.1-Flash-1017" = "#275139",
  "Kimi-K3.1-Pro" = "#B5534E"
)
condition_labels <- c(
  "r-eco" = "R 包名", "software" = "独立软件名",
  "py-eco" = "Python 包名", "plain" = "英文地名/姓氏"
)
primary <- c("r-eco", "software")

by_wording <- trials |>
  group_by(model, condition, wording) |>
  summarise(n = n(), r = sum(first_runtime == "R"), p_r = r / n, .groups = "drop")

# ==============================================================================
# 1. Condition estimates: shared ruler, model small multiples.
# ==============================================================================
set.seed(20261121)
condition_draws <- by_wording |>
  group_by(model, condition) |>
  summarise(
    mean_rate = mean(p_r),
    draws = list(map_dbl(seq_len(10000), \(i) mean(sample(p_r, replace = TRUE)))),
    .groups = "drop"
  ) |>
  mutate(
    lo = map_dbl(draws, \(d) quantile(d, 0.025)),
    hi = map_dbl(draws, \(d) quantile(d, 0.975))
  )
write_csv(
  condition_draws |> select(-draws),
  file.path(SUM, "cross-model-contrast.csv")
)

p_contrast <- ggplot(condition_draws, aes(x = mean_rate, y = condition, colour = model)) +
  geom_jitter(
    data = by_wording,
    aes(x = p_r, y = condition),
    shape = 21, size = 1.35, stroke = 0.45, alpha = 0.60,
    position = position_jitter(width = 0, height = 0.11, seed = 20261121)
  ) +
  geom_segment(
    aes(x = lo, xend = hi, y = condition, yend = condition),
    linewidth = 2.5, alpha = 0.25, lineend = "round"
  ) +
  geom_point(size = 3.2) +
  facet_grid(cols = vars(model)) +
  scale_colour_manual(values = model_palette) +
  scale_y_discrete(labels = condition_labels) +
  scale_x_continuous(
    limits = c(0, 1), breaks = seq(0, 1, 0.25), labels = label_percent()
  ) +
  labs(
    title = "两个模型的 R 包名效应量不同",
    subtitle = "小点：单个名字的 6 次试次；粗点与横线：均值及 95% 聚类 bootstrap 区间",
    x = "首次点名 R 的比例", y = NULL,
    caption = "每模型 288 次试次；每条件 12 个名字"
  ) +
  theme_pub() + strip_style +
  theme(legend.position = "none", panel.grid.major.y = element_blank())

# ==============================================================================
# 2. Wording ranks: paired dumbbells within the two primary conditions.
# ==============================================================================
rank_order <- by_wording |>
  filter(model == reference_name, condition %in% primary) |>
  arrange(p_r, wording) |>
  pull(wording) |>
  unique()
ranked <- by_wording |>
  filter(condition %in% primary) |>
  mutate(
    wording = factor(wording, levels = rank_order),
    condition = factor(condition, levels = primary)
  )
write_csv(ranked, file.path(SUM, "cross-model-wordings.csv"))

p_rank <- ggplot(ranked, aes(x = p_r, y = wording, colour = model)) +
  geom_line(aes(group = wording), colour = "#C9CDC5", linewidth = 0.5) +
  geom_point(size = 1.9) +
  facet_wrap(vars(condition), ncol = 1, scales = "free_y", labeller = as_labeller(condition_labels)) +
  scale_colour_manual(values = model_palette) +
  scale_x_continuous(
    limits = c(0, 1), breaks = c(0, 0.5, 1), labels = label_percent()
  ) +
  labs(
    title = "Kimi-K3.1-Pro 的 R 信号集中于少数 R 包名",
    subtitle = "每点为一个名字的 6 次试次；线连接同一名字",
    x = "首次点名 R 的比例", y = NULL,
    caption = "仅展示主对比的 24 个名字；不逐个名字作推断"
  ) +
  guides(colour = guide_legend(nrow = 1, override.aes = list(size = 2.5))) +
  theme_pub() + strip_style +
  theme(panel.grid.major.y = element_blank(), legend.position = "top")

# ==============================================================================
# 3. Blocks: the same contrast in six complete rounds.
# ==============================================================================
by_block <- trials |>
  group_by(model, round, condition) |>
  summarise(n = n(), r = sum(first_runtime == "R"), p_r = r / n, .groups = "drop") |>
  filter(condition %in% primary) |>
  select(model, round, condition, p_r) |>
  pivot_wider(names_from = condition, values_from = p_r) |>
  mutate(delta = `r-eco` - software, delta_pp = 100 * delta)
write_csv(by_block, file.path(SUM, "cross-model-blocks.csv"))

p_blocks <- ggplot(by_block, aes(x = round, y = delta_pp, colour = model, group = model)) +
  geom_hline(yintercept = 0, colour = "#9AA198", linewidth = 0.55) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5) +
  scale_colour_manual(values = model_palette) +
  scale_x_continuous(breaks = 1:6) +
  scale_y_continuous(breaks = seq(0, 30, 10)) +
  coord_cartesian(ylim = c(-1, 36)) +
  labs(
    title = "六轮主对比的方向",
    subtitle = "每点为一轮；R 包名与独立软件名各 12 次试次",
    x = "轮次", y = "R 率差（百分点）",
    caption = "每模型 6 轮，共 288 次试次"
  ) +
  guides(colour = guide_legend(nrow = 1)) +
  theme_pub() +
  theme(panel.grid.major.x = element_blank(), legend.position = "top")

# ==============================================================================
# 4. Runtime mixtures: counts on a common 100% bar, sparse labels.
# ==============================================================================
mix <- trials |>
  mutate(kind = case_when(
    runtimes_seen == "R" ~ "仅 R",
    str_detect(runtimes_seen, fixed("+")) ~ "R + Python",
    runtimes_seen == "python" ~ "仅 Python",
    TRUE ~ "未点名"
  )) |>
  mutate(kind = factor(kind, levels = c("仅 R", "R + Python", "仅 Python", "未点名"))) |>
  count(model, condition, kind, .drop = FALSE) |>
  group_by(model, condition) |>
  mutate(share = n / 72) |>
  ungroup()
write_csv(mix, file.path(SUM, "cross-model-mixed.csv"))

p_mix <- ggplot(mix, aes(x = share, y = condition, fill = kind)) +
  geom_col(width = 0.68) +
  # Keep every segment in this layer so position_stack() uses the full bar.
  geom_text(
    aes(label = ifelse(n >= 5, as.character(n), ""), colour = kind),
    position = position_stack(vjust = 0.5),
    size = text_size(), family = ASSAY_MONO, show.legend = FALSE
  ) +
  facet_grid(cols = vars(model)) +
  scale_fill_manual(values = c(
    "仅 R" = "#B5534E", "R + Python" = "#C9B458",
    "仅 Python" = "#275139", "未点名" = "#D4D7D0"
  )) +
  scale_colour_manual(values = c(
    "仅 R" = "#FFFFFF", "R + Python" = "#17211B",
    "仅 Python" = "#FFFFFF", "未点名" = "#17211B"
  )) +
  scale_y_discrete(labels = condition_labels) +
  scale_x_continuous(expand = expansion(mult = c(0, 0))) +
  labs(
    title = "DeepSeek-V4.1-Flash-1017：R 多与 Python 同现",
    subtitle = "每条为 72 次试次；数字为试次数，过窄分段不标",
    x = NULL, y = NULL,
    caption = "每模型共 288 次试次"
  ) +
  guides(fill = guide_legend(nrow = 1)) +
  theme_pub() + strip_style +
  theme(
    panel.grid = element_blank(), legend.position = "top",
    axis.text.x = element_blank()
  )

# ==============================================================================
# 5. Effort: distributions without a second layer of noisy jitter.
# ==============================================================================
effort <- trials |>
  select(model, condition, steps, tool_calls, out_tokens) |>
  pivot_longer(c(steps, tool_calls, out_tokens), names_to = "metric", values_to = "value") |>
  mutate(metric = factor(
    metric, levels = c("steps", "tool_calls", "out_tokens"),
    labels = c("步数", "工具调用数", "输出 token")
  ))

effort_medians <- effort |>
  group_by(model, condition, metric) |>
  summarise(median = median(value), q1 = quantile(value, 0.25), q3 = quantile(value, 0.75), .groups = "drop")
write_csv(effort_medians, file.path(SUM, "cross-model-effort.csv"))

three_marks <- tibble(
  metric = factor(c("步数", "工具调用数"), levels = levels(effort$metric)),
  x = 3, y = 0.56, label = "3"
)

p_effort <- ggplot(effort, aes(x = value, y = condition, colour = model, group = interaction(condition, model))) +
  geom_rug(
    data = three_marks, aes(x = x), inherit.aes = FALSE, sides = "b",
    colour = "#A8AEA5", linetype = "dashed", linewidth = 0.45
  ) +
  geom_text(
    data = three_marks, aes(x = x, y = y, label = label), inherit.aes = FALSE,
    size = text_size("caption"), family = ASSAY_MONO, colour = "#7A8278"
  ) +
  geom_boxplot(
    position = position_dodge(width = 0.70), width = 0.60,
    outlier.shape = 21, outlier.size = 0.75, outlier.alpha = 0.30,
    linewidth = 0.48, staplewidth = 0.45
  ) +
  facet_wrap(vars(metric), scales = "free_x", nrow = 1) +
  scale_colour_manual(values = model_palette) +
  scale_y_discrete(labels = condition_labels) +
  labs(
    title = "Kimi-K3.1-Pro 多数流程为 3，少数试次明显更长",
    subtitle = "箱体为四分位距；底部淡虚线标出 3，三个面板横轴独立",
    x = NULL, y = NULL,
    caption = "每模型每条件 72 次试次"
  ) +
  guides(colour = guide_legend(nrow = 1)) +
  theme_pub() + strip_style +
  theme(panel.grid.major.y = element_blank(), legend.position = "top")

# ==============================================================================
# Typography gates and report-size export.
# ==============================================================================
plots <- list(
  contrast = p_contrast,
  rank = p_rank,
  blocks = p_blocks,
  mixed = p_mix,
  effort = p_effort
)
audits <- map(plots, assay_audit_ok)
walk2(names(audits), audits, \(nm, a) {
  cat(sprintf(
    "%-9s sizes %d/%d  families %d/%d  off-ladder %d\n",
    nm, a$sizes, ASSAY_TYPE_MAX, a$families, ASSAY_FAMILY_MAX, nrow(a$off_ladder)
  ))
})
if (any(map_lgl(audits, `[[`, "ok") == FALSE)) {
  walk(audits, \(a) if (nrow(a$off_ladder)) print(a$off_ladder, n = Inf))
  quit(status = 2)
}

sizes <- list(
  contrast = c(8.0, 4.8),
  rank = c(7.6, 8.6),
  blocks = c(7.6, 4.6),
  mixed = c(8.0, 4.8),
  effort = c(8.2, 4.6)
)
walk2(names(sizes), sizes, \(nm, sz) {
  ggsave(
    file.path(FIG, paste0("fig-", nm, ".png")), plots[[nm]],
    width = sz[[1]], height = sz[[2]], dpi = ASSAY_EXPORT$dpi,
    bg = ASSAY_EXPORT$bg, device = ragg::agg_png
  )
})
cat("figures ->", FIG, "\n")
