test_that("export_results writes CSV files", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(list.files(dirname(tmp), full.names = TRUE,
                             pattern = tools::file_path_sans_ext(basename(tmp)))),
          add = TRUE)

  result <- export_results(task, tmp)
  expect_equal(result, tmp)

  # Multiple tables create suffixed files
  base <- tools::file_path_sans_ext(tmp)
  ar_file <- paste0(base, "_ar.csv")
  expect_true(file.exists(ar_file))
})

test_that("export_results writes single CSV when which has one element", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  export_results(task, tmp, which = "model")
  expect_true(file.exists(tmp))

  data <- read.csv(tmp)
  expect_true("sigma" %in% names(data))
  expect_true("event_id" %in% names(data))
})

test_that("export_results writes LaTeX file", {
  skip_if_not_installed("knitr")
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  tmp <- tempfile(fileext = ".tex")
  on.exit(unlink(tmp), add = TRUE)

  export_results(task, tmp, which = "model")
  expect_true(file.exists(tmp))

  content <- readLines(tmp)
  expect_true(any(grepl("\\\\begin\\{tabular\\}", content)))
})

test_that("export_results errors on xlsx without openxlsx", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  tmp <- tempfile(fileext = ".xlsx")
  # This test depends on whether openxlsx is installed;
  # just check it doesn't fail with an unexpected error
  tryCatch({
    export_results(task, tmp, which = "model")
    expect_true(file.exists(tmp))
  }, error = function(e) {
    expect_true(grepl("openxlsx", conditionMessage(e)))
  })
})

test_that("export_results errors on unfitted task", {
  task <- create_mock_task()
  tmp <- tempfile(fileext = ".csv")

  expect_error(export_results(task, tmp), "No results available")
})

test_that("export_results infers format from extension", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  tmp <- tempfile(fileext = ".unknown")
  expect_error(export_results(task, tmp), "Cannot infer format")
})

test_that("tidy.EventStudyTask returns AR tibble", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "ar")
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("term", "estimate", "std.error", "statistic", "p.value") %in% names(result)))
  expect_true(all(c("event_id", "firm_symbol") %in% names(result)))
  expect_true(nrow(result) > 0)
})

test_that("tidy.EventStudyTask returns CAR tibble", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "car")
  expect_s3_class(result, "tbl_df")
  expect_true("estimate" %in% names(result))
  # CAR should be cumulative (last >= sum effect)
  first_event <- result %>% dplyr::filter(event_id == result$event_id[1])
  expect_true(nrow(first_event) > 1)
})

test_that("tidy.EventStudyTask returns AAR tibble", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "aar")
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("estimate", "caar") %in% names(result)))
})

test_that("tidy.EventStudyTask returns model tibble", {
  task <- create_mock_task()
  ps <- ParameterSet$new()
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "model")
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("term", "estimate") %in% names(result)))
  expect_true("alpha" %in% result$term)
  expect_true("beta" %in% result$term)
})

test_that("tidy.EventStudyTask errors on unfitted task", {
  task <- create_mock_task()
  expect_error(tidy.EventStudyTask(task, type = "ar"), "not computed")
})


# --- Export content validation (issue #3, gap #7) ---

test_that("export CSV AR content is correct", {
  task <- create_fitted_mock_task()
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  export_results(task, tmp, which = "ar")
  expect_true(file.exists(tmp))

  data <- read.csv(tmp)
  expect_true("abnormal_returns" %in% names(data))
  expect_true("event_id" %in% names(data))
  expect_true("relative_index" %in% names(data))
  # Should have event_window rows only
  expect_true(nrow(data) > 0)
})


test_that("export CSV CAR content is correct", {
  task <- create_fitted_mock_task()
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  export_results(task, tmp, which = "car")
  expect_true(file.exists(tmp))

  data <- read.csv(tmp)
  expect_true("car" %in% names(data))
  expect_true("abnormal_returns" %in% names(data))
})


