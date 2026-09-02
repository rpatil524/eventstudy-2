# Phase 1: Contract Foundation — Research

**Researched:** 2026-09-02
**Domain:** R package robustness — degenerate-input contract, R6 class architecture, roxygen2 doc topics
**Confidence:** HIGH (all findings from direct file reads this session)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Mode switch: `ParameterSet` field + package-option fallback (`options(eventstudy.degenerate_handling=)`), resolved by one internal helper `.resolve_degenerate_mode()`. Default = `"lenient"`. Values: `"lenient"` / `"strict"`.
- Strict mode: `stop()` error containing component name + offending event_id/firm_symbol + reason.
- Lenient mode: exactly one warning per (event_id, firm_symbol) per fit call; is_fitted=FALSE; NA cascade downstream.
- Degenerate conditions: <2 finite estimation obs, zero/near-zero variance (sd < .Machine$double.eps), single-event group, NA propagation.
- Reference component: MarketModel. New file `R/contract.R` holds roxygen contract doc (`@name degenerate-input-contract`) + shared internal helpers, reused by Phases 2-3.
- Refactor MarketModel's existing scattered guards onto the helper.

### Claude's Discretion
(None specified — all contract decisions are locked.)

### Deferred Ideas (OUT OF SCOPE)
- Perfect collinearity / singular design handling → Phase 3 (PIPELINE-03).
- Applying the contract to all other models and test statistics → Phase 2.
- Regression test matrix and R CMD check gate → Phase 4.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CONTRACT-01 | A single documented degenerate-input contract defines expected behavior for insufficient observations (<2 estimation obs), zero variance, single-event groups, and NA propagation | `R/contract.R` with roxygen `@name degenerate-input-contract` + `.handle_degenerate()` helper |
| CONTRACT-02 | A configurable mode switch selects strict vs lenient handling (via ParameterSet field and/or package option), with a documented default | New `degenerate_handling` field on `ParameterSet`; `.resolve_degenerate_mode()` helper reads field → option → "lenient" |
| CONTRACT-03 | In strict mode, degenerate input raises a descriptive error naming the offending event_id and/or firm_symbol | `.handle_degenerate()` calls `stop()` with context; event_id/firm_symbol passed as arguments since they are NOT inside the per-event data_tbl (see threading section) |
| CONTRACT-04 | In lenient mode, degenerate input sets `is_fitted = FALSE`, propagates NA through downstream statistics, and emits exactly one clear warning (no duplicate warnings per event) | De-duplication is natural: fit() is called once per (event_id, firm_symbol) row; one call = one warning |
| CONTRACT-05 | Behavior on valid (non-degenerate) input is unchanged from current release | Verified by snapshot test comparing MarketModel outputs before/after refactor on `create_mock_model_data()` fixture |
</phase_requirements>

---

## Summary

Phase 1 establishes the degenerate-input contract for the EventStudy R package. The work has three concrete deliverables: (1) a new `R/contract.R` file containing a roxygen doc topic (`?degenerate-input-contract`) and two internal helper functions, (2) a new `degenerate_handling` field on `ParameterSet`, and (3) a refactored `MarketModel` that replaces its scattered inline guards with the shared helpers. The test deliverable (CONTRACT-05) confirms identical numerical output on valid inputs before and after the refactor.

The most important architectural finding is the **mode-threading gap**: `fit_model()` (in `R/execute.R`) passes only the cloned model object plus the inner per-event `data_tbl` to `model$fit()`. The `ParameterSet` is not passed into the model. The event_id and firm_symbol keys live in the *outer* `task$data_tbl` row, not in the inner `data` tibble that arrives at `MarketModel$fit()`. This means the mode and the identifying keys must be threaded into the model explicitly before `fit()` is called — the cleanest solution is to store them as fields on the cloned model during `.initialize_and_fit_model()`.

