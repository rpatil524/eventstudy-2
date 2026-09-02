---
phase: 02-model-and-stats-sweep
reviewed: 2026-09-02T00:00:00Z
depth: deep
files_reviewed: 4
files_reviewed_list:
  - R/contract.R
  - R/models.R
  - R/models_time_varying.R
  - R/single_event_test_statistics.R
  - R/multi_event_test_statistics.R
findings:
  critical: 2
  warning: 5
  info: 0
  total: 7
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-09-02T00:00:00Z
**Depth:** deep
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 2 migrates 10 models and 3 test statistics onto the `.handle_degenerate()` contract
established by the Phase 1 MarketModel exemplar. The structural pattern (guard before
`is_fitted <- TRUE`, `.degenerate_handled` flag, three-branch `abnormal_returns()`) is
correctly applied everywhere. The critical VolatilityModel regression (guard now lives in
`fit()` before `is_fitted <- TRUE`) is confirmed fixed.

Two blockers remain: (1) `MarketAdjustedModel` and `BHARModel` fire a "zero-variance"
degenerate guard on a fully valid input — a stock that perfectly co-moves with the index —
causing the core-value violation in the opposite direction (false degenerate, silent drop
of valid events). (2) `BHARModel` also has an inconsistency between the MODELS-04 FEC fix
applied to its df calculation and the FEC correction itself, which still uses
`nrow(estimation_tbl)`.

---

## Critical Issues

### CR-01: MarketAdjustedModel — false degenerate on stock perfectly tracking the index

**File:** `R/models.R:379-392`

**Issue:** The zero-variance guard checks `sd(firm_returns - index_returns, na.rm=TRUE) < eps`.
`MarketAdjustedModel` is a purely arithmetic model — it has no OLS fitting step and no
requirement that the residual series have non-zero variance. When a stock perfectly tracks
the index, this difference is identically zero, `sd = 0`, and the guard fires — marking the
model as degenerate, setting `.is_fitted <- FALSE`, and returning NA abnormal returns with a
contract warning. The result is zero everywhere (correct value) being silently replaced by NA
(wrong value). This directly violates the core-value guarantee ("never silently wrong").

The guard is also economically wrong: MarketAdjusted does not need variance in the residuals
to compute abnormal returns — it only needs the two series to have enough observations (the
preceding `n_valid < 2` guard already handles that correctly).

**Fix:** Remove the zero-variance guard from `MarketAdjustedModel.fit()`. If sigma=0 is a
concern for downstream test statistics (sigma=0 → NA t-stat), the test-statistic layer already
handles it via the `sigma_degenerate` guard added in Phase 2.

```r
# REMOVE the block at lines 379–392 in MarketAdjustedModel$fit():
#
# # --- Contract guard: zero or near-zero variance in residuals ---
# if (stats::sd(estimation_tbl$firm_returns - estimation_tbl$index_returns,
#                na.rm = TRUE) < .Machine$double.eps) {
#   .handle_degenerate(...)
#   ...
# }
#
# The n_valid < 2 guard above is sufficient.
```

---

### CR-02: BHARModel — same false degenerate as CR-01, PLUS FEC uses wrong row count

**File:** `R/models.R:1200-1214` (false degenerate) and `R/models.R:1275` (wrong FEC)

**Issue (part A — false degenerate):** `BHARModel` has the identical zero-variance guard
(`sd(firm_returns - index_returns) < eps`). BHAR computes buy-and-hold returns regardless of
whether the estimation-window difference series has variance. A stock that tracks the index
perfectly in the estimation window will have BHAR = 0 in the event window — which is the
correct economic answer. The guard turns this into NA, producing a silently wrong result.

**Issue (part B — FEC inconsistency):** On line 1267–1270, a comment explicitly says:

```
# nrow(estimation_tbl) would include NA rows, inflating df incorrectly.
```

...and `.finite_residual_df()` is used for `degree_of_freedom`. However, on line 1275 the
FEC correction still uses `nrow(estimation_tbl)`:

```r
correction <- sigma * sqrt(1 + 1 / nrow(estimation_tbl))  # BUG: still raw nrow
```