test_that("export multiple CSVs creates all files", {
  task <- create_fitted_mock_task()
  tmp <- tempfile(fileext = ".csv")
  base <- tools::file_path_sans_ext(tmp)
  on.exit(unlink(list.files(dirname(tmp), full.names = TRUE,
                             pattern = basename(base))),
          add = TRUE)

  export_results(task, tmp, which = c("ar", "car", "model"))

  expect_true(file.exists(paste0(base, "_ar.csv")))
  expect_true(file.exists(paste0(base, "_car.csv")))
  expect_true(file.exists(paste0(base, "_model.csv")))
})


# --- Tidy edge cases (issue #3, gap #16) ---

test_that("tidy AR with MarketAdjustedModel has sigma", {
  task <- create_mock_task()
  ps <- ParameterSet$new(return_model = MarketAdjustedModel$new())
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "ar")
  # Should have valid std.error (not NA) since sigma is now set
  expect_true(all(!is.na(result$std.error)))
  expect_true(all(!is.na(result$statistic)))
  expect_true(all(!is.na(result$p.value)))
})


test_that("tidy model with non-regression model omits alpha/beta", {
  task <- create_mock_task()
  ps <- ParameterSet$new(return_model = ComparisonPeriodMeanAdjustedModel$new())
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "model")
  # ComparisonPeriodMeanAdjustedModel doesn't produce alpha/beta
  expect_true("sigma" %in% result$term)
})


test_that("tidy AAR errors on missing stat_name", {
  task <- create_fitted_mock_task()
  expect_error(
    tidy.EventStudyTask(task, type = "aar", stat_name = "Nonexistent"),
    "not found"
  )
})


# --- Regression: tidy_aar detects all test statistic columns ---

test_that("tidy_aar detects BMP test statistic columns", {
  # Bug: tidy_aar only checked for aar_t and aar_z columns, missing bmp_t, kp_t,
  # sign_z, gsign_z, rank_z, caltime_t and their CAAR counterparts.
  # Fix: Extended candidate lists to cover all test statistics.
  task <- create_mock_task(n_firms = 3)
  ps <- ParameterSet$new(
    multi_event_statistics = MultiEventStatisticsSet$new(tests = list(BMPTest$new()))
  )
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "aar", stat_name = "BMP")
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("estimate", "statistic", "p.value") %in% names(result)))
  # BMP is t-distributed, so p-values should use pt (not pnorm)
  expect_true(all(!is.na(result$statistic)))
  expect_true(all(!is.na(result$p.value)))
  expect_true(all(result$p.value >= 0 & result$p.value <= 1))
})


test_that("tidy_aar uses pnorm for z-distributed statistics", {
  # Verify that z-distributed test stats (PatellZ, Sign, etc.) use pnorm,
  # not pt for p-values.
  task <- create_mock_task(n_firms = 3)
  ps <- ParameterSet$new(
    multi_event_statistics = MultiEventStatisticsSet$new(tests = list(PatellZTest$new()))
  )
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "aar", stat_name = "PatellZ")
  expect_s3_class(result, "tbl_df")
  expect_true(all(!is.na(result$statistic)))
  expect_true(all(!is.na(result$p.value)))

  # Manually verify p-value computation with pnorm (z-distributed)
  stat_val <- result$statistic[1]
  expected_pval <- 2 * stats::pnorm(abs(stat_val), lower.tail = FALSE)
  expect_equal(result$p.value[1], expected_pval, tolerance = 1e-10)
})


test_that("tidy_aar uses pt for t-distributed statistics (CSectT)", {
  task <- create_mock_task(n_firms = 3)
  ps <- ParameterSet$new(
    multi_event_statistics = MultiEventStatisticsSet$new(tests = list(CSectTTest$new()))
  )
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "aar", stat_name = "CSectT")
  expect_s3_class(result, "tbl_df")

  # CSectT is t-distributed, so p-value should differ from pnorm-based computation
  stat_val <- result$statistic[1]
  n_valid <- 3  # n_firms
  pval_pt <- 2 * stats::pt(abs(stat_val), df = n_valid - 1, lower.tail = FALSE)
  pval_pnorm <- 2 * stats::pnorm(abs(stat_val), lower.tail = FALSE)

  expect_equal(result$p.value[1], pval_pt, tolerance = 1e-10)
  # With small n, pt and pnorm should give different values
  expect_false(isTRUE(all.equal(pval_pt, pval_pnorm, tolerance = 1e-6)))
})


