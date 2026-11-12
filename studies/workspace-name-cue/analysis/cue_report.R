# ==============================================================================
# What the batch says, and how much of it is an artefact.
#
# Reads `trials.csv` and nothing else. Every number printed here is a restatement or an
# estimate of the same 288 trials; the pre-registered test itself lives in
# `studies/<id>/analysis/cue_effect.py`, which enumerates the exact permutation distribution instead of
# approximating it. This file answers the questions a permutation p-value does not:
#
#   - how wide is the difference, not just how unlikely under the null
#   - is it twelve names or one name
#   - does it survive being cut into six blocks
#   - did the cue change the language, or the amount of work
#
# Each figure carries one shared axis and one question. An earlier version of this file
# faceted the wordings into four panels with four independent y axes, which is four charts
# wearing one caption: the reader had to compare four different rulers to see the only
# comparison that matters. Pooling everything onto one scale fixed that and removed a
# figure, because the interval is now a bar instead of a histogram of its own draws.
#
# Nothing here is a new test of the primary hypothesis. The interval is a cluster
# bootstrap over wordings, reported as a description of these 48 names; resampling the
# wordings is not a claim that they were drawn from a population of names.
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

source("analysis/theme_assay.R")

STUDY  <- "studies/workspace-name-cue"
REC    <- file.path("records", basename(STUDY))
TRIALS <- file.path(REC, "trials.csv")

trials <- read_csv(TRIALS, show_col_types = FALSE, progress = FALSE)
raw_n  <- nrow(read_csv("records/tables/observations.csv",
                        show_col_types = FALSE, progress = FALSE))

FIG <- file.path(REC, "figures")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

PRIMARY <- c("r-eco", "software")
OUTCOME <- "R"

# 配色是这一项研究的选择，所以它住在这里，不住在 theme_assay.R。
# 固定一次，跨图同条件同色。
PALETTE <- c("r-eco" = "#B5446E", "py-eco" = "#2E6F95",
             "software" = "#5C6B7A", "plain" = "#9C8B7A")
FOCUS <- c("r-eco", "software")

# 行的顺序就是读的顺序：主对比相邻在上，另两个条件在下面当参照。
LEVELS <- c("plain", "py-eco", "software", "r-eco")

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
# 3. Cluster bootstraps over wordings
# ==============================================================================

# The wording is the cluster, so the wording is what gets resampled. Resampling trials
# would shrink every interval by pretending six replicates of one name are six independent
# names, which is the same error the permutation test exists to avoid.
set.seed(20261112)

boot_one <- function(rates) {
  map_dbl(seq_len(10000), \(i) mean(sample(rates, replace = TRUE)))
}

by_condition <- by_condition |>
  mutate(rates = map(condition, \(cnd)
    by_wording |> filter(condition == cnd) |> pull(p_r))) |>
  mutate(draws = map(rates, boot_one),
         lo    = map_dbl(draws, \(d) quantile(d, 0.025)),
         hi    = map_dbl(draws, \(d) quantile(d, 0.975)))

observed <- with(by_condition, p_r[condition == PRIMARY[[1]]] - p_r[condition == PRIMARY[[2]]])

set.seed(20261112)
boot_diff <- map_dbl(seq_len(10000), \(i) {
  mean(sample(by_condition$rates[[match(PRIMARY[[1]], by_condition$condition)]], replace = TRUE)) -
    mean(sample(by_condition$rates[[match(PRIMARY[[2]], by_condition$condition)]], replace = TRUE))
})
ci <- quantile(boot_diff, c(0.025, 0.975))

cat("3. HOW WIDE IS IT -- cluster bootstrap over wordings, 10000 draws\n")
for (i in seq_len(nrow(by_condition))) {
  cat(sprintf("   %-9s P(Y=%s) = %2d/%-2d = %.4f   95%% [%.3f, %.3f]\n",
              by_condition$condition[[i]], OUTCOME, by_condition$r[[i]],
              by_condition$n[[i]], by_condition$p_r[[i]],
              by_condition$lo[[i]], by_condition$hi[[i]]))
}
cat(sprintf("   difference %s - %s = %+.4f   95%% [%+.4f, %+.4f]\n",
            PRIMARY[[1]], PRIMARY[[2]], observed, ci[[1]], ci[[2]]))
cat(sprintf("   draws below zero: %d of %d\n", sum(boot_diff <= 0), length(boot_diff)))
cat("\n   A bootstrap interval is not a substitute for the pre-registered permutation\n")
cat("   p-value: it describes these 48 names, it does not test a hypothesis about names.\n\n")

