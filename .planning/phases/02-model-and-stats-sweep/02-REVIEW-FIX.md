---
phase: "02"
fixed_at: "2026-09-02T12:23:28Z"
review_path: ".planning/phases/02-model-and-stats-sweep/02-REVIEW.md"
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-09-02T12:23:28Z
**Source review:** `.planning/phases/02-model-and-stats-sweep/02-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 7
- Skipped: 0

**Test suite result:** `[ FAIL 0 | WARN 0 | SKIP 17 | PASS 1200 ]` (net +10 new regression tests; verification ran in isolated git worktree, no node_modules gates)

---

## Fixed Issues

### CR-01: MarketAdjustedModel — false-degenerate zero-variance guard

**Files modified:** `R/models.R`, `tests/testthat/test_models.R`, `tests/testthat/test_edge_cases.R`
**Commit:** `916dfee`
**Applied fix:** Removed the `sd(firm_returns - index_returns) < .Machine$double.eps` guard from
`MarketAdjustedModel$fit()`. The model is purely arithmetic — it subtracts index returns from firm
returns. Zero variance in the difference is a valid input (stock perfectly tracks index yields AR=0).
Added explanatory comment. Updated `test_models.R` to remove "zerovar" from the degenerate loop
and added CR-01 regression test. Updated `test_edge_cases.R` to assert the corrected contract
(`is_fitted=TRUE`, `sigma=0`, all ARs finite and equal to zero).

---

### CR-02: BHARModel — false-degenerate zero-variance guard + FEC NA-inflation

**Files modified:** `R/models.R`, `tests/testthat/test_models.R`
**Commit:** `916dfee`
**Applied fix (CR-02A):** Removed the `sd(firm_returns - index_returns) < .Machine$double.eps` guard
from `BHARModel$fit()`. BHAR is an arithmetic buy-and-hold model; zero diff-variance yields AR=0,
not a failure. Added explanatory comment.

**Applied fix (CR-02B):** Changed FEC denominator from `nrow(estimation_tbl)` to
`max(sum(!is.na(estimation_tbl$firm_returns) & !is.na(estimation_tbl$index_returns)), 1L)` so NA
rows do not inflate N and understate the correction factor.

Updated `test_models.R`: removed "zerovar" from BHARModel degenerate loops; added CR-02A regression
test (zero diff-variance yields `is_fitted=TRUE`) and CR-02B regression test (FEC uses finite pair count).

---

### WR-01: PatellZTest — degenerate events inflate Q_total denominator

**Files modified:** `R/multi_event_test_statistics.R`, `tests/testthat/test_multi_event_statistics.R`
**Commit:** `bb180a8`
**Applied fix:** Before computing `Q_total = sqrt(sum(Q_i))`, filter `sd_asar` to only events where
at least one row of `fec_sigma` is finite. Degenerate events contributed a fallback `Q_i=1` which
inflated the denominator, understating the Patell Z statistic. Added `valid_event_ids` filter using
`group_by(event_id) %>% summarise(.valid = any(is.finite(fec_sigma))) %>% filter(.valid)`.

Added WR-01 regression test: 3-event pool where event 3 is degenerate (constant returns → non-finite
FEC); verifies that `Q_total` is based on 2 valid events only, not 3.

---

### WR-02: SignTest — csign_z NaN when n_valid < 2

**Files modified:** `R/multi_event_test_statistics.R`, `tests/testthat/test_multi_event_statistics.R`
**Commit:** `bb180a8`
**Applied fix:** Wrapped `csign_z` computation in `ifelse(n_valid >= 2, (n_pos_car - 0.5 * n_valid) / (0.5 * sqrt(n_valid)), NA_real_)`. With only 1 valid event, the formula is statistically undefined; guard produces `NA_real_` instead of `NaN` or `Inf`.

Added WR-02 regression tests: single-event case (`n_valid=1` yields `csign_z=NA`) and two-event case
(`n_valid=2` yields finite `csign_z`).

---

### WR-03: FEC uses nrow() instead of finite-pair count (MarketAdjustedModel + ComparisonPeriodMeanAdjustedModel)

**Files modified:** `R/models.R`, `tests/testthat/test_models.R`
**Commit:** `916dfee`
**Applied fix (MarketAdjustedModel):** Changed FEC N from `nrow(estimation_tbl)` to
`max(sum(!is.na(estimation_tbl$firm_returns) & !is.na(estimation_tbl$index_returns)), 1L)`. The
correction `sigma * sqrt(1 + 1/N)` uses paired finite-row count so NA rows don't inflate N.

**Applied fix (ComparisonPeriodMeanAdjustedModel):** Same fix — changed from `nrow(estimation_tbl)`
to `max(sum(!is.na(estimation_tbl$firm_returns)), 1L)` (unpaired since CPM uses only firm returns).

Added two WR-03 regression tests in `test_models.R`: one for each model with 50 estimation rows
where 10 (MAM) or 15 (CPM) are NA, verifying the FEC reflects the finite count not nrow.

---

### WR-04: RollingWindowModel — degree_of_freedom uses nrow instead of finite pair count

**Files modified:** `R/models_time_varying.R`, `tests/testthat/test_models_time_varying.R`
**Commit:** `e86fba0`
**Applied fix:** Changed `calculate_statistics()` in `RollingWindowModel` to count finite `(firm, index)` pairs instead of using `nrow(estimation_tbl)`, and use `max(ws - 2L, 1L)` to floor the df at 1. This prevents negative/zero df from propagating to t-distribution quantile functions downstream.

Added WR-04 regression test: `window_size=200`, 200 estimation rows with 80 NAs; verifies df=118
(from 120 finite pairs) not df=198 (from nrow=200).

---

### WR-05: ComparisonPeriodMeanAdjustedModel — false-degenerate zero-variance guard

**Files modified:** `R/models.R`, `tests/testthat/test_models.R`, `tests/testthat/test_edge_cases.R`
**Commit:** `916dfee`
**Applied fix:** Removed the `sd(estimation_tbl$firm_returns, na.rm=TRUE) < .Machine$double.eps`
guard from `ComparisonPeriodMeanAdjustedModel$fit()`. The model subtracts the estimation-period mean
from event returns — zero variance in estimation returns is a valid input; the model fits correctly
with `sigma=0` and produces `AR = event_return - constant_mean`.

Updated `test_models.R`: removed "zerovar" from CPM degenerate loops; added WR-05 regression test.
Updated `test_edge_cases.R`: the "constant estimation returns" test now asserts `is_fitted=TRUE` and
no NaN/Inf in ARs (reflecting the corrected contract).

---

## Skipped Issues

None — all 7 findings were fixed.

---

_Fixed: 2026-09-02T12:23:28Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