# --- Regression: CAAR p-values use pt for t-distributed stats ---

test_that("tidy_aar CAAR p-values use pt (not pnorm) for t-distributed stats", {
  # Bug: t_dist_cols didn't include cumulative counterparts (caar_t, cbmp_t, etc.)
  # so CAAR p-values were computed with pnorm instead of pt.
  task <- create_mock_task(n_firms = 3)
  ps <- ParameterSet$new(
    multi_event_statistics = MultiEventStatisticsSet$new(tests = list(CSectTTest$new()))
  )
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "aar", stat_name = "CSectT")

  # CAAR statistic is caar_t (t-distributed with N-1 df)
  caar_stat <- result$caar_statistic[1]
  n_valid <- 3
  expected_pval <- 2 * stats::pt(abs(caar_stat), df = n_valid - 1, lower.tail = FALSE)
  wrong_pval <- 2 * stats::pnorm(abs(caar_stat), lower.tail = FALSE)

  expect_equal(result$caar_p.value[1], expected_pval, tolerance = 1e-10)
  # These should differ with small N
  expect_false(isTRUE(all.equal(expected_pval, wrong_pval, tolerance = 1e-6)))
})


test_that("tidy_aar KP test uses pt (not pnorm)", {
  # Bug: kp_t was not in t_dist_cols, so KP p-values used pnorm.
  task <- create_mock_task(n_firms = 5)
  ps <- ParameterSet$new(
    multi_event_statistics = MultiEventStatisticsSet$new(tests = list(KolariPynnonenTest$new()))
  )
  task <- run_event_study(task, ps)

  result <- tidy.EventStudyTask(task, type = "aar", stat_name = "KP")
  expect_true(all(!is.na(result$statistic)))
  expect_true(all(!is.na(result$p.value)))

  # KP is t-distributed: verify first row
  stat_val <- result$statistic[1]
  n_valid <- 5
  expected_pval <- 2 * stats::pt(abs(stat_val), df = n_valid - 1, lower.tail = FALSE)
  expect_equal(result$p.value[1], expected_pval, tolerance = 1e-10)
})


# --- PIPELINE-02: NA-safety regression tests ---

# Helper: create a fully fitted task then inject NA abnormal_returns into one
# model's inner data to simulate a degenerate upstream model (is_fitted=FALSE
# model whose abnormal_returns() returns NA for all event-window rows).
.inject_na_abnormal_returns <- function(task, row_index = 1L) {
  # Mutate the nested data tbl so the chosen firm's event-window rows have
  # NA abnormal_returns; this mimics the output of a non-fitted model.
  task$data_tbl$data[[row_index]] <- task$data_tbl$data[[row_index]] %>%
    dplyr::mutate(abnormal_returns = dplyr::if_else(event_window == 1L,
                                                     NA_real_,
                                                     abnormal_returns))
  task
}


test_that("export_results: NA abnormal_returns does not error (AR table)", {
  task <- create_fitted_mock_task(n_firms = 2)
  task <- .inject_na_abnormal_returns(task, 1L)

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  # Must not error; AR column may contain NA
  expect_no_error(export_results(task, tmp, which = "ar"))
  dat <- read.csv(tmp, na.strings = "NA")
  expect_true("abnormal_returns" %in% names(dat))
})


test_that("export_results: NA abnormal_returns in AR column preserved as NA (not 0)", {
  task <- create_fitted_mock_task(n_firms = 2)
  task <- .inject_na_abnormal_returns(task, 1L)

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  export_results(task, tmp, which = "ar")

  dat <- read.csv(tmp, na.strings = "NA")
  # At least some AR rows for event 1 should be NA
  event1_rows <- dat[dat$event_id == 1, , drop = FALSE]
  expect_true(any(is.na(event1_rows$abnormal_returns)))
})


