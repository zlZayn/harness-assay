# ==============================================================================
# Two tidy tables over the record index.
#
# Analysis layer only: reads records/index.jsonl, writes nothing the record layer
# owns. Run from the project root, no setwd().
#
# The split is the whole point:
#
#   conditions    one row per stimulus_id  -- one row per *arm*
#                 Holds only what the subject received. Two harness files that differ
#                 cosmetically collapse into one row here, which is what lets a
#                 condition be replaced without moving the meaning of a conclusion.
#
#   observations  one row per trial        -- one row per *measurement*
#                 Adds provenance (which input produced it) and the outcome. The
#                 workspace columns live here because cwd is an input, not a treatment
#                 -- it only becomes a treatment by reaching the subject, which is what
#                 cwd_injected records.
#
# Nothing here judges. There is no pass, no score, no filter: a criteria file applies
# later, outside, and can be replaced without re-reading a record.
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(purrr)
  library(readr)
})

INDEX <- "records/index.jsonl"
OUT   <- "records/tables"

# ==============================================================================
# 1. Read
# ==============================================================================

chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x)[1]
num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]
lgl <- function(x) if (is.null(x) || length(x) == 0) NA else as.logical(x)[1]
join_chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else paste(unlist(x), collapse = ",")

records <- readLines(INDEX, warn = FALSE, encoding = "UTF-8") |>
  keep(\(l) nzchar(trimws(l))) |>
  map(\(l) fromJSON(l, simplifyVector = FALSE))

stopifnot(length(records) > 0)

# ==============================================================================
# 2. One row per trial
# ==============================================================================

observations <- records |>
  map(\(r) {
    s <- r$stimulus
    w <- r$workspace
    o <- r$observed
    i <- r$inputs
    tu <- o$token_usage
    tr <- o$trace
    st <- s$system_prompt
    tl <- s$tools
    ms <- s$messages
    or <- s$observed_route

    tibble(
      # --- identity of the measurement ---
      run_id          = chr(r$run_id),
      trial           = num(r$trial),
      task_id         = chr(r$task_id),
      record_schema   = num(r$record_schema),

      # --- which experiment, which spec ---
      stimulus_id     = chr(r$stimulus_id),
      input_id        = chr(r$input_id),
      stimulus_ok     = !isTRUE(r$stimulus_unavailable),

      # --- provenance: what the operator supplied ---
      harness_sha     = chr(i$harness_sha),
      sealed          = lgl(i$sealed),
      max_depth       = num(i$max_depth),
      task_prompt_sha = chr(i$task_prompt_sha),
      schema_sha      = chr(i$output_schema_sha),

      # --- workspace: an input, until it reaches the subject ---
      cwd             = chr(i$cwd),
      ws_name         = chr(w$cwd_name),
      ws_parent       = chr(w$cwd_parent),
      cwd_injected    = lgl(w$cwd_injected),
      cwd_mentions    = num(w$messages_mention_cwd),

      # --- delivered: what the subject actually received ---
      sys_sha         = chr(st$sha),
      sys_chars       = num(st$chars),
      tools_sha       = chr(tl$sha),
      tools_count     = num(tl$count),
      tools_names     = join_chr(tl$names),
      msgs_sha        = chr(ms$sha),
      msgs_count      = num(ms$count),
      msg_kinds       = join_chr(ms$kinds),
      route_provider  = chr(or$provider),
      route_model     = chr(or$model),
      route_effort    = chr(or$reasoningEffort),
      route_maxTokens = num(or$maxTokens),

      # --- outcome: what happened, untouched ---
      stop_reason     = chr(o$stop_reason),
      timed_out       = lgl(o$timed_out),
      wall_ms         = num(o$wall_ms),
      steps           = num(o$steps),
      tool_calls      = num(tr$toolCalls),
      tool_errors     = num(tr$toolErrors),
      in_uncached     = num(tu$uncachedInputTokens),
      in_cache_read   = num(tu$cacheReadTokens),
      # Prompt cache splits the same input two ways; the sum is the honest input size.
      in_total        = num(tu$uncachedInputTokens) + num(tu$cacheReadTokens),
      out_tokens      = num(tu$outputTokens),
      answer_json     = if (is.null(o$structured)) NA_character_
                        # digits = NA keeps every digit. jsonlite::toJSON defaults to
                        # digits = 4, which silently rounds an answer on its way into
                        # this table: invisible while the answers happened to carry four
                        # significant digits, fatal on a task that asks for six. The
                        # record is right either way; this file was the liar.
                        else as.character(toJSON(o$structured, auto_unbox = TRUE, digits = NA))
    )
  }) |>
  list_rbind()

# ==============================================================================
# 3. One row per tool call
# ==============================================================================

# `observations` keeps a COUNT of calls; the arguments are where the evidence lives.
# The process-level question of this study -- which runtime did it reach for -- is
# answered by reading `args`, so without this table every such question has to go back
# to the raw index and re-parse it. One row per call, verbatim, so a later question
# costs a filter instead of a rewrite.

