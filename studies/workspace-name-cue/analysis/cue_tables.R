# ==============================================================================
# One tidy table per trial, ready to be analysed and plotted.
#
# `index_tables.R` makes the record layer's tables: what was delivered, what came back,
# verbatim, with no study knowledge in them. That is deliberate -- it means the record
# layer does not have to know what this study is about.
#
# This file is the other half. It joins the record layer's tables to the study's own
# declarations -- which folder name means which condition, which command text means which
# runtime, which plan order a slot was run in -- and emits one row per trial. Everything
# after this point reads `trials.csv` and never touches JSON again.
#
# It still does not judge. `verdict` is brought in from the judgement record, which is
# `tools/grade.py`'s output; nothing here recomputes or overrides it. A pass column
# computed in the analysis layer would be a second judge.
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

# This script belongs to one study, so it names its own directory once. The instrument
# tables stay at records/tables because they cover every run on the machine; everything
# this study derives goes under records/<study_id>/ so a second study cannot overwrite it.
STUDY <- "studies/workspace-name-cue"
REC <- file.path("records", basename(STUDY))

TABLES <- "records/tables"
OUT <- REC
PREREG <- file.path(STUDY, "prereg/norris-r3-v1.json")
CONDS <- file.path(STUDY, "conditions.json")
INTERP <- file.path(STUDY, "interpreters.json")
FEATS <- file.path(STUDY, "features.json")

# fromJSON(simplifyVector = FALSE) gives NULL for an absent key and a list for a present
# one, so every scalar needs the same unwrapping. One helper, defined before its first use.
chr <- function(x) {
  if (is.null(x) || length(x) == 0) NA_character_ else as.character(x)[1]
}

# The plan file and the judgement file are named after the prereg's own identifiers, not
# after anything typed here. Two literals that have to agree are two chances to fall out
# of step, and the failure would be silent: the join quietly produces no rows.
prereg <- fromJSON(PREREG, simplifyVector = FALSE)
PLAN <- file.path(REC, "plan", paste0(chr(prereg$plan_id), ".jsonl"))
JUDGE <- file.path(REC, "judgment", basename(chr(prereg$criteria)))

# ==============================================================================
# 1. The study's own declarations
# ==============================================================================

# A wording lives in exactly one condition; that is what makes the folder name a treatment.
conditions <- fromJSON(CONDS, simplifyVector = FALSE)$conditions |>
  imap(\(spec, name) {
    tibble(condition = name, wording = flatten_chr(spec$words))
  }) |>
  list_rbind()

# Which command text counts as which runtime. Regexes, applied to the verbatim args.
runtimes <- fromJSON(INTERP, simplifyVector = FALSE)$runtimes |>
  map(\(r) tibble(runtime = chr(r$name), pattern = chr(r$pattern))) |>
  list_rbind()

planned <- readLines(PLAN, warn = FALSE, encoding = "UTF-8") |>
  keep(nzchar) |>
  map(\(l) fromJSON(l, simplifyVector = FALSE)) |>
  map(\(r) {
    tibble(
      plan_order = as.integer(chr(r$order)),
      slot = chr(r$slot),
      plan_family = chr(r$family),
      rep = as.integer(chr(r$rep))
    )
  }) |>
  list_rbind()

judged <- fromJSON(JUDGE, simplifyVector = FALSE)$verdicts |>
  map(\(v) tibble(run_id = chr(v$run_id), verdict = chr(v$status))) |>
  list_rbind()

# ==============================================================================
# 2. One row per trial
# ==============================================================================

observations <- read_csv(
  file.path(TABLES, "observations.csv"),
  show_col_types = FALSE,
  progress = FALSE
)
calls <- read_csv(
  file.path(TABLES, "calls.csv"),
  show_col_types = FALSE,
  progress = FALSE
)

# The outcome: the FIRST executed call whose arguments name a runtime. An earlier call
# that names none is skipped, not counted as "none" -- reading a file before deciding how
# to compute is not a choice of runtime.
first_runtime <- calls |>
  mutate(across(args, \(a) coalesce(a, ""))) |>
  cross_join(runtimes) |>
  mutate(hit = str_detect(args, regex(pattern, ignore_case = TRUE))) |>
  filter(hit) |>
  group_by(run_id) |>
  arrange(step, .by_group = TRUE) |>
  summarise(
    first_runtime = first(runtime),
    runtimes_seen = paste(sort(unique(runtime)), collapse = "+"),
    .groups = "drop"
  )