**Primary recommendation:** Thread `degenerate_mode`, `event_id`, and `firm_symbol` as fields on the cloned model inside `.initialize_and_fit_model()` (the existing internal glue function in `execute.R`). The model reads `self$degenerate_mode`, `self$event_id`, `self$firm_symbol` inside `fit()` and passes them to `.handle_degenerate()`. This requires no new call sites and no change to the `fit()` signature.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Contract documentation | `R/contract.R` (new file) | — | Roxygen doc topic + helpers centralised in one file |
| Mode resolution | `R/contract.R` `.resolve_degenerate_mode()` | `ParameterSet` field | Single choke point; no component reads raw option |
| Degenerate signalling | `R/contract.R` `.handle_degenerate()` | `MarketModel$fit()` calls it | Uniform behavior across current and future components |
| Mode storage on ParameterSet | `R/parameter_set.R` | — | Existing validated config object; `lock_objects=FALSE` permits new field |
| Mode threading into model | `R/execute.R` `.initialize_and_fit_model()` | — | Only callsite where model is cloned before fit; cleanest injection point |
| MarketModel guard refactor | `R/models.R` `MarketModel$fit()` | `ModelBase$calculate_forecast_error_correction()` | Inline guards replaced; base-class FEC guard stays (it handles fallback, not degeneracy) |
| Contract tests | `tests/testthat/test_contract.R` (new) | `tests/testthat/test_models.R` (existing) | New file for strict/lenient/regression tests |

---

## Standard Stack

No new packages are introduced. All implementation uses the existing stack.

### Core (already in DESCRIPTION)
| Library | Version | Purpose |
|---------|---------|---------|
| R6 | ≥2.5.1 | R6Class definitions — `ParameterSet`, `ModelBase`, `MarketModel` |
| testthat | ≥3.0.0 | 3e test framework; `test_that`, `expect_error`, `expect_warning`, `expect_equal` |
| roxygen2 | 7.3.3 | Generates NAMESPACE and Rd files from `#'` tags |

### Installation
None — this phase adds no new dependencies.

### Version verification
No new packages. The constraint is that no new CRAN NOTEs/WARNINGs are introduced.

---

## Package Legitimacy Audit

No new packages are installed in this phase. Section not applicable.

---

## Architecture Patterns

### System Architecture Diagram

```
User calls: run_event_study(task, parameter_set)
      |
      v
prepare_event_study(task, parameter_set)      [R/prepare_event_study.R]
      |
      v
fit_model(task, parameter_set)                [R/execute.R:29]
  |
  purrr::map(data, .initialize_and_fit_model, return_model=parameter_set$return_model)
  |
  .initialize_and_fit_model(data_tbl, return_model)    [R/execute.R:46]
    |
    cloned = return_model$clone(deep=TRUE)
    cloned$degenerate_mode  <-- SET HERE from parameter_set (Phase 1 adds this)
    cloned$event_id         <-- SET HERE from outer row key  (Phase 1 adds this)
    cloned$firm_symbol      <-- SET HERE from outer row key  (Phase 1 adds this)
    cloned$fit(data_tbl)    [R/models.R:160]
      |
      .handle_degenerate(mode, cond, component, event_id, firm_symbol)  [R/contract.R]
        |--- strict: stop("MarketModel degenerate: event_id=E1, firm=FIRM_A, reason=...")
        |--- lenient: warning("..."); private$.is_fitted <- FALSE; return
      |
      (if non-degenerate) purrr::safely(.estimate_mm_model)(formula, estimation_tbl)
      private$calculate_statistics(data_tbl)
      |
      ModelBase$calculate_forecast_error_correction()   [R/models.R:70]
        (ss_market guard stays — it is a fallback, not a degeneracy signal)
```

The key threading gap: `fit_model()` uses `purrr::map(.x=data, ...)` where `.x=data` is the *inner* nested tibble (rows of price/return data). The outer `task$data_tbl` has columns `event_id`, `group`, `firm_symbol`, `data`, `request`, `model`. The inner `data` tibble does NOT contain `event_id` or `firm_symbol` — they are grouping keys dropped by `tidyr::nest()`. Therefore `.initialize_and_fit_model()` does not currently receive these keys, and `MarketModel$fit()` cannot name the offending event in a warning or error without them being injected beforehand.

### Recommended Project Structure

```
R/
├── contract.R           # NEW: degenerate-input-contract doc topic + helpers
├── parameter_set.R      # MODIFY: add degenerate_handling field
├── execute.R            # MODIFY: inject mode+keys in .initialize_and_fit_model()
├── models.R             # MODIFY: MarketModel$fit() calls .handle_degenerate()
tests/testthat/
├── test_contract.R      # NEW: strict/lenient/regression tests for CONTRACT-01..05
├── helper-mock-data.R   # EXTEND: add degenerate data factory functions
├── test_models.R        # VERIFY: existing tests stay green
├── test_parameter_set.R # EXTEND: add degenerate_handling field tests
```

