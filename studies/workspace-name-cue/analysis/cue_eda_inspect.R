# Deterministic seven-step inspection of one tidy trial table.
# Usage: Rscript cue_eda_inspect.R <input.csv> <output.md>
suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(knitr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Expected <input.csv> <output.md>")
input <- args[[1]]
output <- args[[2]]
low_card_threshold <- 20L
corr_threshold <- 0.99

df <- read_csv(input, guess_max = Inf, show_col_types = FALSE, progress = FALSE)

id_like <- function(nm) str_detect(nm, regex("(^|_)(id|uuid|hash|sha)(_|$)", ignore_case = TRUE))
datetime_candidate <- function(x, nm) {
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return(TRUE)
  if (!is.character(x) || id_like(nm)) return(FALSE)
  sample <- na.omit(x)
  if (!length(sample)) return(FALSE)
  sample <- head(sample, 100)
  mean(str_detect(sample, "^\\d{4}-\\d{2}-\\d{2}")) > 0.80
}
column_type <- function(x, nm) {
  if (datetime_candidate(x, nm)) return("datetime")
  if (is.numeric(x)) return("numeric")
  "string"
}
col_info <- tibble(name = names(df)) |>
  mutate(
    type = map2_chr(df, name, column_type),
    unique = map_int(df, \(x) n_distinct(x, na.rm = FALSE)),
    missing = map_int(df, \(x) sum(is.na(x))),
    missing_pct = round(100 * missing / nrow(df), 2)
  )

as_datetime <- function(x) {
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return(as.POSIXct(x, tz = "UTC"))
  parse_datetime(x, na = c("", "NA"), locale = locale(tz = "UTC"))
}
md_table <- function(x) paste(kable(x, format = "markdown", align = "l"), collapse = "\n")
missing_label <- function(x) ifelse(is.na(x), "(missing)", as.character(x))

lines <- c(
  paste0("# Tidy data inspection: ", basename(input)), "",
  "## 1. Skeleton", "",
  paste0("Rows: **", nrow(df), "**; columns: **", ncol(df), "**."), "",
  md_table(col_info), ""
)

# 2. Missing values and fully duplicated rows.
missing_cols <- col_info |> filter(missing > 0) |> arrange(desc(missing_pct), name)
lines <- c(lines, "## 2. Missing and duplicates", "",
  if (nrow(missing_cols)) md_table(missing_cols) else "No missing values found.", "",
  paste0("Fully duplicate rows: **", sum(duplicated(df)), "**."), "")

# 3. Low-cardinality frequency tables, including missing as a category.
low_names <- col_info |> filter(unique <= low_card_threshold) |> pull(name)
lines <- c(lines, "## 3. Low-cardinality columns", "",
  if (!length(low_names)) "No low-cardinality columns found." else NULL, "")
walk(low_names, \(nm) {
  freq <- tibble(value = missing_label(df[[nm]])) |>
    count(value, name = "n") |>
    mutate(pct = round(100 * n / nrow(df), 2)) |>
    arrange(desc(n), value)
  lines <<- c(lines, paste0("### ", nm), "", md_table(freq), "")
})

# 4. High-cardinality numeric summaries and IQR outlier shares.
num_names <- col_info |> filter(type == "numeric", unique > low_card_threshold) |> pull(name)
num_stats <- map_dfr(num_names, \(nm) {
  x <- df[[nm]]
  q <- quantile(x, c(0.25, 0.75), na.rm = TRUE, names = FALSE)
  iqr <- q[[2]] - q[[1]]
  outliers <- if (iqr == 0) rep(FALSE, length(x)) else x < q[[1]] - 1.5 * iqr | x > q[[2]] + 1.5 * iqr
  tibble(
    name = nm, min = min(x, na.rm = TRUE), max = max(x, na.rm = TRUE),
    mean = mean(x, na.rm = TRUE), median = median(x, na.rm = TRUE),
    sd = sd(x, na.rm = TRUE), q1 = q[[1]], q3 = q[[2]],
    negative = sum(x < 0, na.rm = TRUE), zero = sum(x == 0, na.rm = TRUE),
    outlier_pct = round(100 * mean(outliers, na.rm = TRUE), 2)
  )
})
lines <- c(lines, "## 4. High-cardinality numeric columns", "",
  if (nrow(num_stats)) md_table(num_stats) else "No high-cardinality numeric columns found.", "")

# 5. High-cardinality datetime ranges.
dt_names <- col_info |> filter(type == "datetime", unique > low_card_threshold) |> pull(name)
dt_stats <- map_dfr(dt_names, \(nm) {
  x <- as_datetime(df[[nm]])
  tibble(
    name = nm, earliest = format(min(x, na.rm = TRUE), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    latest = format(max(x, na.rm = TRUE), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    span_days = round(as.numeric(difftime(max(x, na.rm = TRUE), min(x, na.rm = TRUE), units = "days")), 3),
    missing = sum(is.na(x))
  )
})
lines <- c(lines, "## 5. High-cardinality datetime columns", "",
  if (nrow(dt_stats)) md_table(dt_stats) else "No high-cardinality datetime columns found.", "")

# 6. High-cardinality strings: lengths, blanks and modes.
str_names <- col_info |> filter(type == "string", unique > low_card_threshold) |> pull(name)
str_stats <- map_dfr(str_names, \(nm) {
  x <- df[[nm]]
  tab <- table(missing_label(x), useNA = "ifany")
  mode <- names(tab)[[which.max(tab)]]
  tibble(
    name = nm, shortest = min(nchar(x), na.rm = TRUE), longest = max(nchar(x), na.rm = TRUE),
    empty = sum(!is.na(x) & x == "", na.rm = TRUE),
    whitespace_only = sum(!is.na(x) & str_detect(x, "^\\s+$"), na.rm = TRUE),
    mode = mode, mode_pct = round(100 * max(tab) / nrow(df), 2)
  )
})
lines <- c(lines, "## 6. High-cardinality string columns", "",
  if (nrow(str_stats)) md_table(str_stats) else "No high-cardinality string columns found.", "")

# 7. Correlation alerts, upper triangle only and excluding perfect self-like constants.
corr_names <- col_info |> filter(type == "numeric", unique > 1) |> pull(name)
pairs <- if (length(corr_names) >= 2) as_tibble(t(combn(corr_names, 2)), .name_repair = "minimal") else tibble(V1 = character(), V2 = character())
names(pairs) <- c("x", "y")
corr_alerts <- map_dfr(seq_len(nrow(pairs)), \(i) {
  r <- cor(df[[pairs$x[[i]]]], df[[pairs$y[[i]]]], use = "pairwise.complete.obs")
  if (is.na(r) || abs(r) <= corr_threshold || abs(r) >= 1) return(NULL)
  tibble(x = pairs$x[[i]], y = pairs$y[[i]], pearson = round(r, 5))
})
lines <- c(lines, "## 7. Correlation alerts", "",
  if (nrow(corr_alerts)) md_table(corr_alerts) else "No non-perfect numeric pairs with |r| > 0.99 found.", "")

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
con <- file(output, open = "wt", encoding = "UTF-8")
writeLines(lines, con, useBytes = TRUE)
close(con)
cat("inspection ->", output, "\n")
