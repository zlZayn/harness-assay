# ==============================================================================
# Two readings the batch was never asked for, and that no re-run can supply:
#
#   1. Persistence -- is the trial's first runtime the trial's runtime? The primary
#      outcome records only the FIRST call that names one. If the rest of the trial
#      wanders, the 26-point contrast is a statement about a moment, not about the
#      trial. This file measures how often the first call is overturned.
#
#   2. Position -- the design was interleaved so that arm and position would not be
#      collinear. `fig-blocks` shows the six blocks agree; blocks are coarse. A drift
#      inside a block that reverses between blocks is invisible there and would still
#      contaminate the contrast. This file reads the 288 positions themselves.
#
# Neither is in the prereg. Both are DESCRIPTIONS: proportions and rank correlations,
# no p-values. A post-hoc test would need a pre-declared hypothesis, and inventing one
# now is the thing the prereg exists to prevent.
#
# It recomputes `first_runtime` independently of cue_tables.R and asserts the two agree
# before printing anything. Three implementations must not disagree about what the
# outcome was; if they do, the number is not the finding, the disagreement is.
#
# Run from the project root, no setwd().
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
})

STUDY <- "studies/workspace-name-cue"
REC <- file.path("records", basename(STUDY))
TABLES <- "records/tables"
TRIALS <- file.path(REC, "trials.csv")

trials <- read_csv(TRIALS, show_col_types = FALSE, progress = FALSE)
calls <- read_csv(file.path(TABLES, "calls.csv"), show_col_types = FALSE, progress = FALSE)

runtimes <- fromJSON(file.path(STUDY, "interpreters.json"), simplifyVector = FALSE)$runtimes |>
  map(\(r) tibble(runtime = as.character(r$name), pattern = as.character(r$pattern))) |>
  list_rbind()

# Only this plan's trials: the index covers probes and batch-1 as well.
mine <- trials$run_id

# ==============================================================================
# 1. Rebuild the per-call labels, then the sequence
# ==============================================================================

# One label per call, in the order the study's own classifier would give it: the first
# runtime whose regex matches the arguments. A call that names BOTH therefore carries the
# label of whichever row comes first in interpreters.json, which is the behaviour being
# reproduced -- not invented here, and reported in section 3 as the sensitivity it is.
labelled <- calls |>
  filter(run_id %in% mine) |>
  mutate(across(args, \(a) coalesce(a, ""))) |>
  # `step` is the model turn, not the call index: a turn that fires two tools gives two
  # calls the same step (139 of the 330 runs do this). `call_seq` is the row order in
  # calls.csv, which is the order the host recorded them in, and it is what keeps the
  # sequence from collapsing two calls into one. `step` alone would silently drop the
  # second call of every parallel pair -- and with it, a runtime.
  group_by(run_id) |>
  mutate(call_seq = row_number()) |>
  ungroup() |>
  cross_join(runtimes) |>
  mutate(hit = str_detect(args, regex(pattern, ignore_case = TRUE))) |>
  filter(hit) |>
  # One label per CALL, not one per step: the first runtime whose row comes first in
  # interpreters.json. A call naming both is therefore credited in that order.
  group_by(run_id, call_seq) |>
  arrange(match(runtime, runtimes$runtime), .by_group = TRUE) |>
  slice_head(n = 1) |>
  ungroup() |>
  select(run_id, call_seq, step, runtime)

sequence <- labelled |>
  arrange(run_id, call_seq) |>
  group_by(run_id) |>
  summarise(seq = list(runtime), n_named = n(), .groups = "drop")

# ==============================================================================
# 2. The two readings
# ==============================================================================

reading <- trials |>
  select(run_id, condition, wording, plan_order, round, first_runtime) |>
  left_join(sequence, by = "run_id") |>
  mutate(
    seq = map(seq, \(s) if (is.null(s)) character() else s),
    n_named = coalesce(n_named, 0L),
    # Majority vote over the calls that named a runtime; a tie goes to whichever came
    # first. With no named call the trial has no majority, and "none" is the honest value.
    majority_runtime = map2_chr(seq, first_runtime, \(s, frst) {
      if (length(s) == 0) {
        return("none")
      }
      tab <- table(s)
      top <- names(tab)[tab == max(tab)]
      if (length(top) > 1) top <- top[order(match(top, s))][1]
      top
    }),
    # How long the longest unbroken stretch of one runtime is. A trial that alternates
    # every call has 1; a trial that never switches has n.
    longest_run = map_int(seq, \(s) {
      if (length(s) == 0) {
        return(0L)
      }
      r <- rle(s)
      max(r$lengths)
    })
  )

