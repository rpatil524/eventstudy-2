---
phase: 03-pipeline-and-external-hardening
fixed_at: 2026-09-02T00:00:00Z
review_path: .planning/phases/03-pipeline-and-external-hardening/03-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-09-02
**Source review:** `.planning/phases/03-pipeline-and-external-hardening/03-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: `export.R` — revert CAR coalesce; NA must propagate, not become 0

**Files modified:** `R/export.R`, `tests/testthat/test_export.R`
**Commit:** `5686c8c`
**Applied fix:**
Reverted both occurrences of `cumsum(dplyr::coalesce(abnormal_returns, 0))` back to `cumsum(abnormal_returns)` in `.build_export_tables` (~line 87) and `.tidy_car` (~line 307). The coalesce silently converted NA abnormal-return days to zero-return days, producing plausible-looking wrong CARs for unfitted events (CAR=0.0 instead of NA) and understated CARs for partial-NA events.

Two existing tests were asserting the wrong (coalesced) behavior and were updated to assert the correct (NA-propagating) behavior:
- "CAR cumsum coalesce — interior NA does not blank entire tail" → rewritten to assert NA propagates forward from the injection point
- "tidy CAR: interior NA does not blank entire cumulative tail" → same

New regression tests added:
- All-NA (unfitted) event produces CAR=NA in export_results (not 0.0)
- All-NA event produces estimate=NA in tidy.EventStudyTask CAR (not 0.0)
- Valid (finite) input is identical before/after revert (no behavior change on happy path)

Note: The coalesce in `R/multi_event_test_statistics.R` (STATS-03 deliberate cross-firm aggregation pattern) was explicitly NOT touched.

### CR-02: `synthetic_control.R` — empty donor pool returns NULL+warning, not fabricated ATT

**Files modified:** `R/synthetic_control.R`, `tests/testthat/test_synthetic_control.R`
**Commit:** `857a5c6`
**Applied fix:**
Added an early guard in `estimate_synthetic_control()` immediately after computing `n_donors`, before any matrix construction or solver call. When `n_donors == 0`, the function emits one `warning(call.=FALSE)` and returns `invisible(NULL)`. Without this guard, `X_all %*% weights` (nrow x 0 matrix times zero-length vector) silently yields a zero vector in R, making `y_synth=0`, `gap=y_treated`, and `att=mean(y_treated[post])` — the raw treated-unit outcome level reported as the ATT, a maximally wrong plausible-looking result.

The existing `.solve_sc_optim` guard (returns `rep(NA_real_, 0)`) was necessary but insufficient because the fabricated path continued in the caller after that return.

New regression test: `SyntheticControlTask` with zero-row `donor_data` → `invisible(NULL)` + warning containing "donor pool is empty", `task$results` remains NULL, no fabricated ATT.

### WR-01: `models.R` / `models_time_varying.R` — GARCH/DCC one-warning contract

**Files modified:** `R/models.R`, `R/models_time_varying.R`, `tests/testthat/test_models_time_varying.R`
**Commit:** `46158a1`
**Applied fix:**
Added `private$.degenerate_handled <- TRUE` in the `calculate_statistics` tryCatch error handlers for both `GARCHModel` (R/models.R ~line 1078) and `DCCGARCHModel` (R/models_time_varying.R ~line 351). Without this flag, when `calculate_statistics` failed post-convergence, `abnormal_returns()` fell through to the else-branch and emitted a second "not fitted" warning — violating the one-warning-per-event contract. The branch `else if (private$.degenerate_handled)` was already in place to suppress the second warning; the handler just was not setting the flag.

New regression tests (skipped when rugarch/rmgarch absent): mock `rugarch::sigma` / `rmgarch::rcov` to force calculate_statistics failure → `fit()` emits exactly 1 warning, subsequent `abnormal_returns()` emits 0 warnings, returns all-NA.

### WR-02: `panel_event_study.R` — wrapper warns when external estimator returns NULL

**Files modified:** `R/panel_event_study.R`, `tests/testthat/test_panel.R`
**Commit:** `c204cc6`
**Applied fix:**
Added a NULL guard after the `switch()` block in `estimate_panel_event_study()`. When the method is one of the three external estimators (`callaway_santanna`, `dechaisemartin_dhaultfoeuille`, `borusyak_jaravel_spiess`) and `task$results` is still NULL after the switch, the wrapper emits one `warning(call.=FALSE)` naming the method and stating that `task$results is NULL`. The switch() discards its return value, so the inner estimator's `invisible(NULL)` return was previously invisible to the caller, who received back a task with NULL results and no signal — only crashing later in `plot_panel_event_study()`.

Also updated 6 existing `expect_warning()` tests that were emitting spurious test-level WARNs (the new wrapper warning fired as an unmatched second warning): converted to `withCallingHandlers` pattern that captures all warnings and asserts the expected inner-estimator warning text is present.

New regression tests:
- Mock `did` absent → wrapper warns naming "callaway_santanna" + "NULL"
- When `did` present and estimation succeeds → wrapper does NOT emit the NULL guard warning

## Verification

Verification ran in the isolated git worktree `.claude/worktrees/rf-03-1579204-1788355551` (not the main checkout). Post-merge results in the main checkout:

- `test_export.R`: FAIL 0 | WARN 0 | SKIP 0 | PASS 79
- `test_synthetic_control.R`: FAIL 0 | WARN 0 | SKIP 0 | PASS 59
- `test_models_time_varying.R`: FAIL 0 | WARN 0 | SKIP 16 | PASS 56 (skips: rugarch/rmgarch absent)
- `test_panel.R`: FAIL 0 | WARN 0 | SKIP 6 | PASS 47 (skips: did/DIDmultiplegt/didimputation absent)
- **Full suite:** FAIL 0 | WARN 1 (pre-existing, cross_sectional rank-deficiency test) | SKIP 26 | PASS 1291

The pre-existing WARN at `test_edge_cases.R:817` was present before these fixes (cross_sectional_regression rank-deficiency warning from a test that intentionally triggers it — not caused by this fix set).

---

_Fixed: 2026-09-02_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