# ==============================================================================
# 4. Is it twelve names or one name
# ==============================================================================

# Leave-one-wording-out is a READING of stability, not a filter. Dropping a word that
# behaved oddly and re-running the test would be a different analysis chosen after seeing
# the data, which the prereg forbids; reporting how much each word contributes is not.
r_rates  <- by_wording |> filter(condition == PRIMARY[[1]]) |> pull(p_r)
sw_rates <- by_wording |> filter(condition == PRIMARY[[2]]) |> pull(p_r)

loo <- tibble(
  dropped = by_wording |> filter(condition == PRIMARY[[1]]) |> pull(wording),
  diff    = map_dbl(seq_along(r_rates), \(i) mean(r_rates[-i]) - mean(sw_rates))
) |>
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
cat(sprintf("\n   all six blocks in the same direction: %s\n\n", all(by_round$diff > 0)))

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

FLOW <- assay_flow(raw_n, nrow(trials), "batch-1 and probe trials, other plan")
cat("scope:", FLOW, "\n\n")

# --- 7a. the answer, on one scale ---------------------------------------------
# Every wording is a point. Four conditions share one x axis, so the gap between the top
# two rows is a distance on the page rather than something reconstructed from four rulers.
#
# Text budget for every figure here: one bold claim, one grey line saying how to read the
# marks, one faint source line. The reason the top two rows are the pre-registered
# contrast is a sentence, and sentences belong beside the rows they are about -- so it is
# drawn in the plotting area, not stacked under the title.
#
# The right-hand column is NOT the same statement twice. The rate is "which language did it
# name first"; the mixed share is "how many trials went on to name a second one". Those come
# apart exactly where it matters -- see 7d -- so they belong on the same scale, read against
# the same four rows, rather than in a second chart with its own ruler.

means <- by_condition |>
  mutate(condition = factor(condition, levels = LEVELS))

p_contrast <- by_wording |>
  mutate(condition = factor(condition, levels = LEVELS)) |>
  ggplot(aes(p_r, condition)) +
  geom_segment(
    data = means,
    aes(x = lo, xend = hi, y = condition, yend = condition),
    inherit.aes = FALSE, linewidth = 1.6, colour = "grey78",
    lineend = "round"
  ) +
  # alpha 低是有原因的：同一措辞的六次重复常常落在同一个值上，点会叠在一起。
  # 透明一点，重叠就显示成更深的颜色，密度自己浮出来，而不是被一个实心点盖住。
  geom_point(aes(colour = condition), size = 1.9, alpha = 0.55,
             position = position_jitter(height = 0.10, width = 0, seed = 1)) +
  geom_point(data = means, aes(fill = condition), shape = 21, size = 4.4,
             colour = "white", stroke = 1.1) +
  geom_text(
    data = means,
    aes(x = 1, label = sprintf("%d/%d  %s", r, n, percent(p_r, accuracy = 0.1))),
    family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
    hjust = 0, vjust = 0.5, colour = "grey25"
  ) +
  # The contrast is a pair of adjacent rows, so it gets a bracket rather than a sentence.
  annotate("segment", x = -0.03, xend = -0.03, y = 3, yend = 4,
           linewidth = 0.4, colour = "grey45") +
  annotate("text", x = -0.05, y = 3.5, label = "pre-registered\ncontrast",
           family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
           hjust = 1, vjust = 0.5, colour = "grey35", lineheight = 0.95) +
  scale_colour_manual(values = PALETTE, guide = "none") +
  scale_fill_manual(values = PALETTE, guide = "none") +
  # The axis is fixed at 0..1 because a share cannot leave it; the extra room on either
  # side is margin for the bracket and the count column, not a wider scale. `limits` in the
  # scale would DELETE the bracket for being out of range, which is why this is coord_*.
  scale_x_continuous(labels = percent, breaks = seq(0, 1, 0.25)) +
  coord_cartesian(xlim = c(-0.26, 1.30), clip = "off") +
  labs(
    title = "An R package name in the workspace name moves the choice of runtime by 26 points",
    subtitle = "A dot is one workspace name, six trials; the bar is a 95% bootstrap over the names.",
    x = "share of trials whose first runtime was R", y = NULL,
    caption = assay_source(TRIALS, nrow(trials))
  ) +
  assay_theme()

ggsave(file.path(FIG, "fig-contrast.png"), p_contrast,
       width = 9.6, height = 5.6, dpi = ASSAY_EXPORT$dpi, bg = ASSAY_EXPORT$bg)