trials <- observations |>
  transmute(
    run_id,
    trial,
    task_id,
    stimulus_id,
    input_id,
    slot = ws_name,
    wording = str_remove(slot, "-\\d+$"),
    rep_in_slot = as.integer(str_extract(slot, "\\d+$")),
    stop_reason,
    wall_ms,
    steps,
    tool_calls,
    tool_errors,
    in_total,
    out_tokens,
    answer_json
  ) |>
  left_join(conditions, by = "wording") |>
  # Only the plan order crosses over: plan_family duplicates condition and rep duplicates
  # round, and a column nothing declares is a definition nobody reviewed.
  left_join(planned |> select(slot, plan_order), by = "slot") |>
  left_join(judged, by = "run_id") |>
  left_join(first_runtime, by = "run_id") |>
  mutate(
    # A trial that names no runtime at all is a legal outcome, not missing data.
    first_runtime = coalesce(first_runtime, "none"),
    runtimes_seen = coalesce(runtimes_seen, ""),
    mixed = str_detect(runtimes_seen, fixed("+")),
    zero_tool = tool_calls == 0L,
    used_runtime = first_runtime %in% c("R", "python"),
    # Four conditions x twelve wordings is one replicate of the design; six replicates
    # make the batch. Round is the block, and blocks are what position effects live in.
    round = (plan_order - 1L) %/% 48L + 1L,
    verdict = coalesce(verdict, "unknown")
  ) |>
  arrange(plan_order)

# ==============================================================================
# 3. Scope: this table describes ONE plan
# ==============================================================================

# The index holds every run on this machine: batch 1, the single-trial probes that fixed
# k, the harness round-trip checks. They are true records and stay in the index, but they
# were never trials of this plan -- they ran a different task under a different design, so
# `condition` and `round` have no meaning for them. Naming the scope here is cheaper than
# a later reader filtering by accident and concluding the study had 330 trials.
in_plan <- !is.na(trials$plan_order)
set_aside <- trials |> filter(!in_plan)

trials_plan <- trials |>
  filter(in_plan) |>
  mutate(round = as.integer(round))

# ==============================================================================
# 4. Write and check
# ==============================================================================

write_csv(trials_plan, file.path(OUT, "trials.csv"))

cat(sprintf("trials : %d rows (this plan)\n", nrow(trials_plan)))
cat(sprintf(
  "set aside: %d trial(s) in the index that belong to another batch or a probe\n",
  nrow(set_aside)
))
cat(sprintf(
  "wordings: %d, all in a declared condition: %s\n",
  n_distinct(trials_plan$wording),
  !any(is.na(trials_plan$condition))
))
cat(sprintf("planned: %d, matched: %d\n", nrow(planned), nrow(trials_plan)))
cat("\n")

if (nrow(trials_plan) != nrow(planned)) {
  cat("trials.csv does not cover the plan:\n")
  anti_join(planned, trials_plan, by = "slot") |> print(n = Inf)
  quit(status = 2)
}

if (any(is.na(trials_plan$condition))) {
  cat("a trial sits in a folder no condition claims:\n")
  trials_plan |> filter(is.na(condition)) |> distinct(slot) |> print(n = Inf)
  quit(status = 2)
}

# The classification has to survive a re-read: a word that is not a runtime must not be
# silently counted as one, and every trial must land in exactly one outcome value.
cat("outcome values:\n")
trials_plan |> count(first_runtime, sort = TRUE) |> print(n = Inf)
cat("\n")
cat("verdicts:\n")
trials_plan |> count(verdict, sort = TRUE) |> print(n = Inf)
cat("\n")

if (!all(trials_plan$first_runtime %in% c("R", "python", "none"))) {
  cat("an outcome value appeared that interpreters.json did not declare\n")
  quit(status = 2)
}

if (any(trials_plan$verdict == "unknown")) {
  cat(sprintf(
    "note: %d trial(s) have no verdict in %s\n",
    sum(trials_plan$verdict == "unknown"),
    JUDGE
  ))
}

# ==============================================================================
# 5. 口径 gate: the declared features and the emitted columns must cover each other
# ==============================================================================

# A derived variable is a definition, and a definition that only exists inside a mutate()
# call is one only its author can audit. features.json declares every column that is
# not a verbatim record field; this asserts both directions, so neither can drift:
#   - a column in the table that nobody declared  -> a definition nobody reviewed
#   - a feature declared that the table lacks     -> a definition nobody applies
spec <- fromJSON(FEATS, simplifyVector = FALSE)

declared <- map_chr(spec$features, \(f) chr(f$name))
base <- flatten_chr(spec$base_columns$columns)
emitted <- names(trials_plan)

undeclared <- setdiff(emitted, c(base, declared))
unapplied <- setdiff(declared, emitted)

cat("\n5. FEATURE DECLARATION -- features.json vs the emitted columns\n")
cat(sprintf(
  "   base %d + declared %d = %d; emitted %d\n",
  length(base),
  length(declared),
  length(c(base, declared)),
  length(emitted)
))

if (length(undeclared) || length(unapplied)) {
  if (length(undeclared)) {
    cat(
      "   emitted but not declared: ",
      paste(undeclared, collapse = ", "),
      "\n"
    )
  }
  if (length(unapplied)) {
    cat(
      "   declared but not emitted: ",
      paste(unapplied, collapse = ", "),
      "\n"
    )
  }
  cat("   A column without a declaration is a definition nobody reviewed.\n")
  quit(status = 2)
}
cat("   ok -- every column is either a record field or a declared feature\n")