### Pattern 1: Roxygen Doc-Only Topic

The package uses `EventStudy-package.R` for the package-level topic (`@keywords internal`, `"_PACKAGE"`). A standalone doc-only topic for the contract follows the same roxygen convention using `@name` + `@title` + `@description` attached to a `NULL` assignment. [VERIFIED: R/EventStudy-package.R:37-139]

```r
# R/contract.R

#' Degenerate-Input Contract
#'
#' @name degenerate-input-contract
#' @title Degenerate-Input Contract for EventStudy Models
#'
#' @description
#' The degenerate-input contract defines how all EventStudy return models
#' behave when the estimation data is degenerate. Two modes are supported:
#'
#' \strong{Lenient (default):} The model sets \code{is_fitted = FALSE},
#' emits exactly one \code{warning()} per event, and propagates \code{NA}
#' through abnormal returns and all downstream statistics. No event is
#' silently dropped; zeros are never substituted for NA.
#'
#' \strong{Strict:} The model raises a descriptive \code{stop()} error
#' naming the component, \code{event_id}, and \code{firm_symbol}.
#'
#' Configure via \code{ParameterSet$new(degenerate_handling = "strict")} or
#' \code{options(eventstudy.degenerate_handling = "strict")}.
#'
#' \strong{Degenerate conditions covered:}
#' \itemize{
#'   \item Fewer than 2 finite observations in the estimation window
#'   \item Zero or near-zero variance (\code{sd < .Machine$double.eps})
#'   \item Single-event group (relevant for multi-event statistics — Phase 2)
#'   \item NA propagation from upstream steps
#' }
#'
#' @seealso \code{\link{ParameterSet}}, \code{\link{MarketModel}}
NULL
```

This pattern generates a `?degenerate-input-contract` help page without attaching to any exported symbol. [ASSUMED — verified by analogy with standard roxygen2 doc-only topic convention; no existing `@name`-only topic found in this repo to cite directly. The `NULL` object pattern is standard roxygen2 practice.]

### Pattern 2: ParameterSet Field Addition

`ParameterSet` uses `lock_objects = FALSE` [VERIFIED: R/parameter_set.R:9], which means new public fields can be assigned in `initialize()` without being pre-declared. The existing `study_type = "return"` field [VERIFIED: R/parameter_set.R:21] is an example of a simple string field with a default.

```r
# In ParameterSet$initialize(), add parameter:
initialize = function(return_calculation = SimpleReturn$new(),
                      return_model = MarketModel$new(),
                      single_event_statistics = SingleEventStatisticsSet$new(),
                      multi_event_statistics = MultiEventStatisticsSet$new(),
                      degenerate_handling = NULL) {   # NULL = use .resolve_degenerate_mode()
  # ... existing validation ...
  self$degenerate_handling <- degenerate_handling
}
```

And in `print()`, add a line:
```r
cat("  Degenerate mode:  ", .resolve_degenerate_mode(self$degenerate_handling), "\n")
```

### Pattern 3: Contract Helpers in R/contract.R

```r
# R/contract.R

#' @noRd
.resolve_degenerate_mode <- function(ps_value = NULL) {
  # Priority: ParameterSet field > package option > default "lenient"
  if (!is.null(ps_value)) {
    match.arg(ps_value, c("lenient", "strict"))
    return(ps_value)
  }
  opt <- getOption("eventstudy.degenerate_handling", default = NULL)
  if (!is.null(opt)) {
    match.arg(opt, c("lenient", "strict"))
    return(opt)
  }
  "lenient"
}

#' @noRd
.handle_degenerate <- function(mode, condition, component,
                                event_id = NULL, firm_symbol = NULL,
                                fitted_flag_env = NULL) {
  # Build context string for messages
  ctx <- paste0(component)
  if (!is.null(event_id))    ctx <- paste0(ctx, " [event_id=", event_id, "]")
  if (!is.null(firm_symbol)) ctx <- paste0(ctx, " [firm=", firm_symbol, "]")

  msg <- paste0(ctx, ": ", condition)

  if (mode == "strict") {
    stop(msg, call. = FALSE)
  } else {
    warning(msg, call. = FALSE)
    if (!is.null(fitted_flag_env)) {
      fitted_flag_env$.is_fitted <- FALSE
    }
  }
}
```

