# ==============================================================================
# 作图工艺：一张图的底线，不含配色。
#
# 配色是这一项研究的选择（哪个条件用哪个颜色），它住在调用方；这里只有每张图都必须
# 满足的工艺。拆开的原因很实际：配色会随研究换，工艺不会。
#
# 借自 tidytuesday/assets/tt_theme.R 的东西，只借能在这里兑现的：
#   - 标题说洞察、副标题说口径、脚注说来源与样本量，三者对齐到 plot 而不是 panel
#   - 字号阶梯单调、种类有上限，不许在各个 geom 里现发明字号
#   - 自检靠退出码，不靠打印一句"请注意"
#
# 文字主次是硬要求，不是风格偏好。一张图只允许三层文字重量：
#   粗体墨色一行  = 结论（标题）
#   灰色一行      = 这句话怎么读：点、条、虚线各是什么（副标题）
#   极浅小字两行  = 来源与样本量（脚注）
# 第三层之后不再加句子。设计理由、口径链、定义一律留在正文与 studies/<id>/，图里不承载——
# 脚注堆到三四个短句时读者已经放弃读了，而真正该看的是标题。
#
# 这条规则是被自己的输出逼出来的：上一版的每张图都有"一句话结论 + 两句副标题 +
# 两三句脚注"，还把只属于表格范围说明的 raw->plotted 差塞进图注，图注于是承载了
# 一个它管不着的信息。
#
# 不借的：页面重量预算、HTML 内嵌图大小、逐周配色框架 —— 那是自包含 qmd 的约束，
# 这个仓库导出的是几张 PNG，抄过来只是负担。
#
# Run from the project root.
# ==============================================================================

suppressPackageStartupMessages(library(ggplot2))

# ---- 字体事实：本机已装 Segoe UI / Consolas；家族上限 2，按角色分工 ----------
ASSAY_FONT <- "Segoe UI" # 标题、正文
ASSAY_MONO <- "Consolas" # 数字与标签，让"数据"和"话语"分开

# 阶梯单调递减且相邻可辨。全图出现的字号种类不得超过 length(ASSAY_TYPE)。
ASSAY_TYPE <- c(
  title = 16,
  subtitle = 12,
  axis_title = 10.5,
  axis_text = 9,
  annot = 8,
  caption = 7.5
)
ASSAY_TYPE_MAX <- length(ASSAY_TYPE)
ASSAY_FAMILY_MAX <- 2L
ASSAY_CAPTION_WIDTH <- 96 # 脚注折行宽度：超过会被画布右缘裁掉，踩过

# 导出必须显式给宽高与 dpi，不依赖默认值；bg 与主题底色一致。
ASSAY_EXPORT <- list(dpi = 240, bg = "#FFFFFF")

# ---- 主题工厂 ---------------------------------------------------------------
assay_theme <- function(
  ink = "#141414",
  body = "#4A4A4A",
  grid = "#E6E6E6",
  scale = 1
) {
  ty <- ASSAY_TYPE * scale
  theme_minimal(base_size = ty[["axis_title"]], base_family = ASSAY_FONT) +
    theme(
      plot.background = element_rect(fill = ASSAY_EXPORT$bg, colour = NA),
      panel.background = element_rect(fill = ASSAY_EXPORT$bg, colour = NA),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.title = element_text(
        colour = ink,
        face = "bold",
        size = ty[["title"]],
        hjust = 0,
        margin = margin(b = 4)
      ),
      plot.subtitle = element_text(
        colour = body,
        size = ty[["subtitle"]],
        hjust = 0,
        margin = margin(b = 14)
      ),
      plot.caption = element_text(
        colour = body,
        size = ty[["caption"]],
        hjust = 0,
        margin = margin(t = 12)
      ),
      text = element_text(colour = body, size = ty[["axis_text"]]),
      axis.title = element_text(colour = body, size = ty[["axis_title"]]),
      axis.text = element_text(colour = body, size = ty[["axis_text"]]),
      legend.position = "top",
      legend.justification = "left",
      legend.title = element_blank(),
      legend.text = element_text(size = ty[["annot"]]),
      strip.text = element_text(
        colour = ink,
        face = "bold",
        size = ty[["axis_title"]],
        hjust = 0
      ),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = grid, linewidth = 0.3),
      panel.spacing = unit(1.4, "lines"),
      plot.margin = margin(16, 20, 12, 16)
    )
}

# 图内数字用等宽字体：数字要对齐看，比例字体在点图里会晃。
assay_mono <- function(...) element_text(family = ASSAY_MONO, ...)

# ---- 口径链：原始 N -> 入图 n，差额必须解释 ---------------------------------
# 用在**表格输出**上，不用在图注上。图注里写这个是错的：图注说清"这些点是什么"就够；
# 一个不属于本图的差额写进去，读者会去找那 42 条被"少画"的点。
assay_flow <- function(raw, kept, ...) {
  why <- unlist(list(...))
  sprintf(
    "raw %d -> plotted %d%s",
    raw,
    kept,
    if (length(why)) paste0(" (", paste(why, collapse = "; "), ")") else ""
  )
}

# 脚注：来源 + 样本量，两行封顶，固定折行宽度（超过会被画布右缘裁掉，踩过）。
# 刻意不接受 note —— 需要解释的东西属于副标题，不属于脚注。
assay_source <- function(what, n = NULL, width = ASSAY_CAPTION_WIDTH) {
  parts <- paste0(
    "Source: ",
    what,
    if (!is.null(n)) paste0("  \u00b7  n = ", n) else ""
  )
  paste(strwrap(parts, width = width), collapse = "\n")
}

# ---- 排版自检：字号必须来自阶梯 ---------------------------------------------
# 返回逐元素表；通过判据 = 全部 in_ladder 且种类数 <= 阶梯长度 且家族数 <= 2。
# 调用方负责把它变成退出码 —— 只打印一行提示的自检等于没有自检。
assay_audit <- function(p, allowed = ASSAY_TYPE, tol = 0.05) {
  rows <- p$theme |>
    keep(\(e) inherits(e, "element_text")) |>
    imap(\(e, nm) {
      sz <- e$size
      if (is.null(sz) || inherits(sz, "rel")) {
        sz <- NA_real_
      } else {
        sz <- as.numeric(sz)
      }
      tibble::tibble(
        element = nm,
        size = sz,
        family = if (is.null(e$family)) {
          NA_character_
        } else {
          as.character(e$family)
        }
      )
    }) |>
    list_rbind()

  if (nrow(rows) == 0) {
    return(rows)
  }
  rows |>
    dplyr::mutate(
      in_ladder = is.na(size) |
        vapply(size, \(s) any(abs(s - allowed) < tol), logical(1))
    ) |>
    dplyr::arrange(element)
}

assay_audit_ok <- function(p) {
  a <- assay_audit(p)
  n_sizes <- length(unique(stats::na.omit(a$size)))
  n_fams <- length(unique(stats::na.omit(a$family)))
  ok <- all(a$in_ladder) &&
    n_sizes <= ASSAY_TYPE_MAX &&
    n_fams <= ASSAY_FAMILY_MAX
  list(
    ok = ok,
    sizes = n_sizes,
    families = n_fams,
    table = a,
    off_ladder = a |> dplyr::filter(!in_ladder)
  )
}
