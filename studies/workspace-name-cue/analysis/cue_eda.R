# Targeted, descriptive EDA for the two completed trial tables.
# Does not alter observations or introduce a new inferential criterion.
suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(tidyr)
  library(jsonlite)
  library(stringr)
})

REC <- "records/workspace-name-cue"
OUT <- file.path(REC, "eda")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
trials <- bind_rows(
  read_csv(file.path(REC, "trials.csv"), show_col_types = FALSE, progress = FALSE),
  read_csv(file.path(REC, "trials-kimi.csv"), show_col_types = FALSE, progress = FALSE)
) |>
  mutate(model = factor(model, levels = c("DeepSeek-V4.1-Flash-1017", "Kimi-K3.1-Pro")))

model_summary <- trials |>
  summarise(
    n = n(), R = sum(first_runtime == "R"), python = sum(first_runtime == "python"),
    none = sum(first_runtime == "none"), used_runtime = sum(first_runtime != "none"), mixed = sum(mixed),
    pass = sum(verdict == "pass"), fail = sum(verdict == "fail"), missing = sum(verdict == "missing"),
    stop_error = sum(stop_reason == "error"), tool_errors = sum(tool_errors),
    steps_3 = sum(steps == 3), tool_calls_3 = sum(tool_calls == 3),
    both_3 = sum(steps == 3 & tool_calls == 3), equal_steps_calls = sum(steps == tool_calls),
    median_steps = median(steps), median_tool_calls = median(tool_calls),
    median_wall_s = median(wall_ms) / 1000, median_out_tokens = median(out_tokens),
    median_in_total = median(in_total), .by = model
  )
write_csv(model_summary, file.path(OUT, "model-summary.csv"))

condition_summary <- trials |>
  summarise(
    n = n(), R = sum(first_runtime == "R"), python = sum(first_runtime == "python"),
    none = sum(first_runtime == "none"), used_runtime = sum(first_runtime != "none"), mixed = sum(mixed),
    pass = sum(verdict == "pass"), fail = sum(verdict == "fail"), missing = sum(verdict == "missing"),
    steps_3 = sum(steps == 3), tool_calls_3 = sum(tool_calls == 3),
    median_steps = median(steps), median_tool_calls = median(tool_calls),
    median_wall_s = median(wall_ms) / 1000, median_out_tokens = median(out_tokens),
    median_in_total = median(in_total), .by = c(model, condition)
  )
write_csv(condition_summary, file.path(OUT, "condition-summary.csv"))

round_summary <- trials |>
  summarise(
    n = n(), R = sum(first_runtime == "R"), python = sum(first_runtime == "python"),
    none = sum(first_runtime == "none"), pass = sum(verdict == "pass"),
    fail = sum(verdict == "fail"), missing = sum(verdict == "missing"),
    steps_3 = sum(steps == 3), tool_calls_3 = sum(tool_calls == 3),
    median_wall_s = median(wall_ms) / 1000, median_out_tokens = median(out_tokens),
    .by = c(model, round)
  )
write_csv(round_summary, file.path(OUT, "round-summary.csv"))

step_cross <- trials |>
  count(model, steps, tool_calls, name = "n") |>
  arrange(model, steps, tool_calls)
write_csv(step_cross, file.path(OUT, "steps-tool-crosstab.csv"))

kimi_non3 <- trials |>
  filter(model == "Kimi-K3.1-Pro", steps != 3 | tool_calls != 3) |>
  select(run_id, condition, wording, round, steps, tool_calls, first_runtime,
         verdict, wall_ms, out_tokens, in_total)
write_csv(kimi_non3, file.path(OUT, "kimi-non3.csv"))

metrics <- c("steps", "tool_calls", "wall_ms", "in_total", "out_tokens")
position_trends <- expand_grid(model = levels(trials$model), metric = metrics) |>
  mutate(
    spearman = map2_dbl(model, metric, \(m, v) {
      x <- trials |> filter(model == m)
      cor(x$plan_order, x[[v]], method = "spearman")
    })
  )
write_csv(position_trends, file.path(OUT, "position-trends.csv"))

position_thirds <- trials |>
  mutate(third = ceiling(plan_order / 96)) |>
  summarise(n = n(), R = sum(first_runtime == "R"), .by = c(model, condition, third))
write_csv(position_thirds, file.path(OUT, "position-thirds.csv"))

effort_first <- trials |>
  summarise(
    n = n(), median_steps = median(steps), median_tool_calls = median(tool_calls),
    median_wall_s = median(wall_ms) / 1000, median_out_tokens = median(out_tokens),
    median_in_total = median(in_total), .by = c(model, first_runtime)
  )
write_csv(effort_first, file.path(OUT, "effort-first-runtime.csv"))