GARCH (line 1149) and DCC-GARCH (line 897 in models_time_varying.R) were correctly fixed to
use `n_valid_fec`, but `BHARModel` was missed. With NA rows in the estimation window, the FEC
denominator is overstated, the correction factor `sqrt(1 + 1/nrow)` is understated, and the
forecast-error-corrected sigma is too small — yielding t-statistics that are too large (false
positives).

**Fix (part A):** Remove the zero-variance guard from `BHARModel$fit()` at lines 1200–1214.

**Fix (part B):** Replace line 1275:

```r
# Replace:
correction <- sigma * sqrt(1 + 1 / nrow(estimation_tbl))

# With (consistent with GARCH/DCC-GARCH MODELS-04 fix):
n_valid_fec <- sum(!is.na(estimation_tbl$firm_returns) &
                     !is.na(estimation_tbl$index_returns))
correction <- sigma * sqrt(1 + 1 / max(n_valid_fec, 1L))
```

---

## Warnings

### WR-01: PatellZTest — Q_total inflated by degenerate events, biasing valid-event z-scores

**File:** `R/multi_event_test_statistics.R:140`

**Issue:** `Q_total = sqrt(sum(sd_asar$Q_i))` aggregates over ALL events, including those
with degenerate models (NA fec_sigma). Degenerate events contribute `Q_i = 1` (the fallback
at line 112). This inflates `Q_total`, so the `aar_z = sum_sar / Q_total` for valid events is
deflated (test is too conservative). The `n_valid_events <= 1` guard at line 154 prevents
outputting an invalid z-score when ALL events are degenerate, but it does not remove degenerate
events' Q_i contribution from the denominator in the mixed case.

The consequence is not a NaN/Inf (so it passes automated tests) but a wrong z-score on valid
multi-event studies that happen to include one or more degenerate events.

**Fix:** Filter out events whose fec_sigma is entirely NA before computing Q_total:

```r
sd_asar_valid <- sd_asar %>%
  dplyr::semi_join(
    fec_sigma %>%
      dplyr::group_by(event_id) %>%
      dplyr::filter(any(is.finite(fec_sigma))) %>%
      dplyr::distinct(event_id),
    by = "event_id"
  )
Q_total = sqrt(sum(sd_asar_valid$Q_i))
```

---

### WR-02: SignTest — cumulative sign statistic (csign_z) not guarded for n_valid == 1

**File:** `R/multi_event_test_statistics.R:233`

**Issue:** The point-in-time `sign_z` correctly guards `n_valid_events >= 2` (changed in this
phase). However, the cumulative sign statistic `csign_z` computed in the `cum_sign` pipeline
at line 233 has no such guard:

```r
csign_z = (n_pos_car - 0.5 * n_valid) / (0.5 * sqrt(n_valid))
```

When `n_valid == 1`, this yields `(1 - 0.5) / (0.5 * 1) = 1.0` — a finite, plausible-looking
number that is statistically meaningless. This is the exact pattern the phase is supposed to
eliminate.

**Fix:**

```r
csign_z = ifelse(n_valid >= 2,
                 (n_pos_car - 0.5 * n_valid) / (0.5 * sqrt(n_valid)),
                 NA_real_)
```

---

### WR-03: MarketAdjustedModel and ComparisonPeriodMean — FEC uses nrow not finite count

**File:** `R/models.R:438` (MarketAdjusted), `R/models.R:551` (ComparisonPeriodMean)

**Issue:** Both constant-mean FEC corrections use `nrow(estimation_tbl)` as the denominator:

```r
correction = sigma * sqrt(1 + 1 / nrow(estimation_tbl))
```

With NA rows in the estimation window this overstates the denominator, understates the
correction factor, and produces FEC sigma values that are too small. The same bug was
explicitly noted in the MODELS-04 fix applied to GARCH (line 1149) and DCC-GARCH
(line 897), but these two constant-mean models were not updated. The BHARModel FEC (line 1275)
has the same issue (also covered in CR-02).

**Fix** (same pattern for both):

```r
# Replace nrow(estimation_tbl) with:
n_valid_est <- sum(!is.na(estimation_tbl$firm_returns))  # or finite-pair count as appropriate
correction = sigma * sqrt(1 + 1 / max(n_valid_est, 1L))
```

---

### WR-04: RollingWindowModel — degree_of_freedom uses raw window size not finite pair count

**File:** `R/models_time_varying.R:177`