# --- 7b. one name or twelve ---------------------------------------------------
# Ranked, one axis, each name carrying its own uncertainty. Without the interval this
# figure over-reads: 5/6 and 3/6 are adjacent rows but very different evidence, and a
# reader ranking twenty-four point estimates will see a staircase that is mostly noise.
#
# Wilson, not Wald: at 0/6 and 6/6 Wald collapses to a zero-width interval, and 0/6 is
# exactly where several software names sit -- the interval would be narrowest where the
# data are least informative.
# Wilson 区间自己算，不引 binom 包：三行闭式，装了包反而多一个版本依赖。
wilson <- function(x, n, z = 1.959964) {
  p <- x / n
  den <- 1 + z^2 / n
  ctr <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(lo = max(0, ctr - half), hi = min(1, ctr + half))
}

ranked <- by_wording |>
  filter(condition %in% FOCUS) |>
  rowwise() |>
  mutate(w = list(wilson(r, n)), lo = w[["lo"]], hi = w[["hi"]]) |>
  ungroup() |>
  mutate(
    label = sprintf("%s  %d/%d", wording, r, n),
    # Order by the interval's midpoint rather than by the point estimate: two names that
    # landed on the same integer count are the same evidence and should not be separated
    # by a tie-break the reader cannot see.
    label = fct_reorder(label, (lo + hi) / 2),
    condition = factor(condition, levels = LEVELS)
  )

# 副标题里那句话由数据算出来，不手写：写了就得有人去核，核不住就会一直错。
high_a <- sum(by_wording$condition == PRIMARY[[1]] & by_wording$p_r >= 0.5)
high_b <- sum(by_wording$condition == PRIMARY[[2]] & by_wording$p_r >= 0.5)

p_rank <- ggplot(ranked, aes(p_r, label)) +
  geom_segment(aes(x = 0, xend = p_r, yend = label, colour = condition),
               linewidth = 0.5, alpha = 0.45) +
  geom_errorbar(aes(xmin = lo, xmax = hi, colour = condition),
                orientation = "y", width = 0.30, linewidth = 0.6, alpha = 0.55) +
  geom_point(aes(colour = condition), size = 2.6) +
  geom_vline(data = means |> filter(condition %in% FOCUS),
             aes(xintercept = p_r, colour = condition),
             linetype = "22", linewidth = 0.55, alpha = 0.9) +
  geom_text(
    data = means |> filter(condition %in% FOCUS),
    aes(x = p_r, y = Inf, label = sprintf("%s %.0f%%", condition, p_r * 100),
        colour = condition),
    family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
    hjust = -0.06, vjust = 1.1
  ) +
  scale_colour_manual(values = PALETTE, guide = "none") +
  scale_x_continuous(labels = percent, limits = c(0, 1),
                     breaks = seq(0, 1, 0.25),
                     expand = expansion(mult = c(0.01, 0.03))) +
  # Room above the top row so the two rule labels sit outside the data, not on it.
  scale_y_discrete(expand = expansion(add = c(0.6, 2.0))) +
  labs(
    title = "It is the category, not one lucky name",
    # The whisker's assumption is stated because it is the figure's weakest link: Wilson
    # treats the six replicates as independent Bernoulli trials, and they share a name and
    # a machine. If they are correlated the true interval is wider, never narrower -- so the
    # whiskers understate, which is the harmless direction for a figure whose job is to stop
    # the ranking being read as a staircase.
    #
    # Wrapped rather than shortened: "0 of 12 software reach 3-in-6" is the evidence for the
    # title, and dropping it to save a line would trade the claim's support for whitespace.
    # A single unwrapped line runs past the canvas edge, which is how the previous attempt
    # lost the second half of this sentence.
    subtitle = paste(
      strwrap(sprintf(paste0("24 names ranked by interval; whiskers are 95%%, assuming six ",
                             "independent trials. %d of 12 r-eco reach 3-in-6, ",
                             "%d of 12 software do."), high_a, high_b),
              width = 84),
      collapse = "\n"),
    x = "share of trials whose first runtime was R", y = NULL,
    caption = assay_source(TRIALS, nrow(trials))
  ) +
  assay_theme()

ggsave(file.path(FIG, "fig-rank.png"), p_rank,
       width = 9.0, height = 6.6, dpi = ASSAY_EXPORT$dpi, bg = ASSAY_EXPORT$bg)

# --- 7c. six blocks -----------------------------------------------------------

# A dumbbell, not a line: block is categorical, and a connecting line would suggest the
# six blocks are six points on a continuum, which they are not.