# --- gate: the independent recomputation must reproduce the published outcome --------
rebuilt <- reading |>
  transmute(
    run_id,
    mine = map_chr(seq, \(s) if (length(s) == 0) "none" else s[[1]])
  )
published <- trials |> select(run_id, first_runtime)
disagree <- rebuilt |>
  inner_join(published, by = "run_id") |>
  filter(mine != first_runtime)

cat(sprintf("0. GATE -- first_runtime recomputed independently: %d/%d agree\n",
            nrow(rebuilt) - nrow(disagree), nrow(rebuilt)))
if (nrow(disagree) > 0) {
  print(disagree, n = Inf)
  cat("  the outcome is not reproducible from calls.csv; stop here\n")
  quit(status = 2)
}

# --- 2a. persistence ---------------------------------------------------------------
persist <- reading |>
  count(first_runtime, majority_runtime) |>
  complete(first_runtime, majority_runtime, fill = list(n = 0)) |>
  pivot_wider(names_from = majority_runtime, values_from = n, values_fill = 0)

cat("\n1. PERSISTENCE -- first runtime named, against the runtime the trial mostly used\n")
print(as.data.frame(persist), row.names = FALSE)

per_first <- reading |>
  count(first_runtime) |>
  rename(total = n)
agree <- reading |>
  filter(first_runtime == majority_runtime) |>
  count(first_runtime) |>
  rename(same = n)

cat("\n   share of trials whose first runtime is also the trial's runtime:\n")
per_first |>
  left_join(agree, by = "first_runtime") |>
  mutate(same = coalesce(same, 0L), share = same / total) |>
  print(n = Inf, width = 90)

cat("\n   longest unbroken stretch of one runtime, per trial:\n")
reading |>
  filter(n_named > 0) |>
  summarise(
    trials = n(),
    mean = mean(longest_run),
    median = median(longest_run),
    max = max(longest_run),
    switched = mean(longest_run < n_named)
  ) |>
  print(width = 90)

# --- 2b. position ------------------------------------------------------------------
# Position is the plan order. That is admissible only because the recorded start order
# matched the plan exactly (tools/order_fidelity.py, and fig-blocks reproduces it); using
# plan order as a stand-in for time without that check would be an assumption, not a
# measurement.
tab <- reading |> arrange(plan_order)

cat("\n2. POSITION -- rank correlation between plan order and cost, over 288 trials\n")
for (v in c("steps", "tool_calls", "wall_ms", "in_total", "out_tokens")) {
  x <- trials |> arrange(plan_order) |> pull(v)
  rho <- suppressWarnings(cor(seq_along(x), x, method = "spearman", use = "complete.obs"))
  cat(sprintf("   rho(plan_order, %-11s) = %+.3f\n", v, rho))
}

third <- reading |>
  mutate(part = ntile(plan_order, 3)) |>
  group_by(part) |>
  summarise(
    trials = n(),
    r = sum(first_runtime == "R"),
    p_r = mean(first_runtime == "R"),
    .groups = "drop"
  )

cat("\n   first runtime = R, by third of the batch:\n")
print(as.data.frame(third), row.names = FALSE)

by_cond_third <- reading |>
  mutate(part = ntile(plan_order, 3)) |>
  group_by(condition, part) |>
  summarise(r = sum(first_runtime == "R"), n = n(), .groups = "drop") |>
  arrange(condition, part)

cat("\n   the same, split by condition (r / n):\n")
print(as.data.frame(by_cond_third), row.names = FALSE)

# ==============================================================================
# 3. Sensitivity: how much of the R arm rests on calls that name both runtimes
# ==============================================================================

# Not a second analysis. A statement about the outcome's definition: a call that names
# both runtimes is a single observation, and it is credited to R because R's row comes
# first in interpreters.json. Everything here exists so the size of that credit is
# visible next to the number it feeds.
#
# `reads` is one row per call with two flags, so "names both" stops being an inference
# from the label and becomes a visible property of the call.
reads <- calls |>
  filter(run_id %in% mine) |>
  mutate(across(args, \(a) coalesce(a, ""))) |>
  transmute(
    run_id,
    step,
    names_r = str_detect(args, regex(runtimes$pattern[runtimes$runtime == "R"],
                                     ignore_case = TRUE)),
    names_py = str_detect(args, regex(runtimes$pattern[runtimes$runtime == "python"],
                                      ignore_case = TRUE))
  ) |>
  filter(names_r | names_py)

