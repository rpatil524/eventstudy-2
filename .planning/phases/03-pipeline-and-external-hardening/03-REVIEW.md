---
phase: 03-pipeline-and-external-hardening
reviewed: 2026-09-02T00:00:00Z
depth: deep
files_reviewed: 7
files_reviewed_list:
  - R/prepare_event_study.R
  - R/export.R
  - R/cross_sectional.R
  - R/panel_event_study.R
  - R/models.R
  - R/models_time_varying.R
  - R/synthetic_control.R
findings:
  critical: 2
  warning: 2
  info: 0
  total: 4
status: findings
---

# Phase 3: Code Review Report

**Reviewed:** 2026-09-02
**Depth:** deep
**Files Reviewed:** 7
**Status:** findings

## Summary

Phase 3 introduced defensive wrapping around external package calls, degenerate-input routing in `prepare_event_study`, rank-deficiency handling in `cross_sectional`, and GARCH/DCC-GARCH post-fit error isolation. Most changes are structurally sound. Two blockers were found: one is a contract-breaking semantic regression in `export.R` (the coalesce-guarded CAR cumsum silently substitutes NA returns with zero, producing plausible-looking wrong CAR values), and one is a silent-wrong-result gap in `synthetic_control.R` (the empty-donor-pool guard fires in `.solve_sc_optim` but returns a zero-length weight vector that R's matrix algebra turns into a zero synthetic trajectory, making the reported ATT equal to the treated unit's raw outcome level). Two warnings were found: the GARCH/DCC-GARCH `calculate_statistics` tryCatch resets `is_fitted=FALSE` without setting `.degenerate_handled=TRUE`, causing a second spurious warning on the subsequent `abnormal_returns()` call; and `estimate_panel_event_study()` returns `task` unconditionally even when the inner estimator returned `NULL`, leaving `task$results=NULL` with no caller-visible signal.

---

## Critical Issues

### CR-01: `export.R` — `coalesce(abnormal_returns, 0)` silently substitutes NA returns with zero, producing wrong CARs

**File:** `R/export.R:87`

**Issue:** The Phase 3 fix replaces `cumsum(abnormal_returns)` with `cumsum(dplyr::coalesce(abnormal_returns, 0))`. R's `cumsum()` never crashes on NA inputs — it propagates NA forward, which is the correct statistical behavior. The coalesce substitution treats every NA abnormal-return day as a zero-return day, producing two classes of silently wrong results:

1. **All-NA events** (model not fitted, `is_fitted=FALSE`): all `abnormal_returns` are `NA_real_`. After coalesce, `cumsum(c(0,0,...,0))` produces `c(0,0,...,0)`. The export table reports CAR = 0 for every window day — a plausible-looking "no effect" result where the actual answer is unknown.

2. **Partial-NA events** (sparse estimation window, one trading day missing mid-window): NA days are treated as zero-return days, so later cumulative values are understated. The final CAR is wrong but indistinguishable from a valid result.

This is a direct violation of the project's core value ("never return a plausible-looking wrong number"). The old code's behavior (`cumsum` propagating NA) was already correct. The fix had no bug to fix.

Contrast: `.tidy_car()` (also in `export.R`, line 307) applies the same `coalesce` pattern — that was pre-existing and is out of scope for this review, but confirms the pattern was cargo-culted rather than introduced to address a real crash.

**Fix:**

```r
# R/export.R line 87 — remove coalesce; cumsum already handles NA correctly
dplyr::mutate(car = cumsum(abnormal_returns))
```

If a non-NA running total is genuinely desired (e.g., for a specific "skip-NA-days" interpretation), document the semantic choice explicitly and add a parameter to select behavior. Do not default to silently zeroing NA returns.

---

### CR-02: `synthetic_control.R` — empty donor pool produces `y_synth = 0` and a numerically wrong ATT

**File:** `R/synthetic_control.R:118-129`

**Issue:** When the donor pool is empty (`n_donors == 0`), the code reaches `.solve_sc_quadprog()`, which builds a 0×0 `Dmat` — `quadprog::solve.QP` throws and the tryCatch returns `NULL`. The fallback then calls `.solve_sc_optim(y_pre, X_pre)` with `X_pre` having zero columns. The new guard in `.solve_sc_optim` (line 220-224) correctly detects `n==0` and returns `rep(NA_real_, 0)`.