**Issue:** `private$.statistics$degree_of_freedom <- ws - 2` uses `ws = min(window_size, n_est)`
where `n_est = nrow(estimation_tbl)` (line 175) — total rows including NA pairs. Guard 1 in
`fit()` correctly switched to `n_valid` (finite pair count) for the minimum-observations check,
but `calculate_statistics()` reverts to `nrow` when computing df. With NA-heavy estimation
windows the df is overstated and t-statistics will be too permissive.

**Fix:**

```r
# In calculate_statistics(), replace:
n_est <- nrow(estimation_tbl)
ws <- min(self$window_size, n_est)
private$.statistics$degree_of_freedom <- ws - 2

# With:
n_valid_est <- sum(!is.na(estimation_tbl$firm_returns) &
                     !is.na(estimation_tbl$index_returns))
ws <- min(self$window_size, n_valid_est)
private$.statistics$degree_of_freedom <- max(ws - 2L, 1L)
```

---

### WR-05: ComparisonPeriodMeanAdjustedModel — variance guard may trip on a single-valued estimation window

**File:** `R/models.R:490-502`

**Issue:** `ComparisonPeriodMeanAdjustedModel` guards on `sd(est_returns, na.rm=TRUE) < eps`.
Unlike MarketAdjusted/BHAR (CR-01/CR-02), this model does use the mean of estimation returns
as the expected return, so test statistics do depend on sigma. However, `stats::sd()` of a
single-element vector returns `NA`, not 0. Since `NA < eps` is `NA` (falsy), the guard will
NOT fire on a single-element window — it falls through to the subsequent computation where
`sd(residuals, na.rm=TRUE)` returns `NA`, which becomes sigma. The ARTTest sigma guard then
produces NA t-statistics (correct behavior). But if the estimation window has exactly two
identical values (e.g., both returns = 0.01), `sd = 0` and the guard fires correctly.

The real problem: the guard also fires when all returns are identical but non-zero (e.g., a
constant-returns fund). This is a valid input that produces a predictable mean but zero
residual variance. The test-statistic layer already handles `sigma == 0` via the ART/CART
guards added in this phase. Firing the degenerate guard here produces a warning and NA abnormal
returns, rather than producing the correct abnormal returns with NA t-statistics.

**Fix:** Remove the zero-variance guard from `ComparisonPeriodMeanAdjustedModel$fit()` and let
the sigma=0 case propagate to the test-statistic layer (which already guards it). The
`n_valid < 2` guard is sufficient for the model-level degeneracy check.

---

## Contract Compliance Summary

| Model | Guard before is_fitted | .degenerate_handled branch | Error message keys |
|---|---|---|---|
| MarketAdjustedModel | BEFORE (correct) | Present | component + event_id + firm |
| ComparisonPeriodMean | BEFORE (correct) | Present | component + event_id + firm |
| CustomModel | Inherited from MarketModel | Present | component + event_id + firm |
| LinearFactorModel | BEFORE (correct) | Present | component + event_id + firm |
| FamaFrench3/5FactorModel | Inherited from LinearFactorModel | Present | component + event_id + firm |
| Carhart4FactorModel | Inherited from LinearFactorModel | Present | component + event_id + firm |
| BHARModel | BEFORE (correct) | Present | component + event_id + firm |
| VolumeModel | BEFORE (correct) | Present | component + event_id + firm |
| VolatilityModel | BEFORE (correct) — Phase 2 fix confirmed | Present | component + event_id + firm |
| RollingWindowModel | BEFORE (all 3 guards) | Present | component + event_id + firm |
| GARCHModel | BEFORE rugarch call | Present | component + event_id + firm |
| DCCGARCHModel | BEFORE rmgarch call | Present | component + event_id + firm |
| ARTTest | sigma guard | n/a | n/a |
| CARTTest | sigma guard | n/a | n/a |
| BHARTTest | bhar_se guard | n/a | n/a |
| PatellZTest | n_valid_events <= 1 | n/a | **Q_total not degenerate-aware (WR-01)** |
| SignTest | n_valid_events >= 2 | n/a | **csign_z not guarded (WR-02)** |

VolatilityModel bug from Phase 2 scope: **confirmed fixed** — guard is now in `fit()` before
`private$.is_fitted <- TRUE`, removing the inconsistency window.

---

_Reviewed: 2026-09-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