### Pattern 4: Mode + Key Threading via .initialize_and_fit_model()

This is the cleanest threading path. The function already clones the model per-event; adding three field assignments before `fit()` requires no signature change anywhere else.

```r
# R/execute.R — updated .initialize_and_fit_model

#' @noRd
.initialize_and_fit_model <- function(data_tbl, return_model,
                                       degenerate_mode = "lenient",
                                       event_id = NULL,
                                       firm_symbol = NULL) {
  cloned_return_model <- return_model$clone(deep = TRUE)
  # Thread contract context — models read these in fit()
  cloned_return_model$degenerate_mode  <- degenerate_mode
  cloned_return_model$event_id         <- event_id
  cloned_return_model$firm_symbol      <- firm_symbol
  cloned_return_model$fit(data_tbl)
  cloned_return_model
}
```

And in `fit_model()`, change the `purrr::map` to `purrr::map2` (or `purrr::pmap`) so that the outer row keys flow in:

```r
fit_model <- function(task, parameter_set) {
  mode <- .resolve_degenerate_mode(parameter_set$degenerate_handling)

  task$data_tbl <- task$data_tbl %>%
    dplyr::mutate(
      model = purrr::pmap(
        list(data = data, event_id = event_id, firm_symbol = firm_symbol),
        function(data, event_id, firm_symbol) {
          .initialize_and_fit_model(
            data,
            parameter_set$return_model,
            degenerate_mode = mode,
            event_id        = event_id,
            firm_symbol     = firm_symbol
          )
        }
      )
    )

  # Calculate abnormal returns (unchanged)
  task$data_tbl <- task$data_tbl %>%
    dplyr::mutate(data = purrr::map2(.x = data, .y = model,
                                      .f = .calculate_abnormal_returns))
  task
}
```

### Pattern 5: MarketModel$fit() Refactored onto Helper

```r
# R/models.R — MarketModel$fit() after refactor

fit = function(data_tbl) {
  # --- Contract guard: insufficient observations ---
  estimation_tbl <- data_tbl %>% dplyr::filter(estimation_window == 1)
  n_valid <- sum(!is.na(estimation_tbl$firm_returns) &
                   !is.na(estimation_tbl$index_returns))
  if (n_valid < 2) {
    .handle_degenerate(
      mode       = .resolve_degenerate_mode(self$degenerate_mode),
      condition  = paste0("insufficient estimation obs (", n_valid, " < 2)"),
      component  = self$model_name,
      event_id   = self$event_id,
      firm_symbol = self$firm_symbol,
      fitted_flag_env = private
    )
    private$.is_fitted <- FALSE
    return(invisible(self))
  }

  # --- Existing: safe lm() execution ---
  safe_mm <- purrr::safely(.f = .estimate_mm_model)
  res <- safe_mm(self$formula, estimation_tbl)
  if (is.null(res$error)) {
    private$.fitted_model <- res$result
    private$.is_fitted <- TRUE
    private$calculate_statistics(data_tbl)
  } else {
    # lm() failure is a degenerate condition (e.g. zero variance causes rank deficiency)
    .handle_degenerate(
      mode       = .resolve_degenerate_mode(self$degenerate_mode),
      condition  = conditionMessage(res$error),
      component  = self$model_name,
      event_id   = self$event_id,
      firm_symbol = self$firm_symbol,
      fitted_flag_env = private
    )
    private$.is_fitted <- FALSE
  }
}
```

### Pattern 6: Warning De-duplication

De-duplication is **naturally guaranteed** by the call architecture: `purrr::map(.x=data, .f=.initialize_and_fit_model)` calls `model$fit(data_tbl)` exactly once per outer row in `task$data_tbl`. Each outer row is uniquely identified by `(event_id, group, firm_symbol)`. Therefore one fit call = one (event_id, firm_symbol) context = at most one warning. No explicit de-duplication mechanism (e.g., `withCallingHandlers`) is needed. [VERIFIED: R/execute.R:31-34 and R/task.R:72-73]

### Pattern 7: Roxygen NAMESPACE Regeneration

