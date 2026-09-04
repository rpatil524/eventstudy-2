#' Volkswagen "Dieselgate" Event Study Dataset
#'
#' A small, frozen dataset bundling daily prices for Volkswagen AG and the DAX
#' benchmark index around the 2015 "dieselgate" emissions scandal, ready to
#' drive a complete event study (\code{prepare_event_study()} ->
#' \code{fit_model()} -> \code{calculate_statistics()}).
#'
#' The event is the U.S. Environmental Protection Agency's Notice of Violation
#' issued to Volkswagen on \strong{2015-09-18} (a Friday); the share-price
#' crash lands on the following trading days. The bundled window layout uses a
#' 250-trading-day estimation window ending 11 days before the event and an
#' event window of \code{[-10, +10]} trading days.
#'
#' Fitting a market model on this data produces a materially negative
#' event-window cumulative abnormal return, driven by roughly -17\% and -12\%
#' abnormal returns on the first two trading days after the disclosure.
#'
#' @format A named \code{list} with four elements:
#' \describe{
#'   \item{firm}{A tibble of Volkswagen daily prices with columns
#'     \code{symbol} (\code{"VOW.DE"}), \code{date} (character,
#'     \code{"\%d.\%m.\%Y"} format), and \code{adjusted} (numeric adjusted
#'     close).}
#'   \item{index}{A tibble of DAX (\code{"^GDAXI"}) daily prices with the same
#'     \code{symbol} / \code{date} / \code{adjusted} columns, used as the
#'     benchmark / reference market.}
#'   \item{request}{A one-row tibble giving the event-study request
#'     specification with the nine columns expected by
#'     \code{\link{EventStudyTask}}: \code{event_id}, \code{firm_symbol},
#'     \code{index_symbol}, \code{event_date} (\code{"18.09.2015"}),
#'     \code{group}, \code{event_window_start} (-10), \code{event_window_end}
#'     (10), \code{shift_estimation_window} (-11), and
#'     \code{estimation_window_length} (250).}
#'   \item{meta}{A list of provenance metadata: \code{firm_ticker},
#'     \code{index_ticker}, \code{event_date}, \code{from}, \code{to},
#'     \code{source}, and \code{access_date}.}
#' }
#'
#' @details
#' \strong{Firm:} Volkswagen AG ordinary shares (ticker \code{VOW.DE}, Xetra).
#' \strong{Benchmark:} DAX performance index (ticker \code{^GDAXI}).
#' \strong{Date range:} 2014-08-01 to 2015-11-30.
#'
#' @source Yahoo Finance daily adjusted prices, retrieved 2026-09-04 via the
#'   package's own \code{\link{download_stock_data}}. This is a small
#'   illustrative sample bundled for academic / demonstration use only; see
#'   \code{data-raw/dieselgate.R} for the reproducible fetch script.
#'
#' @examples
#' \donttest{
#' data(dieselgate)
#' task <- EventStudyTask$new(dieselgate$firm, dieselgate$index,
#'                            dieselgate$request)
#' task <- run_event_study(task, ParameterSet$new())
#' task$get_car(1L)
#' }
#'
#' @docType data
#' @keywords datasets
#' @name dieselgate
#' @usage data(dieselgate)
"dieselgate"