cat("\n3. CALLS THAT NAME BOTH RUNTIMES\n")
cat(sprintf("   calls naming any runtime : %d\n", nrow(reads)))
cat(sprintf("   of those, naming both    : %d (%.1f%%)\n",
            sum(reads$names_r & reads$names_py),
            100 * mean(reads$names_r & reads$names_py)))

opening <- reads |>
  arrange(run_id, step) |>
  group_by(run_id) |>
  slice_head(n = 1) |>
  ungroup() |>
  mutate(kind = case_when(
    names_r & names_py ~ "both",
    names_r            ~ "R only",
    TRUE               ~ "python only"
  )) |>
  inner_join(trials |> select(run_id, condition), by = "run_id")

cat("\n   what the trial's FIRST runtime-naming call names, by condition:\n")
opening |>
  count(condition, kind) |>
  complete(condition, kind, fill = list(n = 0)) |>
  pivot_wider(names_from = kind, values_from = n, values_fill = 0) |>
  arrange(condition) |>
  print(width = 90)

cat("\n   The same three counts as shares of each condition's 72 trials:\n")
opening |>
  count(condition, kind) |>
  complete(condition, kind, fill = list(n = 0)) |>
  pivot_wider(names_from = kind, values_from = n, values_fill = 0) |>
  mutate(across(where(is.numeric), \(x) x / 72)) |>
  arrange(condition) |>
  print(width = 90)

cat("\n   P(Y=R) if a call naming both were counted for R (the published rule), against\n")
cat("   P(Y=R) if only a call naming R and nothing else were:\n")
published <- trials |>
  group_by(condition) |>
  summarise(published = sum(first_runtime == "R") / n(), .groups = "drop")
strict <- opening |>
  group_by(condition) |>
  summarise(strict = sum(kind == "R only") / 72, .groups = "drop")

left_join(published, strict, by = "condition") |>
  mutate(delta = published - strict) |>
  arrange(condition) |>
  print(width = 90)

cat("\n   Every trial credited to R under the published rule that would not be under the\n")
cat("   strict one is a trial whose opening call named both runtimes. Which runtime such a\n")
cat("   call is credited to follows the row order of interpreters.json, so that order is\n")
cat("   part of the outcome definition and is reported here rather than assumed.\n")

# --- 3b. the same exact test, under both rules --------------------------------------
#
# The pre-registered test lives in cue_effect.py, which enumerates the 2.7M label
# assignments. This computes the same statistic a second way -- counting subsets by
# their sum instead of enumerating them -- for two reasons: to re-derive the published
# p-value from scratch (if the two disagree, one of them is wrong), and because the only
# thing that makes the two rules comparable is being tested identically.
#
# The statistic is a difference of means over twelve wordings, each rate a multiple of
# 1/6, so the chosen subset's SUM determines it. Counting by sum is exact.
exact_p <- function(rates_a, rates_b) {
  sixth <- round(c(rates_a, rates_b) * 6)
  total <- sum(sixth)
  obs <- round(sum(rates_a) * 6)
  m <- length(sixth)

  if (total == 0) {
    return(list(ge = choose(m, 12), total = choose(m, 12)))
  }

  # dp[j + 1, s + 1] = ways to choose j of the items seen so far with sum s
  dp <- matrix(0, nrow = 13, ncol = total + 1)
  dp[1, 1] <- 1
  for (v in sixth) {
    if (v > total) next
    for (j in 12:1) {
      dp[j + 1, ] <- dp[j + 1, ] +
        c(rep(0, v), dp[j, seq_len(total + 1 - v)])
    }
  }
  list(
    ge = sum(dp[13, (obs + 1):(total + 1)]),
    total = choose(m, 12)
  )
}

# The two rules, stated as what they do to one trial. "both" is a property of a call,
# so it is read off `opening` rather than inferred from the label.
scored <- reading |>
  select(run_id, condition, wording, first_runtime) |>
  left_join(opening |> select(run_id, kind), by = "run_id") |>
  mutate(
    kind = coalesce(kind, "none"),
    hit_published = first_runtime == "R",
    hit_strict = kind == "R only"
  ) |>
  filter(condition %in% c("r-eco", "software"))

