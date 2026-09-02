---
phase: 02-model-and-stats-sweep
plan: "04"
subsystem: testing
tags: [r, testthat, test-statistics, robustness, sigma-guard, n-events-guard]

requires:
  - phase: 01-contract-foundation
    provides: degenerate-input contract (.handle_degenerate, ModelBase fields, MarketModel exemplar)

provides:
  - sigma==0 guard in ARTTest/CARTTest/BHARTTest returning NA instead of Inf
  - n_events<=1 guard in PatellZTest (aar_z/caar_z) and SignTest (sign_z) returning NA
  - STATS-02 regression tests locking event_id-based join correctness (firm-in-2-events)
  - STATS-03 regression tests locking coalesce-based NA-safe cumsum chains (mid-window drop)
  - STATS-04 regression tests locking n_events==1 to NA behavior

affects:
  - 04-regression-matrix (acceptance test matrix)

actuals:
  tokens: 5689
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Denominator guard: sigma_degenerate <- is.na(sigma) || sigma < .Machine$double.eps before t-statistic division"
    - "n_events guard: ifelse(n_valid_events <= 1, NA_real_, stat) for Patell/Sign"
    - "Regression test pattern: build minimal fixture, assert guard fires, assert valid path unchanged"

key-files:
  created: []
  modified:
    - R/single_event_test_statistics.R
    - R/multi_event_test_statistics.R
    - tests/testthat/test_ar_car_test_statistics.R
    - tests/testthat/test_multi_event_statistics.R
    - tests/testthat/test_edge_cases.R
    - .gitignore

key-decisions:
  - "STATS-01 guard uses is.na(sigma) || sigma < .Machine$double.eps (covers both NA and near-zero, consistent with contract.R pattern)"
  - "STATS-04 PatellZTest: guard applied at aar_z computation AND propagated to caar_z via second mutate after join (simplest approach)"
  - "STATS-04 SignTest: guard changed from n_valid_events > 0 to n_valid_events >= 2 (one-line delta, semantically correct)"
  - "test_edge_cases.R 'SignTest with single event still computes' updated to assert NA behavior (old assertion documented the bug)"
  - "STATS-02/STATS-03 are verify-and-lock: code was already correct, tests prove it and guard against regression"

patterns-established:
  - "Denominator guard pattern for single-event stats: compute degenerate flag once, use in mutate scalar-wrapped if/else or ifelse"
  - "n_events guard pattern: apply at the summarise step (aar_z) and propagate to derived stats (caar_z) via post-join mutate"

requirements-completed: [STATS-01, STATS-02, STATS-03, STATS-04]

coverage:
  - id: D1
    description: "ARTTest returns NA (not Inf/NaN) in ar_t when model sigma == 0 or NA"
    requirement: STATS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_ar_car_test_statistics.R#STATS-01: ARTTest returns NA (not Inf/NaN) when sigma == 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "CARTTest returns NA (not Inf/NaN) in car_t when model sigma == 0 or NA"
    requirement: STATS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_ar_car_test_statistics.R#STATS-01: CARTTest returns NA (not Inf/NaN) in car_t when sigma == 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "BHARTTest returns NA (not Inf/NaN) in bhar_t when model sigma == 0 or NA"
    requirement: STATS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_ar_car_test_statistics.R#STATS-01: BHARTTest returns NA (not Inf/NaN) in bhar_t when sigma == 0"
        status: pass
    human_judgment: false
  - id: D4
    description: "PatellZTest aar_z and caar_z return NA when n_events == 1"
    requirement: STATS-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_multi_event_statistics.R#STATS-04: PatellZTest aar_z is NA (not finite) when n_events == 1"
        status: pass
    human_judgment: false
  - id: D5
    description: "SignTest sign_z returns NA when n_events == 1"
    requirement: STATS-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_multi_event_statistics.R#STATS-04: SignTest sign_z is NA (not finite) when n_events == 1"
        status: pass
    human_judgment: false
  - id: D6
    description: "Firm appearing in multiple events does not inflate n_events count in any stat (STATS-02)"
    requirement: STATS-02
    verification:
      - kind: unit
        ref: "tests/testthat/test_multi_event_statistics.R#STATS-02: CSectTTest does not inflate n_events when firms recur"
        status: pass
    human_judgment: false
  - id: D7
    description: "Mid-window NA gap does not corrupt post-gap CARs/CAAR (STATS-03)"
    requirement: STATS-03
    verification:
      - kind: unit
        ref: "tests/testthat/test_multi_event_statistics.R#STATS-03: CSectTTest mid-window NA gap does not corrupt post-gap CARs"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-09-02
