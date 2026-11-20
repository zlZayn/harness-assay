# The original five figures, redesigned for a second model. Small multiples and paired
# marks add the model dimension without changing any scale or counting trials twice.
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
  "DeepSeek-V4.1-Flash-1017" = "#3F5263",
  "Kimi-K3.1-Pro" = "#B5446E"
)
condition_levels <- c("plain", "py-eco", "software", "r-eco")
primary <- c("r-eco", "software")
source_caption <- assay_source("records/workspace-name-cue/{trials.csv,trials-kimi.csv}", "288 per model")

by_wording <- trials |>
  group_by(model, condition, wording) |>
  summarise(n = n(), r = sum(first_runtime == "R"), p_r = r / n, .groups = "drop")

# ==============================================================================
# 1. Condition estimates: model small-multiples, one shared 0-100% ruler.
# ==============================================================================
set.seed(20261121)
condition_draws <- by_wording |>
  group_by(model, condition) |>
  summarise(
    draws = list(map_dbl(seq_len(10000), \(i) mean(sample(p_r, replace = TRUE)))),
    .groups = "drop"
  ) |>
  mutate(
    lo = map_dbl(draws, \(d) quantile(d, 0.025)),
    hi = map_dbl(draws, \(d) quantile(d, 0.975)),
    mean_rate = map_dbl(draws, mean)
  )

p_contrast <- ggplot(condition_draws, aes(x = mean_rate, y = condition, colour = model)) +
  geom_jitter(
    data = by_wording,
    aes(x = p_r, y = condition),
    shape = 21, size = 1.5, stroke = 0.5, alpha = 0.55,
    position = position_jitter(width = 0, height = 0.12, seed = 20261121)
  ) +
  geom_segment(
    aes(x = lo, xend = hi, y = condition, yend = condition),
    linewidth = 3.2, alpha = 0.28, lineend = "round"
  ) +
  geom_point(size = 4) +
  facet_grid(cols = vars(model)) +
  scale_colour_manual(values = model_palette) +
  scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25), labels = label_percent()) +
  labs(
    title = "The R-package cue is strong in DeepSeek, weak in Kimi",
    subtitle = "Small points are one name's rate over six trials; large points are condition means and bars their 95% cluster-bootstrap intervals.",
    x = "share of trials whose first runtime was R",
    y = NULL,
    caption = source_caption
  ) +
  assay_theme() +
  theme(legend.position = "none")

# ==============================================================================
# 2. Wording ranks: paired dumbbells, not two independently ranked plots.
# ==============================================================================
rank_order <- by_wording |>
  filter(model == reference_name, condition %in% primary) |>
  arrange(p_r, wording) |>
  pull(wording) |>
  unique()
ranked <- by_wording |>
  filter(condition %in% primary) |>
  mutate(wording = factor(wording, levels = rank_order))

p_rank <- ggplot(ranked, aes(x = p_r, y = wording, colour = model)) +
  geom_line(aes(group = wording), colour = "#C9CDD2", linewidth = 0.65) +
  geom_point(size = 2.2) +
  facet_grid(rows = vars(condition), scales = "free_y", space = "free_y") +
  scale_colour_manual(values = model_palette) +
  scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25), labels = label_percent()) +
  labs(
    title = "Kimi's remaining R use is concentrated in a few names",
    subtitle = "Each point is one name's rate over six trials; a line joins the same name in the two models. No per-name interval is drawn.",
    x = "share of trials whose first runtime was R",
    y = NULL,
    caption = source_caption
  ) +
  assay_theme()

# ==============================================================================
# 3. Blocks: model trajectories of the same preregistered contrast.
# ==============================================================================
by_block <- trials |>
  group_by(model, round, condition) |>
  summarise(n = n(), r = sum(first_runtime == "R"), p_r = r / n, .groups = "drop") |>
  filter(condition %in% primary) |>
  select(model, round, condition, p_r) |>
  pivot_wider(names_from = condition, values_from = p_r) |>
  mutate(delta = `r-eco` - software)
write_csv(by_block, file.path(SUM, "cross-model-blocks.csv"))