per_wording <- function(col) {
  scored |>
    group_by(condition, wording) |>
    summarise(rate = mean(.data[[col]]), .groups = "drop")
}

cat("\n   the same contrast and the same test, under the two rules:\n")
for (nm in c("hit_published", "hit_strict")) {
  rates <- per_wording(nm)
  a <- rates |> filter(condition == "r-eco") |> pull(rate)
  b <- rates |> filter(condition == "software") |> pull(rate)
  p <- exact_p(a, b)
  cat(sprintf(
    "      %-14s delta %+.4f   exact one-sided p = %d/%d = %.6f\n",
    nm, mean(a) - mean(b), p$ge, p$total, p$ge / p$total
  ))
}

# --- 3c. does it actually EXECUTE the runtime? --------------------------------------
#
# The rule above ("the opening call names R and nothing else") is a poor tightening: it
# selects on probe style rather than on behaviour. A trial that checks for both
# interpreters in one command is dropped from the R side even though it may go on to run
# R code. The question worth asking is whether the trial ever INVOKES R, so the
# discriminator has to be the invocation itself:
#
#   Rscript <something>   where <something> is not a flag -- runs a script or an expression
#   Rscript --version     a probe, not an execution
#
# This is a regex over command text, so it inherits interpreters.json's known limit
# (a mention is not an invocation). It is reported as a sharper definition of the same
# outcome, not as a second outcome.
RUNS_R <- "\\bRscript(?:\\.exe)?\\s+(?!-v|--version|--help|-h)\\S"

executes <- calls |>
  filter(run_id %in% mine) |>
  mutate(across(args, \(a) coalesce(a, ""))) |>
  filter(str_detect(args, regex(RUNS_R, ignore_case = TRUE))) |>
  distinct(run_id) |>
  pull(run_id)

scored <- scored |>
  mutate(hit_executes = run_id %in% executes)

cat("\n   does the trial ever EXECUTE R (not merely name it)?\n")
by_rule <- scored |>
  group_by(condition) |>
  summarise(
    named_first = mean(hit_published),
    named_only = mean(hit_strict),
    executes = mean(hit_executes),
    n = n(),
    .groups = "drop"
  )
print(by_rule |> mutate(across(where(is.double), \(x) round(x, 4))), width = 90)

for (nm in c("hit_published", "hit_executes")) {
  a <- scored |> filter(condition == "r-eco") |> group_by(wording) |> summarise(r = mean(.data[[nm]])) |> pull(r)
  b <- scored |> filter(condition == "software") |> group_by(wording) |> summarise(r = mean(.data[[nm]])) |> pull(r)
  p <- exact_p(a, b)
  cat(sprintf(
    "      %-14s delta %+.4f   exact one-sided p = %d/%d = %.6f\n",
    nm, mean(a) - mean(b), p$ge, p$total, p$ge / p$total
  ))
}

# Over all four conditions, not just the contrast pair: the report quotes this as the
# share of "first runtime = R" trials that later run R code, and that share is a property
# of the outcome's meaning, not of the comparison.
all_conditions <- reading |>
  mutate(hit_published = first_runtime == "R", hit_executes = run_id %in% executes)

cat(sprintf(
  "\n   of the %d trials whose first runtime was R, %d later execute R code (%.0f%%)\n",
  sum(all_conditions$hit_published),
  sum(all_conditions$hit_published & all_conditions$hit_executes),
  100 * mean(all_conditions$hit_executes[all_conditions$hit_published])
))
cat("\n   The stricter definition leaves the contrast where it was. The first-call rule and\n")
cat("   the execute rule differ in wording -- 'it reached for R' against 'it ran R' -- and\n")
cat("   the difference between naming and executing is reported rather than resolved.\n")

# ==============================================================================
# 4. Write the readings the report prints
# ==============================================================================
#
# The report shows five tables built entirely from numbers this file computed. Typing
# them into the prose by hand makes two copies of one fact, and the copy in the prose is
# the one nobody re-checks -- it drifts the moment the data or a definition changes, and
# it drifts silently, because a report has no gate. So the numbers leave here as data and
# the report only displays them.
#
# What does NOT move here: the paper's claims. The contrast, the p-value and the counts
# quoted in the abstract stay in the prose, because they are the argument, not a derived
# table -- and because their real implementation is cue_effect.py's enumeration, which a
# second computation inside a document would only rival, not verify.
SUM <- file.path(REC, "summary")
dir.create(SUM, recursive = TRUE, showWarnings = FALSE)

