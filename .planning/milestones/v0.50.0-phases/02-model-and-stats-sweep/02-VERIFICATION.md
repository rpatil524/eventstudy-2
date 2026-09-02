---
phase: 02-model-and-stats-sweep
verified: 2026-09-02T12:30:00Z
status: passed
score: 7/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: false
---

# Phase 02: Model and Stats Sweep — Verification Report

**Phase Goal:** Every return model AND every test statistic uniformly follows the Phase 1 degenerate-input contract — no component silently emits Inf/NaN or crashes on degenerate input.
**Verified:** 2026-09-02T12:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | Zero-variance estimation window → each model in lenient mode returns all-NA abnormal_returns (not Inf/NaN) | VERIFIED | Direct spot-check: VolatilityModel zero-variance → is_fitted=FALSE, all-NA ARs. Code guards confirmed in all 13 models via `.handle_degenerate()` before `is_fitted <- TRUE`. Full suite 1190/0/0. |
| SC2 | <2 estimation obs → strict errors naming event_id/firm_symbol; lenient is_fitted=FALSE | VERIFIED | Direct spot-check: VolatilityModel strict mode error contains "EVT_V" and "FIRM_V". Pattern confirmed in all models. |
| SC3 | df counts reflect only finite residuals (BHARModel .finite_residual_df fix; shared helper) | VERIFIED | Direct spot-check: BHARModel with 50 NA estimation rows yields df=69 (not nrow-1=119). `.finite_residual_df()` present in R/contract.R:65-70. Used at R/models.R:1270. |
| SC4 | Multi-event stats (Patell/BMP/KP) on firm appearing in >1 event: correct denominators — regression tests present and passing | VERIFIED | Test file test_multi_event_statistics.R: STATS-02 regression tests present (lines 545-560); 104/0/0 in test file. Direct spot-check: PatellZTest n_events==1 → aar_z=NA, caar_z=NA (PASS). Joins keyed on event_id not firm_symbol (confirmed in R/multi_event_test_statistics.R:108). |
| SC5 | CAR/CAAR chains tolerate a firm dropping mid-window — regression test present and passing | VERIFIED | STATS-03 regression tests present at lines 686-780 of test_multi_event_statistics.R. Direct spot-check: CSectTTest mid-window NA gap → CAAR continues as [0.01, 0.035], no NA propagation. cumsum(coalesce(abnormal_returns, 0)) pattern confirmed in source. |
| STATS-01 | ART/CART/BHART sigma==0 → NA (not Inf/NaN) guards present | VERIFIED | Guards confirmed in R/single_event_test_statistics.R at lines 71, 120, 199. Regression tests at test_ar_car_test_statistics.R lines 126-190. Condition: `is.na(sigma) || sigma < .Machine$double.eps`. |
| STATS-04 | Patell/Sign n_events==1 → NA guards present | VERIFIED | Guards in R/multi_event_test_statistics.R: PatellZTest aar_z at line 154 (`ifelse(n_valid_events <= 1, NA_real_, ...)`); caar_z at line 173 (propagated). SignTest sign_z at line 217 (`ifelse(n_valid_events >= 2, ..., NA_real_)`). Regression tests at lines 591-665. |