Back in `estimate_synthetic_control`, `weights` is now a zero-length NA vector. `names(weights) <- donor_units` succeeds silently (both have length 0). Then `X_all` is built as an `nrow × 0` matrix. The computation `as.numeric(X_all %*% weights)` exploits R's matrix algebra: a matrix with zero columns multiplied by a zero-length vector yields a zero vector of length `nrow`. The result is:

```r
y_synth <- as.numeric(X_all %*% weights)  # → c(0, 0, ..., 0)
gap <- y_all - y_synth                     # → y_all - 0 = y_all
att <- mean(gap[post_idx])                 # → mean(y_treated[post]) ← WRONG
```

The estimated ATT equals the raw treated-unit outcome level for the post-treatment period — a maximally wrong plausible-looking result. The function returns successfully with a populated `task$results` containing a numeric ATT that appears valid.

The guard in `.solve_sc_optim` is necessary but not sufficient: `estimate_synthetic_control` must also check `n_donors == 0` before entering the solver path.

**Fix:**

```r
# R/synthetic_control.R — add immediately after line 98 (n_donors computation)
if (n_donors == 0) {
  stop("Synthetic control: donor pool is empty. ",
       "donor_data must contain at least one unit.", call. = FALSE)
}
```

Alternatively, to degrade gracefully rather than stop, return `NULL` + `warning()` before reaching the solver block. Either approach is correct; a hard `stop()` is preferable here because an empty donor pool is a structural error that no amount of fallback arithmetic can recover from.

---

## Warnings

### WR-01: `models.R` / `models_time_varying.R` — `calculate_statistics` tryCatch does not set `.degenerate_handled`, emitting two warnings

**File:** `R/models.R:1074-1082`, `R/models_time_varying.R:347-355`

**Issue:** When `calculate_statistics` fails post-fit, the tryCatch handler resets `private$.is_fitted <- FALSE` and emits one warning. When `abnormal_returns()` is subsequently called, the logic is:

```r
if (private$.is_fitted)       # FALSE → skip
else if (private$.degenerate_handled)  # FALSE (never set) → skip
else {
  warning("GARCHModel is not fitted. Returning NA abnormal returns.")  # second warning
  data_tbl %>% dplyr::mutate(abnormal_returns = NA_real_)
}
```

The result is correct (NA abnormal returns), but two warnings are emitted per event — a violation of the contract documented in `contract.R`: "emits exactly one warning() per (event_id, firm_symbol) per fit call". Tests asserting `expect_warning(..., n = 1)` on this path would fail.

**Fix:**

```r
# R/models.R:1077-1081 — add degenerate_handled after resetting is_fitted
error = function(e) {
  private$.is_fitted <- FALSE
  private$.degenerate_handled <- TRUE   # suppress second warning in abnormal_returns()
  warning("GARCH model statistics computation failed: ",
          conditionMessage(e),
          ". Returning NA abnormal returns.", call. = FALSE)
}
```

Apply the identical fix to `R/models_time_varying.R:350-354` for `DCCGARCHModel`.

---

### WR-02: `panel_event_study.R` — `estimate_panel_event_study()` returns `task` unconditionally; NULL result from inner estimator is silent

**File:** `R/panel_event_study.R:146-160`

**Issue:** The `switch()` dispatch calls the inner estimators but discards their return values — the result of the `switch()` expression is dropped, and `task` is returned on line 160 regardless. When `callaway_santanna`, `dechaisemartin_dhaultfoeuille`, or `borusyak_jaravel_spiess` now return `invisible(NULL)` (the new Phase 3 behavior), the caller receives back a `PanelEventStudyTask` with `task$results = NULL` — identical to the pre-estimation state.

```r
switch(method, ...)  # return value silently discarded
task               # always returned, even when inner estimator returned NULL
```

The `plot_panel_event_study()` function guards against this (`if (is.null(task$results)) stop(...)`) but a caller who inspects `task` after `estimate_panel_event_study()` returns gets no signal that the estimator silently failed.

The stop→warning conversion for missing packages was correct; the gap is that `estimate_panel_event_study()` itself should emit one warning at the wrapper level when it detects `task$results` remains NULL after the switch.

**Fix:**

```r
# R/panel_event_study.R — add after the switch() block and before `task`
if (method %in% c("callaway_santanna", "dechaisemartin_dhaultfoeuille",
                   "borusyak_jaravel_spiess") && is.null(task$results)) {
  warning("estimate_panel_event_study: estimator '", method,
          "' returned no results (package missing or estimation failed). ",
          "task$results is NULL.", call. = FALSE)
}
task
```

---

_Reviewed: 2026-09-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
