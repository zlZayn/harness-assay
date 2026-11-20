# One figure for the cross-model replication. It describes the two completed batches;
# the exact within-model tests live in cue_effect.py and the paired interval in
# cue_cross_model.py. No additional test is introduced here.
suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(ggplot2)
  library(scales)
})

source("analysis/theme_assay.R")

REC <- "records/workspace-name-cue"
reference <- read_csv(file.path(REC, "trials.csv"), show_col_types = FALSE, progress = FALSE)
candidate <- read_csv(file.path(REC, "trials-kimi.csv"), show_col_types = FALSE, progress = FALSE)
trials <- bind_rows(reference, candidate)

by_condition <- trials |>
  group_by(model, condition) |>
  summarise(n = n(), r = sum(first_runtime == "R"), rate = r / n, .groups = "drop") |>
  mutate(
    condition = factor(condition, levels = c("plain", "py-eco", "software", "r-eco")),
    model = factor(model, levels = c("DeepSeek-V4.1-Flash-1017", "Kimi-K3.1-Pro")),
    label_y = as.numeric(condition) + ifelse(model == "DeepSeek-V4.1-Flash-1017", 0.18, -0.18)
  ) |>
  arrange(condition, model)

summary_path <- file.path(REC, "summary", "cross-model-conditions.csv")
dir.create(dirname(summary_path), recursive = TRUE, showWarnings = FALSE)
write_csv(by_condition, summary_path)

pal <- c(
  "DeepSeek-V4.1-Flash-1017" = "#3F5263",
  "Kimi-K3.1-Pro" = "#B5446E"
)

p <- ggplot(by_condition, aes(x = rate, y = condition, colour = model, group = model)) +
  geom_line(aes(group = condition), colour = "#C9CDD2", linewidth = 0.8) +
  geom_point(size = 3.2) +
  geom_text(
    aes(y = label_y, label = paste0(r, "/", n), hjust = ifelse(model == "DeepSeek-V4.1-Flash-1017", 1.35, -0.35)),
    size = ASSAY_TYPE[["annot"]], family = ASSAY_MONO, show.legend = FALSE
  ) +
  scale_colour_manual(values = pal) +
  scale_x_continuous(
    limits = c(-0.04, 0.53),
    breaks = seq(0, 0.5, 0.1),
    labels = label_percent(accuracy = 1)
  ) +
  labs(
    title = "The R-package cue is much weaker in Kimi-K3.1-Pro",
    subtitle = "Each point is a condition's share of trials whose first named runtime was R; lines join the same condition across models.",
    x = "share of trials whose first runtime was R",
    y = NULL,
    caption = assay_source("records/workspace-name-cue/{trials.csv,trials-kimi.csv}", "288 per model")
  ) +
  assay_theme()

audit <- assay_audit_ok(p)
cat(sprintf(
  "cross-model typography: sizes %d/%d, families %d/%d, off-ladder %d\n",
  audit$sizes, ASSAY_TYPE_MAX, audit$families, ASSAY_FAMILY_MAX, nrow(audit$off_ladder)
))
if (!audit$ok) {
  print(audit$off_ladder, n = Inf)
  quit(status = 2)
}

fig_dir <- file.path(REC, "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
ggsave(
  file.path(fig_dir, "fig-cross-model.png"),
  p,
  width = 12,
  height = 6.8,
  dpi = ASSAY_EXPORT$dpi,
  bg = ASSAY_EXPORT$bg
)
cat("figure ->", file.path(fig_dir, "fig-cross-model.png"), "\n")
cat("summary ->", summary_path, "\n")