After adding `R/contract.R`, the standard workflow applies:
```r
devtools::document()  # runs roxygen2, updates man/ and NAMESPACE
```
No `@export` tags will be added to the helpers (they are `@noRd`), so NAMESPACE is not changed for the helpers. The doc topic (`@name degenerate-input-contract`) generates a new `.Rd` file in `man/` but no NAMESPACE entry. [ASSUMED — standard roxygen2 behavior for doc-only NULL topics]

### Anti-Patterns to Avoid

- **Passing `degenerate_mode` as a `fit()` parameter:** Breaks the `ModelBase` interface (`fit(data_tbl)`) and requires signature changes in every model class and every callsite. Use field assignment instead.
- **Reading `getOption()` inside `fit()`:** Every model would read the raw option directly, bypassing `.resolve_degenerate_mode()`. All option reads must go through the resolver.
- **Inserting `event_id`/`firm_symbol` into the inner data_tbl:** Adds non-statistical columns to data that models may forward to `lm()`, causing formula errors.
- **Using `withCallingHandlers` or `tryCatch` around all of `fit_model()` to de-duplicate warnings:** Hides the stack and makes debugging harder; not needed given the 1:1 call structure.
- **Modifying `ModelBase$fit()` as the guard entry point:** `ModelBase$fit()` is currently empty (no-op). Adding guards there would require all subclasses to call `super$fit()`, which none of them currently do.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Safe function execution | Custom tryCatch wrapper | `purrr::safely()` | Already used throughout; handles NULL/error cleanly |
| Match enum values | Manual `if`/`else` chain | `match.arg(val, c("lenient","strict"))` | R convention; gives informative error on invalid value |
| R6 field injection | Deep clone + new initialize parameter | Field assignment after clone | lock_objects=FALSE; no interface change required |

---

## Common Pitfalls

### Pitfall 1: event_id/firm_symbol not in the inner data_tbl

**What goes wrong:** The plan assumes that `MarketModel$fit(data_tbl)` can extract `event_id` and `firm_symbol` from `data_tbl` directly (e.g., `data_tbl$event_id[1]`).

**Why it happens:** After `tidyr::nest()` groups by `(event_id, group, firm_symbol)`, those columns become the *outer* grouping keys. The inner `data` tibble contains only the price/return columns (date, firm_adjusted, firm_returns, index_adjusted, index_returns, estimation_window, event_window, relative_index, event_date). [VERIFIED: R/task.R:72-73 — `dplyr::group_by(event_id, group, firm_symbol) %>% tidyr::nest()` drops keys from inner data]

**How to avoid:** Thread `event_id` and `firm_symbol` as fields on the cloned model in `.initialize_and_fit_model()`, as described in Pattern 4.

**Warning signs:** If a test of `.handle_degenerate()` with `event_id` produces `NULL` or `NA` in the error message despite a real event_id existing in `task$data_tbl`.

### Pitfall 2: MarketModel has NO existing insufficient-obs guard

**What goes wrong:** The plan assumes MarketModel already has an `n_valid < 2` guard like `MarketAdjustedModel` and `ComparisonPeriodMeanAdjustedModel`.

**Why it happens:** MarketModel delegates entirely to `purrr::safely(.estimate_mm_model)` — it relies on `lm()` to fail naturally on degenerate data (lm with 0 or 1 obs raises an error, which safely captures). [VERIFIED: R/models.R:160-178]

**How to avoid:** The refactor must ADD an explicit `n_valid < 2` check before the `purrr::safely()` call, per the contract. The `tryCatch`/`safely` path then handles lm() failures (zero-variance, rank deficiency) that slip through.

**Warning signs:** With exactly 1 valid observation, `lm()` raises `"0 non-NA cases"` or similar — the safely path catches it. But the error message is lm-internal, not the contract format. Add the explicit guard first.

### Pitfall 3: ss_market guard in ModelBase is NOT a degeneracy signal

**What goes wrong:** The plan treats `ModelBase$calculate_forecast_error_correction()`'s `ss_market < .Machine$double.eps` check [VERIFIED: R/models.R:76] as the zero-variance guard that needs refactoring.

**Why it happens:** It looks like a zero-variance check. But its semantics are different: it is a *fallback path* when market returns are constant (so OLS forecast-error correction is undefined), not a signal that the model should not have been fit at all. It does not set `is_fitted = FALSE`.

