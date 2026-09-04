# data-raw/dieselgate.R
#
# Reproducible fetch of the bundled `dieselgate` dataset.
#
# Provenance
# ----------
#   Source:      Yahoo Finance daily prices, via the package's own
#                download_stock_data() (tidyquant::tq_get backend).
#   Firm:        Volkswagen AG ordinary shares  (ticker VOW.DE, Xetra)
#   Benchmark:   DAX performance index           (ticker ^GDAXI)
#   Event:       2015-09-18 -- U.S. EPA issues the Notice of Violation to
#                Volkswagen ("dieselgate"). A Friday; the price crash lands
#                on the following trading days.
#   Date range:  2014-08-01 to 2015-11-30 (covers a ~250-trading-day
#                estimation window plus a [-10, +10] event window with margin).
#   Access date: 2026-09-04
#   License:     Yahoo Finance daily adjusted prices. Small illustrative
#                sample bundled for academic / demonstration use only.
#
# To reproduce: run `Rscript data-raw/dieselgate.R` from the package root with
# tidyquant (or quantmod) and usethis installed and a network connection.

library(EventStudy)

firm_ticker  <- "VOW.DE"   # falls back to VOW3.DE if too sparse (see below)
index_ticker <- "^GDAXI"
from_date    <- "2014-08-01"
to_date      <- "2015-11-30"
event_date   <- "2015-09-18"

# --- Fetch firm prices --------------------------------------------------------
firm_raw <- download_stock_data(firm_ticker, from = from_date, to = to_date)

# Fall back to VOW3.DE (preferred/common shares) if the ordinary share is sparse.
if (nrow(firm_raw) < 200) {
  message("VOW.DE returned only ", nrow(firm_raw),
          " rows; falling back to VOW3.DE.")
  firm_ticker <- "VOW3.DE"
  firm_raw <- download_stock_data(firm_ticker, from = from_date, to = to_date)
}

# --- Fetch benchmark index prices --------------------------------------------
index_raw <- download_stock_data(index_ticker, from = from_date, to = to_date)

# --- Assemble the frozen object ----------------------------------------------
# The dataset is a list carrying the three tibbles that feed
# EventStudyTask$new(firm, index, request), plus provenance metadata. Columns
# match the package's expected schema exactly: symbol / date (dd.mm.yyyy) /
# adjusted for the price tibbles, and the nine EventStudyTask request columns.

firm <- tibble::as_tibble(firm_raw)
index <- tibble::as_tibble(index_raw)

request <- tibble::tibble(
  event_id                 = 1L,
  firm_symbol              = firm_ticker,
  index_symbol             = index_ticker,
  event_date               = format(as.Date(event_date), "%d.%m.%Y"),
  group                    = "Automotive",
  event_window_start       = -10L,
  event_window_end         = 10L,
  shift_estimation_window  = -11L,   # estimation window ends 11 days before event
  estimation_window_length = 250L
)

dieselgate <- list(
  firm    = firm,
  index   = index,
  request = request,
  meta    = list(
    firm_ticker  = firm_ticker,
    index_ticker = index_ticker,
    event_date   = event_date,
    from         = from_date,
    to           = to_date,
    source       = "Yahoo Finance (daily adjusted prices)",
    access_date  = "2026-09-04"
  )
)

# --- Freeze -------------------------------------------------------------------
if (requireNamespace("usethis", quietly = TRUE)) {
  usethis::use_data(dieselgate, overwrite = TRUE)
} else {
  if (!dir.exists("data")) dir.create("data")
  save(dieselgate, file = "data/dieselgate.rda", compress = "bzip2")
}

message("Bundled dieselgate: firm=", firm_ticker,
        " (", nrow(firm), " rows), index=", index_ticker,
        " (", nrow(index), " rows).")