workflow_first <- trials |>
  mutate(workflow = if_else(steps == 3 & tool_calls == 3, "3-and-3", "other")) |>
  count(model, first_runtime, workflow, name = "n")
write_csv(workflow_first, file.path(OUT, "workflow-first-runtime.csv"))

workflow_effort <- trials |>
  mutate(workflow = if_else(steps == 3 & tool_calls == 3, "3-and-3", "other")) |>
  summarise(
    n = n(), median_wall_s = median(wall_ms) / 1000,
    median_out_tokens = median(out_tokens), median_in_total = median(in_total),
    .by = c(model, workflow)
  )
write_csv(workflow_effort, file.path(OUT, "workflow-effort.csv"))

wording_primary <- trials |>
  filter(condition %in% c("r-eco", "software")) |>
  summarise(n = n(), R = sum(first_runtime == "R"), rate = mean(first_runtime == "R"),
            .by = c(model, condition, wording))
write_csv(wording_primary, file.path(OUT, "wording-primary.csv"))

runtime_decomposition <- trials |>
  filter(first_runtime == "R", condition %in% c("r-eco", "software")) |>
  mutate(part = if_else(runtimes_seen == "R", "R_only", "dual_named")) |>
  count(model, condition, part, name = "n") |>
  mutate(contribution = n / 72)
write_csv(runtime_decomposition, file.path(OUT, "runtime-decomposition.csv"))

loo <- map_dfr(seq_len(nrow(wording_primary)), \(i) {
  row <- wording_primary[i, ]
  remaining <- trials |>
    filter(
      model == row$model, condition %in% c("r-eco", "software"),
      !(condition == row$condition & wording == row$wording)
    )
  rates <- remaining |>
    summarise(rate = mean(first_runtime == "R"), n = n(), .by = condition)
  tibble(
    model = row$model, deleted_condition = row$condition, deleted_wording = row$wording,
    r_eco_n = rates$n[rates$condition == "r-eco"],
    software_n = rates$n[rates$condition == "software"],
    delta = rates$rate[rates$condition == "r-eco"] - rates$rate[rates$condition == "software"]
  )
})
write_csv(loo, file.path(OUT, "leave-one-wording-out.csv"))

wording_all <- trials |>
  summarise(R = sum(first_runtime == "R"), .by = c(model, wording)) |>
  pivot_wider(names_from = model, values_from = R) |>
  mutate(direction = case_when(
    `Kimi-K3.1-Pro` > `DeepSeek-V4.1-Flash-1017` ~ "increase",
    `Kimi-K3.1-Pro` < `DeepSeek-V4.1-Flash-1017` ~ "decrease",
    TRUE ~ "same"
  ))
write_csv(wording_all, file.path(OUT, "wording-all.csv"))
write_csv(count(wording_all, direction), file.path(OUT, "wording-direction-summary.csv"))

wording_positions <- trials |>
  mutate(within_round_position = (plan_order - 1) %% 48 + 1) |>
  distinct(wording, condition, within_round_position) |>
  arrange(within_round_position)
stopifnot(nrow(wording_positions) == 48, length(unique(wording_positions$within_round_position)) == 48)
write_csv(wording_positions, file.path(OUT, "wording-positions.csv"))

# Verify answer precision against the declared truth and per-field tolerances.
criteria <- fromJSON("studies/workspace-name-cue/criteria/norris-v1.json", simplifyVector = FALSE)
task_criteria <- criteria$tasks[[1]]
fields <- c("b0", "b1", "r2", "resid_sd", "se_b0", "se_b1")
truth <- map_dbl(fields, \(f) task_criteria$truth[[f]]) |> setNames(fields)
tolerance <- map_dbl(fields, \(f) task_criteria$tolerance[[f]]) |> setNames(fields)
answers <- trials |>
  select(model, run_id, verdict, answer_json) |>
  mutate(values = map(answer_json, \(s) {
    if (is.na(s)) return(setNames(rep(NA_real_, length(fields)), fields))
    parsed <- fromJSON(s)
    map_dbl(fields, \(f) parsed[[f]]) |> setNames(fields)
  })) |>
  unnest_wider(values)
answer_checks <- map_dfr(fields, \(f) {
  truth_value <- truth[[f]]
  tolerance_value <- tolerance[[f]]
  four_value <- signif(truth_value, 4)
  answers |>
    transmute(
      model, run_id, verdict, field = f, answer = .data[[f]], truth = truth_value,
      four_signif = four_value, tolerance = tolerance_value,
      exact_four = !is.na(.data[[f]]) & .data[[f]] == four_value,
      relative_error = abs(.data[[f]] - truth_value) / abs(truth_value),
      over_tolerance = !is.na(.data[[f]]) & relative_error > tolerance_value
    )
})
answer_summary <- answer_checks |>
  summarise(
    fields = n(), exact_four_fields = sum(exact_four), over_tolerance_fields = sum(over_tolerance),
    all_six_exact_four = all(exact_four), all_six_over = all(over_tolerance),
    .by = c(model, run_id, verdict)
  ) |>
  summarise(
    trials = n(), all_six_exact_four = sum(all_six_exact_four),
    all_six_over = sum(all_six_over), .by = c(model, verdict)
  )