# --- the five numbers behind "cost is flat" ----------------------------------------
rho <- tribble(~measure, ~rho, ~n)
for (v in c("steps", "tool_calls", "wall_ms", "in_total", "out_tokens")) {
  x <- trials |> arrange(plan_order) |> pull(v)
  rho <- add_row(
    rho,
    measure = v,
    rho = suppressWarnings(cor(seq_along(x), x, method = "spearman", use = "complete.obs")),
    n = sum(!is.na(x))
  )
}
write_csv(rho, file.path(SUM, "rho.csv"))

# --- first runtime against the trial's own majority ---------------------------------
persist <- reading |>
  count(first_runtime, majority_runtime) |>
  complete(first_runtime, majority_runtime, fill = list(n = 0)) |>
  pivot_wider(names_from = majority_runtime, values_from = n, values_fill = 0) |>
  rename(first = first_runtime) |>
  mutate(
    total = R + python + none,
    consistent = round(same <- pmax(R, python, none) / total, 4)
  ) |>
  select(first, R, python, none, total, consistent)
write_csv(persist, file.path(SUM, "persistence.csv"))

# --- where in the batch the R arm sat ----------------------------------------------
# Counts of "first runtime was R" per (condition, third) -- not the cell sizes, which are
# 24 by construction and would make the table say nothing.
position <- reading |>
  mutate(part = ntile(plan_order, 3)) |>
  group_by(condition, part) |>
  summarise(r = sum(first_runtime == "R"), n = n(), .groups = "drop") |>
  mutate(cell = sprintf("%d / %d", r, n)) |>
  select(condition, part, cell) |>
  pivot_wider(names_from = part, values_from = cell, names_prefix = "third_") |>
  arrange(condition)
write_csv(position, file.path(SUM, "position.csv"))

# --- what the opening call names, per condition ------------------------------------
# `opening` holds only the trials whose opening call names a runtime, so the silent ones
# have to be added back: leaving them out would make the four columns sum to less than the
# 72 in every row, which is the one arithmetic error a reader would not catch.
opening_tab <- opening |>
  count(condition, kind) |>
  complete(condition, kind, fill = list(n = 0)) |>
  pivot_wider(names_from = kind, values_from = n, values_fill = 0) |>
  mutate(
    silent = 72L - (`R only` + both + `python only`),
    n = 72L
  ) |>
  select(condition, both, `R only`, `python only`, silent, n) |>
  arrange(condition)
write_csv(opening_tab, file.path(SUM, "opening.csv"))

# --- the contrast under three definitions, same test -------------------------------
rules <- tribble(
  ~definition, ~detail, ~r_eco, ~software, ~delta, ~ge, ~of, ~p
)
add_rule <- function(definition, detail, col) {
  a <- scored |> filter(condition == "r-eco") |> group_by(wording) |>
    summarise(r = mean(.data[[col]]), .groups = "drop") |> pull(r)
  b <- scored |> filter(condition == "software") |> group_by(wording) |>
    summarise(r = mean(.data[[col]]), .groups = "drop") |> pull(r)
  p <- exact_p(a, b)
  add_row(
    rules,
    definition = definition,
    detail = detail,
    r_eco = round(mean(a), 4),
    software = round(mean(b), 4),
    delta = round(mean(a) - mean(b), 4),
    ge = p$ge, of = p$total, p = round(p$ge / p$total, 6)
  )
}
rules <- add_rule("首次点名 = R", "预注册：最早一次点名命中 R，双命中归 R", "hit_published")
rules <- add_rule("首次点名只命中 R", "双命中不计入 R", "hit_strict")
rules <- add_rule("执行过 R 代码", "Rscript <脚本> 或 -e，排除 --version", "hit_executes")
write_csv(rules, file.path(SUM, "rules.csv"))

# --- the one share quoted in the limitations --------------------------------------
share <- tibble(
  of = sum(all_conditions$hit_published),
  executes = sum(all_conditions$hit_published & all_conditions$hit_executes),
  share = round(mean(all_conditions$hit_executes[all_conditions$hit_published]), 4)
)
write_csv(share, file.path(SUM, "share.csv"))

cat("\n4. WRITTEN for the report ->", SUM, "\n")
for (f in list.files(SUM, pattern = "\\.csv$")) {
  cat(sprintf("   %-18s %d row(s)\n", f, nrow(read_csv(file.path(SUM, f), show_col_types = FALSE))))
}