status: complete
---

# Phase 02 Plan 04: Test Statistics Sweep Summary

**Surgical sigma==0 and n_events==1 denominator guards added to 5 test statistics; STATS-02/03/04 correctness locked with regression tests; full 409-test suite green.**

## Performance

- **Duration:** 8 min
- **Tests run:** 409 (full suite); all pass, 0 errors

## Accomplishments

- **STATS-01:** ARTTest, CARTTest, and BHARTTest now return `NA_real_` (never `Inf`/`NaN`) when the model's sigma is zero or near-zero (`< .Machine$double.eps`). Guard is a scalar flag computed once per `compute()` call, applied via `if`/`ifelse` in the `mutate` expressions. Valid-input t-statistics are byte-identical to pre-change.

- **STATS-04:** PatellZTest `aar_z`/`caar_z` and SignTest `sign_z` now return `NA_real_` when `n_valid_events <= 1` (Patell) or `< 2` (Sign). These were previously producing finite-but-statistically-invalid numbers. CSectTTest/BMPTest/KolariPynnonenTest were already correct — verified and locked.

- **STATS-02 (verify-and-lock):** Regression tests confirm that a firm appearing in multiple events does not inflate `n_events`/`n_valid_events` in CSectTTest, BMPTest, KolariPynnonenTest, or PatellZTest. Joins are on `event_id` not `firm_symbol` — already correct since GH #7 / commit 63d67a1. Tests guard against regression.

- **STATS-03 (verify-and-lock):** Regression tests confirm that a mid-window NA gap (firm "drops out" for one day) does not corrupt post-gap cumulative CARs/CAAR. The `cumsum(coalesce(abnormal_returns, 0))` chains in CSectTTest and SignTest treat the gap as a 0 contribution, continuing correctly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated test_edge_cases.R assertion for SignTest with n==1**

- **Found during:** Task 3 (full suite run)
- **Issue:** `test_edge_cases.R` line 46 asserted `all(is.finite(result$sign_z))` for n==1, which was documenting the pre-STATS-04 buggy behavior. After the STATS-04 guard was applied, this test failed.
- **Fix:** Updated the test name and assertion to expect `all(is.na(result$sign_z))` — the correct STATS-04 behavior. Also verified `aar` is still finite.
- **Files modified:** `tests/testthat/test_edge_cases.R`
- **Commit:** f620486

## Known Stubs

None — all deliverables are fully implemented and tested.

## Threat Flags

None — this plan adds only internal denominator guards and regression tests. No new network endpoints, auth paths, file access, or external calls.

## Self-Check: PASSED

- `R/single_event_test_statistics.R` — FOUND, guards at lines 71, 120, 199
- `R/multi_event_test_statistics.R` — FOUND, guards at lines 154, 173, 217
- `tests/testthat/test_ar_car_test_statistics.R` — FOUND, 14 tests (7 STATS-01 regression)
- `tests/testthat/test_multi_event_statistics.R` — FOUND, 37 tests (STATS-02/03/04 regression)
- Commits 624bee6, 9f7daff, f620486 — all verified in git log
- Full suite: 409 tests, 0 failed, 0 errors