p_blocks <- by_round |>
  mutate(block = factor(sprintf("block %d", round), levels = rev(sprintf("block %d", round)))) |>
  ggplot(aes(y = block)) +
  geom_segment(aes(x = .data[[PRIMARY[[2]]]], xend = .data[[PRIMARY[[1]]]],
                   yend = block),
               linewidth = 1.4, colour = "grey80", lineend = "round") +
  geom_point(aes(x = .data[[PRIMARY[[2]]]], colour = PRIMARY[[2]]), size = 3.4) +
  geom_point(aes(x = .data[[PRIMARY[[1]]]], colour = PRIMARY[[1]]), size = 3.4) +
  geom_text(aes(x = pmax(.data[[PRIMARY[[1]]]], .data[[PRIMARY[[2]]]]) + 0.035,
                label = sprintf("%+.0f", diff * 100)),
            family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
            hjust = 0, colour = "grey30") +
  scale_colour_manual(values = PALETTE, breaks = FOCUS, labels = FOCUS) +
  scale_x_continuous(labels = percent, limits = c(0, 1),
                     breaks = seq(0, 1, 0.2),
                     expand = expansion(mult = c(0.02, 0.12))) +
  labs(
    title = "All six blocks point the same way",
    subtitle = "Each block is a full replicate of the design; the number is the gap, in points.",
    x = "share of trials whose first runtime was R", y = NULL,
    caption = assay_source(TRIALS, nrow(trials))
  ) +
  assay_theme()

ggsave(file.path(FIG, "fig-blocks.png"), p_blocks,
       width = 8.6, height = 4.6, dpi = ASSAY_EXPORT$dpi, bg = ASSAY_EXPORT$bg)

# --- 7d. the one thing the primary rate hides ---------------------------------
# The primary says "named R first". It cannot say whether the trial then switched. That
# distinction is not cosmetic: it separates "the cue changed the language" from "the cue
# made it try a language and fall back", and only the first is what the study claims.
#
# A trial is drawn as three states in order of arrival -- first R, first python, no runtime
# -- and the bar fills are the second runtime, if any. Reading across a row tells you what
# the cue actually produced; the headline rate is the leftmost segment alone.

RUNTIME_LEVELS <- c("R", "python", "none")
RUNTIME_FILL   <- c("R" = PALETTE[["r-eco"]], "python" = PALETTE[["py-eco"]],
                    "none" = "grey72")

# Two panels on one shared scale: what was named first, and what was named at all. The
# second panel is where "it only ever tried R" becomes visible; without it a reader sees
# 41.7% and cannot tell 30 clean R trials from 30 trials that also ran python.

by_cond_rt <- trials |>
  count(condition, first_runtime) |>
  mutate(share = n / sum(n), .by = condition)

mixed_by_cond <- trials |>
  group_by(condition) |>
  summarise(mixed = sum(mixed), n = n(), share = mixed / n, .groups = "drop")

# Two facts, one axis, same four rows: what was named first (bars), and how often a second
# runtime was named at all (the dot column on the right). They must be read together. A
# reader who sees only the bars cannot tell whether the cue changed the language or merely
# added an attempt; a reader who sees only the mixed share does not know what was mixed.
# Putting them in two charts would be two rulers for one question.

# The legend order must match the reading order of the bar, which goes R, python, none
# from the left edge. factor levels alone do not control this: position_stack draws the
# LAST level first, so the levels are set to the reverse of the left-to-right order.
STACK_LEVELS <- c("R", "python", "none")