write_csv(answer_summary, file.path(OUT, "answer-precision-summary.csv"))
answer_field_errors <- answer_checks |>
  filter(model == "Kimi-K3.1-Pro", verdict == "fail") |>
  summarise(
    trials = n(), answer = unique(answer), truth = unique(truth), four_signif = unique(four_signif),
    relative_error = unique(relative_error), tolerance = unique(tolerance),
    all_exact_four = all(exact_four), all_over_tolerance = all(over_tolerance),
    .by = field
  ) |>
  mutate(error_over_tolerance = relative_error / tolerance)
write_csv(answer_field_errors, file.path(OUT, "kimi-answer-field-errors.csv"))

# Inspect actual tool sequences, not only their counts.
calls <- read_csv("records/tables/calls.csv", show_col_types = FALSE, progress = FALSE) |>
  mutate(call_index = row_number()) |>
  inner_join(
    trials |> select(run_id, model, condition, wording, round, steps, tool_calls, first_runtime, verdict),
    by = "run_id", relationship = "many-to-one"
  )

kimi_fail_ids <- trials |> filter(model == "Kimi-K3.1-Pro", verdict == "fail") |> pull(run_id)
kimi_precision_commands <- calls |>
  filter(run_id %in% kimi_fail_ids, name == "pwsh") |>
  summarise(
    requested_6g = any(str_detect(args, fixed(".6g"))),
    full_precision_repr = any(str_detect(args, "repr\\(")),
    .by = run_id
  )
stopifnot(
  nrow(kimi_precision_commands) == 17,
  sum(kimi_precision_commands$requested_6g) == 16,
  sum(!kimi_precision_commands$requested_6g & kimi_precision_commands$full_precision_repr) == 1
)
write_csv(kimi_precision_commands, file.path(OUT, "kimi-precision-commands.csv"))

sequences <- calls |>
  arrange(model, run_id, step, call_index) |>
  summarise(sequence = paste(name, collapse = " > "), .by = c(
    run_id, model, condition, wording, round, steps, tool_calls, first_runtime, verdict
  ))
sequence_counts <- sequences |> count(model, sequence, name = "n") |> arrange(model, desc(n))
write_csv(sequence_counts, file.path(OUT, "tool-sequences.csv"))

three_sequences <- sequences |>
  filter(model == "Kimi-K3.1-Pro", steps == 3, tool_calls == 3) |>
  count(sequence, name = "n") |>
  arrange(desc(n))
write_csv(three_sequences, file.path(OUT, "kimi-three-step-sequences.csv"))

tool_use <- calls |>
  summarise(calls = n(), runs = n_distinct(run_id), .by = c(model, name)) |>
  arrange(model, desc(calls))
write_csv(tool_use, file.path(OUT, "tool-use.csv"))

extra_tool_use <- calls |>
  filter(model == "Kimi-K3.1-Pro") |>
  mutate(workflow = if_else(tool_calls == 3, "3 calls", ">3 calls")) |>
  summarise(calls = n(), runs = n_distinct(run_id), .by = c(workflow, name)) |>
  arrange(workflow, desc(calls))
write_csv(extra_tool_use, file.path(OUT, "kimi-extra-tool-use.csv"))

cat("\nMODEL SUMMARY\n")
print(model_summary, n = Inf, width = Inf)
cat("\nKIMI STEPS x TOOL CALLS\n")
print(step_cross |> filter(model == "Kimi-K3.1-Pro"), n = Inf)
cat("\nKIMI NON-3 TRIALS\n")
print(kimi_non3, n = Inf, width = Inf)
cat("\nKIMI 3-AND-3 TOOL SEQUENCES\n")
print(three_sequences, n = Inf)
cat("\nTOOL USE BY MODEL\n")
print(tool_use, n = Inf)
cat("\nKIMI EXTRA TOOL USE\n")
print(extra_tool_use, n = Inf)
cat("\nPOSITION TRENDS\n")
print(position_trends, n = Inf)
cat("\nEFFORT BY FIRST RUNTIME\n")
print(effort_first, n = Inf, width = Inf)
cat("\nTOP TOOL SEQUENCES\n")
print(sequence_counts |> group_by(model) |> slice_max(n, n = 10) |> ungroup(), n = Inf)
cat("\nEDA tables ->", OUT, "\n")