calls <- records |>
  map(\(r) {
    cl <- r$observed$tool_calls
    if (is.null(cl) || length(cl) == 0) return(NULL)
    tibble(
      run_id      = chr(r$run_id),
      stimulus_id = chr(r$stimulus_id),
      ws_name     = chr(r$workspace$cwd_name),
      step        = map_dbl(cl, \(c) num(c$step)),
      name        = map_chr(cl, \(c) chr(c$name)),
      args        = map_chr(cl, \(c) chr(c$args)),
      args_chars  = map_dbl(cl, \(c) num(c$args_chars)),
      error       = map_lgl(cl, \(c) isTRUE(c$error))
    )
  }) |>
  list_rbind()

# ==============================================================================
# 4. One row per arm
# ==============================================================================
conditions <- observations |>
  filter(stimulus_ok) |>
  group_by(stimulus_id) |>
  summarise(
    # delivered attributes are constant within a stimulus_id by construction
    sys_sha         = first(sys_sha),
    sys_chars       = first(sys_chars),
    tools_sha       = first(tools_sha),
    tools_count     = first(tools_count),
    tools_names     = first(tools_names),
    msgs_sha        = first(msgs_sha),
    msgs_count      = first(msgs_count),
    msg_kinds       = first(msg_kinds),
    route_provider  = first(route_provider),
    route_model     = first(route_model),
    route_effort    = first(route_effort),
    # how many efforts produced this one condition
    n_trials        = n(),
    n_runs          = n_distinct(run_id),
    n_inputs        = n_distinct(input_id),
    .groups = "drop"
  ) |>
  arrange(stimulus_id)

# ==============================================================================
# 5. Write and check
# ==============================================================================

dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write_csv(observations, file.path(OUT, "observations.csv"))
write_csv(conditions,   file.path(OUT, "conditions.csv"))
write_csv(calls,        file.path(OUT, "calls.csv"))

unavailable <- sum(!observations$stimulus_ok)

cat(sprintf("observations : %d rows\n", nrow(observations)))
cat(sprintf("conditions   : %d rows\n", nrow(conditions)))
cat(sprintf("calls        : %d rows (%d with an error flag)\n",
            nrow(calls), sum(calls$error)))
cat(sprintf("unavailable  : %d trial(s) with no events.jsonl\n", unavailable))
cat("\n")

# The call table must account for exactly the calls the per-trial table counted.
# A silent drop here would make a runtime look unused, which is the one error this
# study cannot afford: zero is a legal outcome value.
by_trial <- observations |>
  select(run_id, counted = tool_calls) |>
  left_join(count(calls, run_id, name = "detailed"), by = "run_id") |>
  mutate(detailed = coalesce(detailed, 0L))

if (any(by_trial$counted != by_trial$detailed)) {
  cat("calls table DISAGREES with the per-trial count:\n")
  by_trial |>
    filter(counted != detailed) |>
    print(n = Inf, width = 120)
  quit(status = 2)
}
cat("call-count check -- every counted call has a row\n")
cat("\n")

conditions |>
  select(stimulus_id, sys_sha, tools_sha, msgs_sha,
         n_trials, n_runs, n_inputs) |>
  print(n = Inf, width = 120)

cat("\n")
cat("collapse check -- a condition fed by more than one input file:\n")
conditions |>
  filter(n_inputs > 1) |>
  select(stimulus_id, n_inputs, n_runs, n_trials) |>
  print(n = Inf, width = 120)

# ==============================================================================
# 6. Self-check: a derived table must not change a number
# ==============================================================================

# The failure this catches is not a typo, it is a default. jsonlite::toJSON rounds to
# four significant digits unless told otherwise, so every answer passed through this
# file rounded -- silently, for as long as the answers happened to be four digits.
# Only a task asking for six exposed it. A check is the only defence: nobody chose
# that behaviour, so nobody will remember it.
cat("\n")
cat("round-trip check -- answer_json must reproduce the record exactly:\n")

answers <- function(txt) tryCatch(fromJSON(txt, simplifyVector = FALSE),
                                  error = function(e) NULL)

stopifnot(nrow(observations) == length(records))
bad <- records |>
  map2_chr(observations$answer_json, \(r, txt) {
    orig <- r$observed$structured
    if (is.na(txt) || is.null(orig)) return(NA_character_)
    back <- answers(txt)
    if (is.null(back)) {
      return(sprintf("%s: answer_json does not parse", chr(r$run_id)))
    }
    hit <- keep(names(orig), \(k) {
      a <- back[[k]]; b <- orig[[k]]
      is.numeric(a) && is.numeric(b) &&
        !isTRUE(all.equal(a, b, tolerance = 0))
    })
    if (length(hit) == 0) return(NA_character_)
    k <- hit[[1]]
    sprintf("%s: %s %s -> %s", chr(r$run_id), k,
            format(orig[[k]], digits = 17), format(back[[k]], digits = 17))
  }) |>
  discard(is.na)

if (length(bad) == 0) {
  cat(sprintf("  ok -- %d answer(s) survived the trip unchanged\n", sum(!is.na(observations$answer_json))))
} else {
  cat(sprintf("  %d answer(s) CHANGED between the index and this table:\n", length(bad)))
  for (b in head(bad, 10)) cat("    ", b, "\n")
  if (length(bad) > 10) cat(sprintf("     ... and %d more\n", length(bad) - 10))
  cat("  A number that changes downstream makes every judgement made from this table\n")
  cat("  a statement about the rounding, not about the answer.\n")
  quit(status = 2)
}