**Score:** 7/7 truths verified (0 present, behavior-unverified)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/contract.R` | `.finite_residual_df()` helper | VERIFIED | Present at line 65-70; returns `max(sum(is.finite(residuals)) - n_params, 1L)` |
| `R/models.R` | 10 models migrated (MarketAdjusted, CPM, Custom, LinearFactor, FF3, FF5, Carhart4, GARCH, BHAR, Volume, Volatility) | VERIFIED | All 11 R6 class definitions present; each has `.handle_degenerate()` guard before `is_fitted <- TRUE` and 3-branch abnormal_returns() |
| `R/models_time_varying.R` | RollingWindowModel, DCCGARCHModel migrated | VERIFIED | Guards at lines 44-71 (Guard 1,2), 118-128 (Guard 3) for RollingWindow; 261-303 for DCC-GARCH |
| `R/single_event_test_statistics.R` | sigma==0 guards in ARTTest/CARTTest/BHARTTest | VERIFIED | Lines 71, 120, 199 respectively |
| `R/multi_event_test_statistics.R` | n_events<=1 guards in PatellZTest, SignTest | VERIFIED | Lines 154/173 (Patell aar_z/caar_z), line 217 (Sign sign_z) |
| `tests/testthat/fixtures/contract05_*_baseline.rds` | 10 per-model baseline fixtures (+ 1 from Phase 1) | VERIFIED | 12 files present: bhar, carhart4, comparisonperiod, custom, ff3, ff5, linearfactor, marketadjusted, rollingwindow, volatility, volume + original baseline.rds |
| `tests/testthat/helper-mock-data.R` | Degenerate factories for volume/volatility/factor models | VERIFIED | create_degenerate_volume_model_data_insufficient, create_degenerate_volume_model_data_zero_variance, create_degenerate_volatility_model_data_zero_var, create_mock_factor_model_data |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Each model's `fit()` | `.handle_degenerate()` | Guard before `is_fitted <- TRUE` | WIRED | Confirmed in all 13 non-MarketModel models via grep |
| `.handle_degenerate()` | `private$.degenerate_handled = TRUE` | Side effect in lenient mode | WIRED | Confirmed in R/contract.R:93 |
| `abnormal_returns()` 3-branch | `private$.degenerate_handled` flag | `else if (private$.degenerate_handled)` | WIRED | Confirmed in all models |
| `BHARModel$calculate_statistics()` | `.finite_residual_df()` | Replaces `nrow()-1` | WIRED | Line 1270: `.finite_residual_df(bhar_residuals_finite, n_params = 1L)` |
| `GARCHModel$calculate_statistics()` | `n_valid_fec` | Replaces `nrow(estimation_tbl)` | WIRED | R/models.R:1145-1149 |
| `DCCGARCHModel$calculate_statistics()` | `n_valid_fec` | Same fix | WIRED | R/models_time_varying.R:436-440 |
| `VolatilityModel$fit()` | Guard before `is_fitted <- TRUE` | Relocated from calculate_statistics() | WIRED | Lines 1441-1477; comment at 1457-1460 confirms relocation |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `.finite_residual_df(c(1,2,NA,4))` returns 2 | Direct Rscript | 2 | PASS |
| `.finite_residual_df(c(1,NA,NA))` returns 1 (floored) | Direct Rscript | 1 | PASS |
| VolatilityModel zero-variance lenient: is_fitted=FALSE + all-NA + 1 warning | Direct Rscript | PASS | PASS |
| VolatilityModel strict: error contains event_id and firm_symbol | Direct Rscript | PASS | PASS |
| BHARModel with 50 NA rows: df=69 (not nrow-1=119) | Direct Rscript | 69 | PASS |
| PatellZTest n_events==1: aar_z=NA, caar_z=NA | Direct Rscript | NA, NA | PASS |
| SignTest n_events==1: sign_z=NA | Direct Rscript | NA | PASS |
| CSectTTest mid-window NA gap: CAAR=[0.01, 0.035] (no propagation) | Direct Rscript | [0.01, 0.035] | PASS |
| Full test suite | `devtools::test()` | 1190 pass / 0 fail / 0 error / 17 skip | PASS |
| test_multi_event_statistics.R | `testthat::test_file(...)` | 104 pass / 0 fail / 0 error | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MODELS-01 | 02-01, 02-02, 02-03 | Guard insufficient obs through .handle_degenerate() for all models | SATISFIED | All 13 non-MarketModel models have the guard |
| MODELS-02 | 02-01, 02-02, 02-03 | Zero/near-zero variance → one warning in lenient, named error in strict | SATISFIED | Guards confirmed; one-warning invariant enforced via .degenerate_handled flag |
| MODELS-03 | 02-01 | Finite-only df via .finite_residual_df() | SATISFIED | Helper in R/contract.R:65-70; applied in BHARModel |
| MODELS-04 | 02-03 | FEC preserved; GARCH/DCC FEC fixed to use n_valid not nrow | SATISFIED | n_valid_fec at models.R:1145 and models_time_varying.R:436 |
| STATS-01 | 02-04 | sigma==0 → NA in ARTTest/CARTTest/BHARTTest | SATISFIED | Guards at single_event_test_statistics.R:71, 120, 199 |
| STATS-02 | 02-04 | Firm appearing in >1 event: no many-to-many join inflation | SATISFIED | Joins on event_id; regression tests at test_multi_event_statistics.R:545-560 |
| STATS-03 | 02-04 | Mid-window NA gap does not corrupt CAR/CAAR | SATISFIED | coalesce(abnormal_returns,0) chains; regression tests at lines 686-780 |
| STATS-04 | 02-04 | n_events==1 → NA for Patell aar_z/caar_z and Sign sign_z | SATISFIED | Guards at multi_event_test_statistics.R:154, 173, 217 |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | Phase added only guards, helpers, and tests; no stubs or TBD/FIXME markers |

---

### Human Verification Required

None. All phase goal criteria are mechanically verifiable and confirmed by the test suite (1190 pass) plus direct spot-checks.

---

### Gaps Summary

No gaps. All 7 must-haves are verified against the actual codebase:

- SC1-SC3 and STATS-01/04: Guards exist in source and produce correct output under direct execution.
- SC4/STATS-02: Regression tests present and confirmed in a 104-test pass run; joins on event_id not firm_symbol is confirmed in source.
- SC5/STATS-03: Regression tests present; direct execution shows coalesce chains work correctly.
- Full suite: 1190 pass / 0 fail / 0 error. The 17 skips are all GARCH/DCC tests guarded by `skip_if_not_installed("rugarch")` / `skip_if_not_installed("rmgarch")` — acceptable per the verification method.

---

_Verified: 2026-09-02T12:30:00Z_
_Verifier: Claude (gsd-verifier)_
