# ==============================================================================
# What the batch says, and how much of it is an artefact.
#
# Reads `trials.csv` and nothing else. Every number printed here is a restatement or an
# estimate of the same 288 trials; the pre-registered test itself lives in
# `analysis/cue_effect.py`, which enumerates the exact permutation distribution instead of
# approximating it. This file answers the questions a permutation p-value does not:
#
#   - how wide is the difference, not just how unlikely under the null
#   - is it twelve names or one name
#   - does it survive being cut into six blocks
#   - did the cue change the language, or the amount of work
#
# Nothing here is a new test of the primary hypothesis. The interval is a cluster
# bootstrap over wordings, reported as a description of these 48 names; sampling the
# wordings back in is not a claim that they were drawn from a population of names.
#
# Run from the project root, no setwd().
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(forcats)
  library(ggplot2)
  library(scales)
})

trials <- read_csv("records/tables/trials.csv", show_col_types = FALSE, progress = FALSE)

FIG <- "records/figures"
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

# Two conditions are the primary contrast; the other two answer different questions.
PRIMARY <- c("r-eco", "software")
OUTCOME <- "R"

# The palette is fixed once so the same condition is the same colour in every figure.
PALETTE <- c("r-eco" = "#B5446E", "py-eco" = "#2E6F95",
             "software" = "#6B7A8F", "plain" = "#9C8B7A")

theme_assay <- function(base = 11) {
  theme_minimal(base_size = base) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold", size = base + 1),
      plot.subtitle = element_text(colour = "grey35"),
      plot.caption = element_text(colour = "grey45", hjust = 0),
      legend.position = "top",
      legend.title = element_blank()
    )
}

# ==============================================================================
# 1. Per condition
# ==============================================================================

by_condition <- trials |>
  group_by(condition) |>
  summarise(
    n          = n(),
    r          = sum(first_runtime == "R"),
    python     = sum(first_runtime == "python"),
    none       = sum(first_runtime == "none"),
    p_r        = r / n,
    p_used     = mean(used_runtime),
    p_pass     = mean(verdict == "pass"),
    med_wall_s = median(wall_ms) / 1000,
    med_tokens = median(out_tokens),
    .groups = "drop"
  ) |>
  arrange(match(condition, c("r-eco", "py-eco", "software", "plain")))

cat("1. PER CONDITION\n")
print(by_condition, n = Inf, width = 110)
cat("\n")

# ==============================================================================
# 2. Per wording -- the unit the test permutes
# ==============================================================================

by_wording <- trials |>
  group_by(condition, wording) |>
  summarise(n = n(), r = sum(first_runtime == "R"), p_r = r / n, .groups = "drop")

dispersion <- by_wording |>
  group_by(condition) |>
  summarise(wordings = n(), mean_rate = mean(p_r), sd_rate = sd(p_r),
            min_rate = min(p_r), max_rate = max(p_r), .groups = "drop")

cat("2. HOW MUCH THE WORDINGS DISAGREE -- this is what limits the batch\n")
print(dispersion, n = Inf, width = 110)
cat("\nA wide spread means the effect depends on which word was used, and the p-value\n")
cat("is a statement about these names rather than about names in general.\n\n")

# ==============================================================================
# 3. Cluster bootstrap over wordings
# ==============================================================================

rates_of <- function(cond) by_wording |> filter(condition == cond) |> pull(p_r)

r_rates  <- rates_of(PRIMARY[[1]])
sw_rates <- rates_of(PRIMARY[[2]])

observed <- mean(r_rates) - mean(sw_rates)

# The wording is the cluster, so the wording is what gets resampled. Resampling trials
# would shrink the interval by pretending six replicates of one name are six independent
# names, which is the same error the permutation test avoids.
set.seed(20261112)
boot <- map_dbl(seq_len(10000), \(i) {
  mean(sample(r_rates, replace = TRUE)) - mean(sample(sw_rates, replace = TRUE))
})
ci <- quantile(boot, c(0.025, 0.975))

cat("3. HOW WIDE IS IT -- cluster bootstrap over wordings, 10000 draws\n")
cat(sprintf("   %s %s: P(Y=%s) = %.4f\n", PRIMARY[[1]], paste0("(", length(r_rates), " wordings)"),
            OUTCOME, mean(r_rates)))
cat(sprintf("   %-17s: P(Y=%s) = %.4f\n", PRIMARY[[2]], OUTCOME, mean(sw_rates)))
cat(sprintf("   difference = %+.4f   95%% interval [%+.4f, %+.4f]\n",
            observed, ci[[1]], ci[[2]]))
cat(sprintf("   draws below zero: %d of %d\n", sum(boot <= 0), length(boot)))
cat("\n   A bootstrap interval is not a substitute for the pre-registered permutation\n")
cat("   p-value: it describes these 48 names, it does not test a hypothesis about names.\n\n")

# ==============================================================================
# 4. Is it twelve names or one name
# ==============================================================================

# Leave-one-wording-out is a READING of stability, not a filter. Dropping a word that
# behaved oddly and re-running the test would be a different analysis chosen after seeing
# the data, which the prereg forbids; reporting how much each word contributes is not.
loo <- map_dfr(seq_along(r_rates), \(i) {
  tibble(
    dropped = by_wording |> filter(condition == PRIMARY[[1]]) |> slice(i) |> pull(wording),
    diff    = mean(r_rates[-i]) - mean(sw_rates)
  )
}) |>
  arrange(diff)