p_blocks <- ggplot(by_block, aes(x = round, y = delta, colour = model, group = model)) +
  geom_hline(yintercept = 0, colour = "#AAB0B6", linetype = "dashed", linewidth = 0.5) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 2.7) +
  scale_colour_manual(values = model_palette) +
  scale_x_continuous(breaks = 1:6, labels = paste0("block ", 1:6)) +
  scale_y_continuous(limits = c(-0.02, 0.38), breaks = seq(0, 0.35, 0.1), labels = label_percent()) +
  labs(
    title = "The R-cue lead is steadier in DeepSeek than in Kimi",
    subtitle = "Each point is one complete 48-trial block's r-eco minus software R-rate; lines join the six blocks within each model.",
    x = NULL,
    y = "difference in R-use rate",
    caption = source_caption
  ) +
  assay_theme()

# ==============================================================================
# 4. Runtime mixtures: identical categories and denominators in model panels.
# ==============================================================================
mix <- trials |>
  mutate(kind = case_when(
    runtimes_seen == "R" ~ "R only",
    str_detect(runtimes_seen, fixed("+")) ~ "R and Python",
    runtimes_seen == "python" ~ "Python only",
    TRUE ~ "No runtime"
  )) |>
  mutate(kind = factor(kind, levels = c("R only", "R and Python", "Python only", "No runtime"))) |>
  count(model, condition, kind, .drop = FALSE) |>
  group_by(model, condition) |>
  mutate(share = n / 72) |>
  ungroup()
write_csv(mix, file.path(SUM, "cross-model-mixed.csv"))

p_mix <- ggplot(mix, aes(x = share, y = condition, fill = kind)) +
  geom_col(position = "stack", width = 0.78) +
  geom_text(
    data = mix |> filter(n > 0),
    aes(label = n),
    position = position_stack(vjust = 0.5),
    size = ASSAY_TYPE[["annot"]], family = ASSAY_MONO, colour = "#FFFFFF", show.legend = FALSE
  ) +
  facet_grid(cols = vars(model)) +
  scale_fill_manual(values = c(
    "R only" = "#8E2F4C",
    "R and Python" = "#C9869B",
    "Python only" = "#2E6F95",
    "No runtime" = "#B9BDC2"
  )) +
  scale_x_continuous(labels = label_percent()) +
  labs(
    title = "R is rare in Kimi, and usually arrives alone",
    subtitle = "Each trial is classified by every runtime named during it; each bar sums to that condition's 72 trials.",
    x = "share of trials within a model and condition",
    y = NULL,
    caption = source_caption
  ) +
  assay_theme()

# ==============================================================================
# 5. Effort: distributions by condition, with model as the visual dimension.
# ==============================================================================
effort <- trials |>
  select(model, condition, steps, tool_calls, out_tokens) |>
  pivot_longer(c(steps, tool_calls, out_tokens), names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric, levels = c("steps", "tool_calls", "out_tokens"), labels = c("steps", "tool calls", "out tokens")))

effort_medians <- effort |>
  group_by(model, condition, metric) |>
  summarise(median = median(value), q1 = quantile(value, 0.25), q3 = quantile(value, 0.75), .groups = "drop")
write_csv(effort_medians, file.path(SUM, "cross-model-effort.csv"))

p_effort <- ggplot(effort, aes(x = condition, y = value, colour = model, group = interaction(condition, model))) +
  geom_boxplot(position = position_dodge(width = 0.68), outlier.shape = NA, linewidth = 0.55) +
  geom_jitter(
    alpha = 0.16, size = 0.75,
    position = position_jitterdodge(jitter.width = 0.12, jitter.height = 0, dodge.width = 0.68, seed = 20261121)
  ) +
  facet_wrap(vars(metric), scales = "free_y", nrow = 1) +
  scale_colour_manual(values = model_palette) +
  labs(
    title = "Effort differs by model, but not by condition",
    subtitle = "Boxes show the middle half of trials; small points are individual trials. Panels have independent y scales.",
    x = NULL,
    y = NULL,
    caption = source_caption
  ) +
  assay_theme()

# ==============================================================================
# Typography and export gates.
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
  contrast = c(14.0, 7.5),
  rank = c(12.5, 10.0),
  blocks = c(12.0, 6.8),
  mixed = c(13.0, 7.5),
  effort = c(14.5, 7.5)
)
walk2(names(sizes), sizes, \(nm, sz) {
  ggsave(
    file.path(FIG, paste0("fig-", nm, ".png")),
    plots[[nm]],
    width = sz[[1]], height = sz[[2]], dpi = ASSAY_EXPORT$dpi, bg = ASSAY_EXPORT$bg
  )
})
cat("figures ->", FIG, "\n")
