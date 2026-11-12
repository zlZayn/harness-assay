# Where the numeric tolerance comes from. Not part of the pipeline: run it when the
# criteria change, and paste the numbers into studies/<id>/criteria/v1.json.
#
# The tasks ask for 4 significant digits. That fixes what a *correct* answer looks like:
# the correctly rounded 4-digit form has a relative error of at most 5e-5, and in practice
# ~3e-4 for these values because rounding lands on the far side of a digit boundary.

truth <- list(
  welch  = list(mean_diff = 1.1045708061, n_control = 34, n_treat = 27, p_value = 0.083161116958),
  meansd = list(mean = 11.0069672131, sd = 2.4156956760)
)
reported <- list(
  welch  = list(mean_diff = 1.105, n_control = 34, n_treat = 27, p_value = 0.0832),
  meansd = list(mean = 11.01, sd = 2.416)
)

cat("=== what the two runs actually reported ===\n")
for (task in names(truth)) {
  cat("--", task, "\n")
  for (f in names(truth[[task]])) {
    tr <- truth[[task]][[f]]
    rp <- reported[[task]][[f]]
    cat(sprintf("  %-10s truth=%-16.12g reported=%-8g rel_err=%.3e\n",
                f, tr, rp, abs(rp - tr) / abs(tr)))
  }
}

cat("\n=== what a coarser answer would cost (relative error) ===\n")
cases <- c(
  "mean 11.0 (3 sig)"   = abs(11.0 - 11.0069672131) / 11.0069672131,
  "sd 2.42 (3 sig)"     = abs(2.42 - 2.4156956760) / 2.4156956760,
  "mean_diff 1.10"      = abs(1.10 - 1.1045708061) / 1.1045708061,
  "p 0.0832 (3 sig)"    = abs(0.0832 - 0.083161116958) / 0.083161116958,
  "p 0.083 (2 sig)"     = abs(0.083 - 0.083161116958) / 0.083161116958
)
print(signif(cases, 4))

cat("\n=== read-off ===\n")
cat("  5e-4 accepts every correctly rounded 4-digit answer above.\n")
cat("  5e-4 rejects the 3-digit mean (6.3e-4), sd (1.8e-3), mean_diff (4.1e-3),\n")
cat("  and p at 2 digits (1.9e-3).\n")
cat("  KNOWN HOLE: p reported as 0.0832 is only 3 digits yet lands at 4.7e-4,\n")
cat("  inside the tolerance. Relative tolerance cannot enforce precision for a\n")
cat("  small quantity. Recorded in the criteria file rather than papered over.\n")