cat("4. LEAVE-ONE-WORDING-OUT -- stability reading, not a filter\n")
cat(sprintf("   full contrast        %+.4f\n", observed))
cat(sprintf("   range across 12      %+.4f .. %+.4f\n", min(loo$diff), max(loo$diff)))
cat(sprintf("   every one still > 0  %s\n", all(loo$diff > 0)))
cat("   largest movers (dropping the word moves the contrast by):\n")
loo |>
  mutate(shift = diff - observed, abs_shift = abs(shift)) |>
  slice_max(abs_shift, n = 3) |>
  transmute(dropped, diff, shift) |>
  print(n = Inf, width = 90)
cat("\n")

# ==============================================================================
# 5. Six blocks -- the design was interleaved, so check the blocks agree
# ==============================================================================

by_round <- trials |>
  filter(condition %in% PRIMARY) |>
  group_by(round, condition) |>
  summarise(p_r = mean(first_runtime == "R"), n = n(), .groups = "drop") |>
  pivot_wider(names_from = condition, values_from = p_r) |>
  mutate(diff = .data[[PRIMARY[[1]]]] - .data[[PRIMARY[[2]]]])

cat("5. BY BLOCK -- position effects would show up as rounds disagreeing\n")
print(by_round, n = Inf, width = 90)
cat(sprintf("\n   all six blocks in the same direction: %s\n",
            all(by_round$diff > 0)))
cat("\n")

# ==============================================================================
# 6. Did it change the language, or the amount of work
# ==============================================================================

by_condition |>
  select(condition, n, p_r, p_used, p_pass, med_wall_s, med_tokens) |>
  print(n = Inf, width = 110)

cat("\n6. CORRECTNESS x RUNTIME -- secondary, never the primary claim\n")
trials |>
  count(first_runtime, verdict) |>
  pivot_wider(names_from = verdict, values_from = n, values_fill = 0) |>
  print(n = Inf, width = 90)
cat("\n")

# ==============================================================================
# 7. Figures
# ==============================================================================

# The dot plot: every wording as one point, so a single name carrying the whole effect
# would be visible as one outlier instead of hidden inside a summary.
p_wordings <- by_wording |>
  mutate(
    label = paste0(wording, " (", r, "/", n, ")"),
    label = fct_reorder(label, p_r),
    condition = factor(condition, levels = names(PALETTE))
  ) |>
  ggplot(aes(p_r, label, colour = condition)) +
  geom_segment(aes(x = 0, xend = p_r, yend = label), linewidth = 0.4, alpha = 0.35) +
  geom_point(size = 2.4) +
  facet_wrap(~condition, scales = "free_y", ncol = 4) +
  scale_colour_manual(values = PALETTE, guide = "none") +
  scale_x_continuous(labels = percent, limits = c(0, 1),
                     expand = expansion(mult = c(0.01, 0.10))) +
  labs(
    title = "Every wording is one point",
    subtitle = "P(the first runtime it reached for was R), six replicates per name",
    x = NULL, y = NULL,
    caption = paste("288 trials; each label carries the count behind its rate.",
                    "The spread inside a condition is why the test permutes wordings, not trials.")
  ) +
  theme_assay() +
  theme(panel.grid.major.y = element_blank())

ggsave(file.path(FIG, "fig-wordings.png"), p_wordings,
       width = 11, height = 6.5, dpi = 200)

# The interval: what the p-value does not say.
p_boot <- tibble(diff = boot) |>
  ggplot(aes(diff)) +
  geom_histogram(bins = 60, fill = PALETTE[["r-eco"]], colour = "white", linewidth = 0.2) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey30") +
  geom_vline(xintercept = observed, colour = "black", linewidth = 0.7) +
  annotate("label", x = observed, y = Inf, vjust = 1.4, hjust = -0.08,
           label = sprintf("observed %+.3f", observed), size = 3.2) +
  scale_x_continuous(labels = label_number(style_positive = "plus")) +
  labs(
    title = "The difference, resampled over wordings",
    subtitle = sprintf("95%% interval [%+.3f, %+.3f]; the dashed line is no difference",
                       ci[[1]], ci[[2]]),
    x = "P(Y=R | r-eco) minus P(Y=R | software)", y = "bootstrap draws",
    caption = "10000 draws, wordings resampled within condition, seed 20261112."
  ) +
  theme_assay()

ggsave(file.path(FIG, "fig-interval.png"), p_boot,
       width = 8, height = 4.5, dpi = 200)

# The blocks: the design was interleaved for a reason, so show that it paid.
p_rounds <- by_round |>
  select(round, all_of(PRIMARY)) |>
  pivot_longer(-round, names_to = "condition", values_to = "p_r") |>
  mutate(condition = factor(condition, levels = names(PALETTE))) |>
  ggplot(aes(round, p_r, colour = condition)) +
  geom_line(linewidth = 0.7, alpha = 0.7) +
  geom_point(size = 2.6) +
  scale_colour_manual(values = PALETTE) +
  scale_y_continuous(labels = percent) +
  scale_x_continuous(breaks = 1:6) +
  labs(
    title = "Six blocks, same direction each time",
    subtitle = "each block is a complete replicate of the design: 48 trials, every wording once",
    x = "block", y = "P(Y=R)",
    caption = "Interleaving is what makes this check possible at all."
  ) +
  theme_assay()

ggsave(file.path(FIG, "fig-blocks.png"), p_rounds,
       width = 8, height = 4.5, dpi = 200)

cat("figures ->", FIG, "\n")
cat("  ", paste(list.files(FIG, pattern = "\\.png$"), collapse = "\n   "), "\n")
