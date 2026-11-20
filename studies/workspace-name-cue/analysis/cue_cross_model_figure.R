# Cross-model overview. Statistics are computed elsewhere; this script only describes them.
suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(ggplot2)
  library(scales)
})

source("analysis/theme_assay.R")

# Report-size typography: export near the width at which the figure is displayed.
ASSAY_FONT <- "Microsoft YaHei"
ASSAY_TYPE <- c(title = 15, subtitle = 10.5, axis_title = 10.5,
                axis_text = 9.5, annot = 9, caption = 8)
ASSAY_EXPORT$dpi <- 300
ASSAY_EXPORT$bg <- "#F7F7F3"
theme_pub <- function(scale = 1) {
  assay_theme(ink = "#17211B", body = "#3D4741", grid = "#E1E2DA", scale = scale)
}
text_size <- function(role = "annot") ASSAY_TYPE[[role]] / .pt

REC <- "records/workspace-name-cue"
reference <- read_csv(file.path(REC, "trials.csv"), show_col_types = FALSE, progress = FALSE)
candidate <- read_csv(file.path(REC, "trials-kimi.csv"), show_col_types = FALSE, progress = FALSE)
trials <- bind_rows(reference, candidate)

reference_name <- "DeepSeek-V4.1-Flash-1017"
candidate_name <- "Kimi-K3.1-Pro"
condition_labels <- c(
  "r-eco" = "R 包名", "software" = "独立软件名",
  "py-eco" = "Python 包名", "plain" = "英文地名/姓氏"
)
model_palette <- c(
  "DeepSeek-V4.1-Flash-1017" = "#275139",
  "Kimi-K3.1-Pro" = "#B5534E"
)

by_condition <- trials |>
  group_by(model, condition) |>
  summarise(n = n(), r = sum(first_runtime == "R"), rate = r / n, .groups = "drop") |>
  mutate(
    condition = factor(condition, levels = c("plain", "py-eco", "software", "r-eco")),
    model = factor(model, levels = c(reference_name, candidate_name)),
    label_y = as.numeric(condition) + ifelse(model == reference_name, 0.20, -0.20)
  ) |>
  arrange(condition, model)

summary_path <- file.path(REC, "summary", "cross-model-conditions.csv")
dir.create(dirname(summary_path), recursive = TRUE, showWarnings = FALSE)
write_csv(by_condition |> select(-label_y), summary_path)

p <- ggplot(by_condition, aes(x = rate, y = condition, colour = model, group = model)) +
  geom_line(aes(group = condition), colour = "#C9CDC5", linewidth = 0.65) +
  geom_point(size = 2.8) +
  geom_text(
    aes(y = label_y, label = paste0(r, "/", n)),
    size = text_size(), family = ASSAY_MONO, show.legend = FALSE
  ) +
  scale_colour_manual(values = model_palette) +
  scale_y_discrete(labels = condition_labels) +
  scale_x_continuous(
    breaks = seq(0, 0.4, 0.1), labels = label_percent(accuracy = 1),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  coord_cartesian(xlim = c(-0.025, 0.47)) +
  labs(
    title = "R 包名效应在 Kimi 中较弱",
    subtitle = "每点汇总 72 次试次；数字为首次 R 次数，线连接同一条件",
    x = "首次点名 R 的比例", y = NULL,
    caption = "两个模型各 288 次试次"
  ) +
  guides(colour = guide_legend(nrow = 1, override.aes = list(size = 3))) +
  theme_pub() +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position = "top",
    plot.margin = margin(12, 16, 10, 12)
  )

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
  file.path(fig_dir, "fig-cross-model.png"), p,
  width = 7.6, height = 4.8, dpi = ASSAY_EXPORT$dpi,
  bg = ASSAY_EXPORT$bg, device = ragg::agg_png
)
cat("figure ->", file.path(fig_dir, "fig-cross-model.png"), "\n")
cat("summary ->", summary_path, "\n")