**How to avoid:** Leave `calculate_forecast_error_correction()` untouched. The zero-variance degenerate guard belongs in `MarketModel$fit()` *before* lm() is called — if `sd(estimation_tbl$index_returns) < .Machine$double.eps`, the model data is degenerate and `.handle_degenerate()` should be called.

**Warning signs:** If the refactored code removes or wraps `calculate_forecast_error_correction()`'s fallback, forecast-error-corrected sigmas will be wrong on valid data with constant index returns (unusual but valid).

### Pitfall 4: ParameterSet lock_objects=FALSE does not exempt validation

**What goes wrong:** Adding `degenerate_handling` as a field but forgetting to validate its value on initialization. A typo (`"Lenient"` vs `"lenient"`) silently defaults to `"lenient"` at resolution time.

**How to avoid:** In `ParameterSet$initialize()`, call `match.arg(degenerate_handling, c("lenient", "strict", NULL))` or validate explicitly before assigning. `NULL` must be a valid value (means "use option/default"). [VERIFIED: R/parameter_set.R:8-86]

### Pitfall 5: CONTRACT-05 test must snapshot BEFORE refactor

**What goes wrong:** The "identical output" regression test is written after the refactor and cannot compare against a pre-refactor baseline.

**How to avoid:** Capture the numerical outputs of a `run_event_study()` call with the default `ParameterSet` (lenient mode, valid data) using `create_mock_model_data()` [VERIFIED: R/tests/testthat/helper-mock-data.R:138-152] as a snapshot, then run the same data after the refactor and assert equality with `expect_equal()`. Alternatively, write the test using the existing `test_models.R` pattern: fit MarketModel on `create_mock_model_data()`, capture `mm$statistics$alpha`, `mm$statistics$beta`, `mm$statistics$sigma`, then assert same values after refactor.

---

## Code Examples

### Existing MarketModel$fit() — exact structure to refactor

```r
# R/models.R:160-178 [VERIFIED]
fit = function(data_tbl) {
  data_tbl %>%
    filter(estimation_window == 1) -> estimation_tbl

  # safe execution
  safe_mm = purrr::safely(.f=.estimate_mm_model)
  res = safe_mm(self$formula, estimation_tbl)
  if (is.null(res$error)) {
    private$.fitted_model = res$result
    private$.is_fitted = TRUE

    # Calculate statistics
    private$calculate_statistics(data_tbl)
  } else {
    private$.is_fitted = FALSE
    private$.error = res$error
    warning("Model fitting failed: ", conditionMessage(res$error))
  }
}
```

Key facts:
- No `n_valid < 2` guard exists (unlike `MarketAdjustedModel` lines 292-299, `ComparisonPeriodMeanAdjustedModel` lines 366-372, `BHARModel` lines 924-930, `VolumeModel` lines 1023-1029) [VERIFIED: R/models.R]
- The `safely` path sets `private$.is_fitted = FALSE` and calls `warning()` inline — both to be replaced by `.handle_degenerate()`
- `private$.is_fitted` is the backing field for the `is_fitted` active binding in `ModelBase` [VERIFIED: R/models.R:46-52, 55]

### Existing ParameterSet$initialize() — exact signature to extend

```r
# R/parameter_set.R:33-55 [VERIFIED]
initialize = function(return_calculation = SimpleReturn$new(),
                      return_model = MarketModel$new(),
                      single_event_statistics = SingleEventStatisticsSet$new(),
                      multi_event_statistics = MultiEventStatisticsSet$new()) {
  # ...validates and assigns each field...
}
```

The `lock_objects = FALSE` [VERIFIED: R/parameter_set.R:9] means `self$degenerate_handling <- value` in `initialize()` works without a pre-declared field.

### Existing .initialize_and_fit_model() — exact function to modify

```r
# R/execute.R:46-51 [VERIFIED]
.initialize_and_fit_model <- function(data_tbl, return_model) {
  # Each event needs its own model, therefore a deep clone is necessary
  cloned_return_model = return_model$clone(deep=TRUE)
  cloned_return_model$fit(data_tbl)
  cloned_return_model
}
```

The purrr::map call that invokes it [VERIFIED: R/execute.R:31-34]:
```r
task$data_tbl = task$data_tbl %>%
  mutate(model = purrr::map(.x=data,
                            .f=.initialize_and_fit_model,
                            return_model=parameter_set$return_model))
```

