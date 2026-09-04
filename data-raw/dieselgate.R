# data-raw/dieselgate.R
#
# Reproducible fetch of the bundled `dieselgate` dataset.
#
# Provenance
# ----------
#   Source:      Yahoo Finance daily prices, via tidyquant::tq_get.
#   Firms:       Volkswagen AG ordinary shares (VOW.DE, Xetra)
#                Porsche Automobil Holding SE    (PAH3.DE, Xetra)
#                BMW AG                          (BMW.DE, Xetra)
#                Mercedes-Benz Group AG          (MBG.DE, Xetra)
#   Benchmark:   DAX performance index           (^GDAXI)
#   Groups:      "VW Group"  -> VOW.DE, PAH3.DE  (directly implicated)
#                "Other"     -> BMW.DE, MBG.DE   (peer automakers)
#   Event:       2015-09-18 -- U.S. EPA issues the Notice of Violation to
#                Volkswagen ("dieselgate"). A Friday; the price crash lands
#                on the following trading days.
#   Date range:  2014-06-01 to 2015-11-01 (covers a ~250-trading-day
#                estimation window plus a [-10, +10] event window with margin).
#   Access date: 2026-09-04
#   License:     Yahoo Finance daily adjusted prices. Small illustrative
#                sample bundled for academic / demonstration use only.
#
# To reproduce: run `Rscript data-raw/dieselgate.R` from the package root with
# tidyquant and usethis installed and a network connection.

library(EventStudy)

firm_tickers <- c("VOW.DE", "PAH3.DE", "BMW.DE", "MBG.DE")
index_ticker <- "^GDAXI"
from_date    <- "2014-06-01"
to_date      <- "2015-11-01"
event_date   <- "2015-09-18"

# --- Fetch firm prices (all 4 tickers in one tq_get call) --------------------
if (!requireNamespace("tidyquant", quietly = TRUE)) {
  stop("tidyquant is required to regenerate the dieselgate dataset. ",
       "Install it with: install.packages('tidyquant')")
}

firm_raw_list <- lapply(firm_tickers, function(ticker) {
  raw <- download_stock_data(ticker, from = from_date, to = to_date)
  if (nrow(raw) < 200) {
    message("WARNING: ", ticker, " returned only ", nrow(raw), " rows — check ticker validity.")
  }
  tibble::as_tibble(raw)
})
names(firm_raw_list) <- firm_tickers

# Combine all firms into a single tibble (union of rows by symbol/date/adjusted)
firm <- dplyr::bind_rows(firm_raw_list)

# --- Fetch benchmark index prices --------------------------------------------
index <- tibble::as_tibble(
  download_stock_data(index_ticker, from = from_date, to = to_date)
)

# --- Assemble the frozen object ----------------------------------------------
# Four-row request tibble: 2 VW Group firms (event_id 1-2) + 2 Other (3-4).
# event_id 1 is VOW.DE so legacy code using get_ar(1L) / get_car(1L) still
# targets the core VW crash.
request <- tibble::tibble(
  event_id                 = 1L:4L,
  firm_symbol              = firm_tickers,
  index_symbol             = rep(index_ticker, 4L),
  event_date               = rep(format(as.Date(event_date), "%d.%m.%Y"), 4L),
  group                    = c("VW Group", "VW Group", "Other", "Other"),
  event_window_start       = rep(-10L, 4L),
  event_window_end         = rep(10L, 4L),
  shift_estimation_window  = rep(-11L, 4L),
  estimation_window_length = rep(250L, 4L)
)

dieselgate <- list(
  firm    = firm,
  index   = index,
  request = request,
  meta    = list(
    firm_tickers = firm_tickers,
    groups       = list("VW Group" = c("VOW.DE", "PAH3.DE"),
                        "Other"    = c("BMW.DE", "MBG.DE")),
    index_ticker = index_ticker,
    event_date   = event_date,
    from         = from_date,
    to           = to_date,
    source       = "Yahoo Finance (daily adjusted prices)",
    access_date  = "2026-09-04",
    note         = paste(
      "4-firm, 2-group dieselgate dataset.",
      "VW Group = directly implicated firms (VOW.DE, PAH3.DE);",
      "Other = peer automakers (BMW.DE, MBG.DE).",
      "event_id 1 is VOW.DE for backward compatibility."
    )
  )
)

# --- Freeze -------------------------------------------------------------------
if (requireNamespace("usethis", quietly = TRUE)) {
  usethis::use_data(dieselgate, overwrite = TRUE)
} else {
  if (!dir.exists("data")) dir.create("data")
  save(dieselgate, file = "data/dieselgate.rda", compress = "bzip2", version = 2)
}

message("Bundled dieselgate: ",
        length(firm_tickers), " firms (",
        paste(firm_tickers, collapse = ", "), ")",
        " | index=", index_ticker,
        " | firm rows=", nrow(firm),
        " | index rows=", nrow(index))