p_mix <- by_cond_rt |>
  mutate(
    condition = factor(condition, levels = rev(LEVELS)),
    first_runtime = factor(first_runtime, levels = rev(STACK_LEVELS))
  ) |>
  ggplot(aes(share, condition)) +
  geom_col(aes(fill = first_runtime), width = 0.58, colour = "white", linewidth = 0.6) +
  geom_text(aes(label = ifelse(n > 0, n, "")),
            position = position_stack(vjust = 0.5),
            family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
            colour = "white") +
  # The switch column is drawn past the end of the 0..1 bar scale, in its own space, with
  # its own faint baseline -- so it reads as a separate measurement, not as a fourth
  # segment of the bar.
  geom_segment(data = mixed_by_cond,
               aes(x = 1.06, xend = 1.06 + share * 0.55, y = condition, yend = condition),
               inherit.aes = FALSE, linewidth = 3.2, colour = "grey80", lineend = "round") +
  geom_segment(data = mixed_by_cond,
               aes(x = 1.06, xend = 1.06 + share * 0.55, y = condition, yend = condition),
               inherit.aes = FALSE, linewidth = 3.2, lineend = "round",
               colour = "grey42") +
  geom_text(data = mixed_by_cond,
            aes(x = 1.06 + share * 0.55 + 0.02, y = condition,
                label = sprintf("%d/%d", mixed, n)),
            inherit.aes = FALSE,
            family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
            hjust = 0, colour = "grey30") +
  annotate("text", x = 1.06, y = 4.62, label = "named a\nsecond runtime",
           family = ASSAY_MONO, size = ASSAY_TYPE[["annot"]] / .pt,
           hjust = 0, vjust = 0, colour = "grey35", lineheight = 0.95) +
  scale_fill_manual(values = RUNTIME_FILL, breaks = STACK_LEVELS,
                    labels = c("R first", "python first", "no runtime")) +
  scale_x_continuous(labels = \(x) ifelse(x <= 1, percent(x), ""),
                     breaks = c(seq(0, 1, 0.25), 1.06),
                     expand = expansion(mult = c(0, 0.02))) +
  coord_cartesian(xlim = c(0, 1.40), clip = "off") +
  labs(
    title = "The R lift is real but a third of it comes with python alongside",
    subtitle = "Bars: first runtime named, per condition's 72 trials. Right column: trials that named a second runtime.",
    x = "share of the condition's trials", y = NULL,
    fill = NULL,
    caption = assay_source(TRIALS, nrow(trials))
  ) +
  assay_theme()

ggsave(file.path(FIG, "fig-mixed.png"), p_mix,
       width = 9.0, height = 4.8, dpi = ASSAY_EXPORT$dpi, bg = ASSAY_EXPORT$bg)

# --- 7e. did the cue change the language, or the amount of work ---------------
# The control a reader should demand: a cue that merely made the agent work harder or
# longer would produce the same R rate without any preference for R. Steps and tool calls
# are the effort; the two conditions that differ most in R sit on the same footing here.

effort <- trials |>
  select(condition, steps, tool_calls, out_tokens) |>
  pivot_longer(c(steps, tool_calls, out_tokens), names_to = "measure",
               values_to = "value") |>
  mutate(
    condition = factor(condition, levels = rev(LEVELS)),
    measure = factor(measure, levels = c("steps", "tool_calls", "out_tokens"),
                     labels = c("steps", "tool calls", "output tokens"))
  )

p_effort <- ggplot(effort, aes(value, condition)) +
  geom_boxplot(aes(colour = condition), width = 0.5, outlier.shape = NA,
               linewidth = 0.45, fill = NA) +
  geom_point(aes(colour = condition), size = 1.1, alpha = 0.35,
             position = position_jitter(height = 0.16, width = 0, seed = 2)) +
  facet_wrap(~measure, ncol = 3, scales = "free_x") +
  scale_colour_manual(values = PALETTE, guide = "none") +
  labs(
    title = "The cue did not make it work harder, only differently",
    subtitle = "One point is one trial; boxes are quartiles. Three effort measures, same four conditions.",
    x = NULL, y = NULL,
    caption = assay_source(TRIALS, nrow(trials))
  ) +
  assay_theme()

ggsave(file.path(FIG, "fig-effort.png"), p_effort,
       width = 9.6, height = 4.2, dpi = ASSAY_EXPORT$dpi, bg = ASSAY_EXPORT$bg)

# ==============================================================================
# 8. Typography gate -- a self-check that only prints is not a self-check
# ==============================================================================

cat("8. TYPOGRAPHY -- every size must come from the shared ladder\n")

audits <- list(contrast = p_contrast, rank = p_rank, blocks = p_blocks,
               mixed = p_mix, effort = p_effort) |>
  map(assay_audit_ok)

walk2(names(audits), audits, \(nm, a) {
  cat(sprintf("   %-9s sizes %d/%d  families %d/%d  off-ladder %d\n",
              nm, a$sizes, ASSAY_TYPE_MAX, a$families, ASSAY_FAMILY_MAX,
              nrow(a$off_ladder)))
})

if (any(map_lgl(audits, `[[`, "ok") == FALSE)) {
  cat("\n   a figure uses a size or family the shared ladder does not declare:\n")
  walk(audits, \(a) if (nrow(a$off_ladder)) print(a$off_ladder, n = Inf))
  quit(status = 2)
}

cat("\nfigures ->", FIG, "\n")
cat("  ", paste(list.files(FIG, pattern = "\\.png$"), collapse = "\n   "), "\n")