Note: `purrr::map(.x=data, ...)` iterates over the inner `data` column. To also pass `event_id` and `firm_symbol`, this must change to `purrr::pmap()` or an anonymous function that captures the outer column values.

### Existing test infrastructure for models

```r
# tests/testthat/test_models.R:1-6 [VERIFIED]
test_that("MarketModel fits correctly", {
  data = create_mock_model_data()
  mm = MarketModel$new()
  mm$fit(data)
  expect_true(mm$is_fitted)
  # ... asserts on mm$statistics ...
})
```

```r
# tests/testthat/test_models.R:41-50 [VERIFIED]
test_that("MarketModel returns NA when not fitted", {
  mm = MarketModel$new()
  data = create_mock_model_data()
  expect_warning(
    result <- mm$abnormal_returns(data),
    "not fitted"
  )
  expect_true(all(is.na(result$abnormal_returns)))
})
```

### Degenerate data factories to add to helper-mock-data.R

```r
# tests/testthat/helper-mock-data.R — additions for Phase 1 tests
create_degenerate_model_data_insufficient <- function(n_valid = 1, n_event = 11) {
  # Produces an estimation window with only n_valid non-NA rows
  n_estimation <- 120
  data <- create_mock_model_data(n_estimation = n_estimation, n_event = n_event)
  # Set all but n_valid estimation rows to NA
  est_rows <- which(data$estimation_window == 1)
  na_rows <- est_rows[seq(n_valid + 1, length(est_rows))]
  data$firm_returns[na_rows] <- NA_real_
  data$index_returns[na_rows] <- NA_real_
  data
}

create_degenerate_model_data_zero_variance <- function(n_event = 11) {
  # Produces estimation window with constant index returns
  data <- create_mock_model_data(n_event = n_event)
  est_rows <- which(data$estimation_window == 1)
  data$index_returns[est_rows] <- 0.001  # constant
  data
}
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| `warning()` inline in `fit()` | `.handle_degenerate()` in `contract.R` | Phase 1 target |
| Scattered guards per model | Unified guard via helper | Phase 2 extends to all models |
| No contract documentation | `?degenerate-input-contract` roxygen topic | Phase 1 target |
| Inconsistent error context | Named component + event_id + firm_symbol in message | Phase 1 target |

---

## Critical Threading Finding (Key Open Issue)

### The Mode-Threading Call Chain — Full Trace

```
run_event_study(task, parameter_set)              R/execute.R:13
  └─ fit_model(task, parameter_set)               R/execute.R:29
       └─ purrr::map(.x=data,                     R/execute.R:31-34
                     .f=.initialize_and_fit_model,
                     return_model=parameter_set$return_model)
            └─ .initialize_and_fit_model(          R/execute.R:46
                   data_tbl,                       # inner per-event tibble (NO event_id/firm_symbol)
                   return_model)                   # cloned model (NO degenerate_mode)
                 └─ cloned$fit(data_tbl)           R/models.R:160