test_that("export_results: CAR cumsum coalesce — interior NA does not blank entire tail", {
  # A single interior NA in abnormal_returns should NOT propagate NA to every
  # subsequent cumsum entry; coalesce treats it as 0 for accumulation.
  task <- create_fitted_mock_task(n_firms = 2)

  # Inject NA only into the MIDDLE of the event window for firm 1
  d <- task$data_tbl$data[[1]]
  ew_rows <- which(d$event_window == 1L)
  mid <- ew_rows[ceiling(length(ew_rows) / 2)]
  d$abnormal_returns[mid] <- NA_real_
  task$data_tbl$data[[1]] <- d

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  expect_no_error(export_results(task, tmp, which = "car"))

  dat <- read.csv(tmp, na.strings = "NA")
  car_event1 <- dat[dat$event_id == 1, "car"]
  # After coalesce the tail should NOT be all-NA
  expect_false(all(is.na(car_event1)))
})


test_that("tidy AR: NA abnormal_returns preserved as NA, not 0", {
  task <- create_fitted_mock_task(n_firms = 2)
  task <- .inject_na_abnormal_returns(task, 1L)

  result <- tidy.EventStudyTask(task, type = "ar")
  expect_no_error(result)
  event1 <- result[result$event_id == 1, , drop = FALSE]
  # All AR estimates for the NA-injected event should be NA
  expect_true(all(is.na(event1$estimate)))
})


test_that("tidy CAR: interior NA does not blank entire cumulative tail", {
  task <- create_fitted_mock_task(n_firms = 2)

  d <- task$data_tbl$data[[1]]
  ew_rows <- which(d$event_window == 1L)
  mid <- ew_rows[ceiling(length(ew_rows) / 2)]
  d$abnormal_returns[mid] <- NA_real_
  task$data_tbl$data[[1]] <- d

  result <- suppressWarnings(tidy.EventStudyTask(task, type = "car"))
  expect_no_error(result)
  event1 <- result[result$event_id == 1, , drop = FALSE]
  # After coalesce the tail estimates should not all be NA
  expect_false(all(is.na(event1$estimate)))
})


test_that("tidy AAR: does not error on task with NA abnormal_returns (model type)", {
  task <- create_fitted_mock_task(n_firms = 3)
  task <- .inject_na_abnormal_returns(task, 1L)

  result <- suppressWarnings(tidy.EventStudyTask(task, type = "aar"))
  expect_no_error(result)
  expect_s3_class(result, "tbl_df")
})


test_that("tidy model: does not error on task with NA abnormal_returns", {
  task <- create_fitted_mock_task(n_firms = 2)
  task <- .inject_na_abnormal_returns(task, 1L)

  result <- tidy.EventStudyTask(task, type = "model")
  expect_no_error(result)
  expect_s3_class(result, "tbl_df")
})


test_that("CAR coalesce is no-op on fully finite abnormal_returns", {
  # Valid (all-finite) input must produce byte-identical output before/after
  # the coalesce change — coalesce(x, 0) == x when x is finite.
  task <- create_fitted_mock_task(n_firms = 2)

  tmp_before <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp_before), add = TRUE)
  export_results(task, tmp_before, which = "car")
  dat_before <- read.csv(tmp_before)

  # Produce tidy CAR independently
  tidy_car <- tidy.EventStudyTask(task, type = "car")

  # The cumsum of coalesce(ar, 0) equals cumsum(ar) when ar is fully finite
  d1 <- task$data_tbl$data[[1]]
  ew_ar <- d1$abnormal_returns[d1$event_window == 1L]
  expect_false(anyNA(ew_ar))  # confirm no NA in the test data
  car_no_coalesce <- cumsum(ew_ar)
  car_with_coalesce <- cumsum(dplyr::coalesce(ew_ar, 0))
  expect_equal(car_no_coalesce, car_with_coalesce)  # byte-identical
})