```

**Gap:** `parameter_set$degenerate_handling` and the outer-row keys (`event_id`, `firm_symbol`) are NOT passed into `.initialize_and_fit_model()` or into `model$fit()`. The ParameterSet is available in `fit_model()` but only `parameter_set$return_model` is extracted and passed down.

**Required change:** `.initialize_and_fit_model()` must accept and set `degenerate_mode`, `event_id`, `firm_symbol` as fields on the cloned model, and `fit_model()` must pass them. This is a minimal, contained change — no model interface (`fit(data_tbl)` signature) changes.

**Alternative (rejected):** Add `degenerate_handling` as a constructor argument to every model class. This would require changing all 13 model `initialize()` functions and the deep clone mechanism — far too invasive for a convention change.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Doc-only `@name` topic with a `NULL` assignment generates a `?degenerate-input-contract` help page without NAMESPACE entry | Architecture Patterns — Pattern 1 | If wrong: no help page generated, or R CMD check NOTE; fix by using `@rdname` or moving to named function |
| A2 | `private$.is_fitted <- FALSE` can be set from inside `.handle_degenerate()` via `fitted_flag_env = private` (environment reference) | Architecture Patterns — Pattern 3 | If wrong: lenient mode does not set is_fitted correctly; fix by returning a flag instead of mutating |
| A3 | `purrr::pmap()` with named list accessing outer-row columns (`event_id`, `firm_symbol`) from `task$data_tbl` works correctly inside `dplyr::mutate()` | Architecture Patterns — Pattern 4 | If wrong: key threading fails silently; fallback is `mapply()` or explicit `for` loop over rows |

---

## Open Questions

1. **R6 private environment passing to helper**
   - What we know: `private` in an R6 method is an environment; passing it as `fitted_flag_env = private` to an external function and then doing `fitted_flag_env$.is_fitted <- FALSE` should mutate the original R6 private environment.
   - What's unclear: Whether R6's private environment supports assignment from an external reference (not tested in this package).
   - Recommendation: Test this in a one-line prototype before committing to the pattern. Alternative: `.handle_degenerate()` returns a logical; the caller does `if (.handle_degenerate(...)) { private$.is_fitted <- FALSE; return(invisible(self)) }`.

2. **`purrr::pmap` vs anonymous function in `dplyr::mutate`**
   - What we know: The current code uses `purrr::map(.x=data, ...)` which only iterates one column.
   - What's unclear: Whether `purrr::pmap(list(data=data, event_id=event_id, firm_symbol=firm_symbol), fn)` inside `dplyr::mutate()` evaluates the column names correctly in dplyr's NSE context.
   - Recommendation: Use an explicit anonymous function `dplyr::mutate(model = purrr::map(seq_len(nrow(.)), function(i) { .initialize_and_fit_model(data[[i]], ..., event_id=event_id[i], firm_symbol=firm_symbol[i]) }))` as the safe fallback, or test `purrr::pmap` with a trivial example first.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely code/config changes within the existing R package. No external tools, services, CLIs, or new runtimes are required.

---

## Security Domain

`security_enforcement` is enabled. Applying ASVS Level 1 to this phase:

| ASVS Category | Applies | Notes |
|---------------|---------|-------|
| V2 Authentication | No | Package library, no auth |
| V3 Session Management | No | No sessions |
| V4 Access Control | No | No access control |
| V5 Input Validation | Yes | Validate `degenerate_handling` values via `match.arg()` |
| V6 Cryptography | No | No crypto |

**V5 Input Validation control:** `match.arg(degenerate_handling, c("lenient", "strict"))` in `ParameterSet$initialize()` and `.resolve_degenerate_mode()`. This prevents injection of arbitrary strings into warning/error messages that contain the mode value. [ASSUMED — no specific threat here, but the control is cheap and correct]

**Known Threat Patterns:**

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Arbitrary string in mode field passed through to `stop()`/`warning()` messages | Tampering / Information Disclosure | `match.arg()` validation; only `"lenient"` or `"strict"` allowed |

---

## Sources

### Primary (HIGH confidence — directly read this session)
- `R/models.R:1-265` — MarketModel and ModelBase complete source [VERIFIED]
- `R/execute.R:1-164` — Full pipeline orchestration and threading [VERIFIED]
- `R/parameter_set.R:1-87` — ParameterSet structure [VERIFIED]
- `R/EventStudy-package.R:1-139` — Package doc topic pattern [VERIFIED]
- `R/task.R:19-82` — `.keys` and nest() structure [VERIFIED]
- `tests/testthat/helper-mock-data.R:1-153` — Test factory functions [VERIFIED]
- `tests/testthat/test_models.R:1-80` — Existing model test patterns [VERIFIED]
- `tests/testthat/test_parameter_set.R:1-45` — ParameterSet test patterns [VERIFIED]
- `.planning/phases/01-contract-foundation/01-CONTEXT.md` — Locked decisions [VERIFIED]
- `.planning/config.json` — nyquist_validation=false confirmed [VERIFIED]

### Secondary
- `R/models.R:269-1162` — Other model classes confirming n_valid pattern [VERIFIED]
- `R/prepare_event_study.R:1-55` — Column structure confirmation [VERIFIED]
- `.planning/codebase/CONCERNS.md` — Known bugs and fragile areas [VERIFIED]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages, all existing tools read directly
- Architecture / call chain: HIGH — traced from source files; threading gap confirmed by reading execute.R and task.R
- Mode-threading solution: MEDIUM — the field-injection approach is sound but the R6 private-environment mutation (A2) and purrr::pmap in mutate (A3) have small verification uncertainties
- Pitfalls: HIGH — derived directly from reading the actual code

**Research date:** 2026-09-02
**Valid until:** 2026-10-02 (stable R package, no fast-moving dependencies)
