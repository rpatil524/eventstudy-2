---
phase: 03-pipeline-and-external-hardening
plan: "02"
subsystem: external-packages
status: complete
tags: [external-packages, panel-did, garch, dcc-garch, synthetic-control, tryCatch, requireNamespace, testthat, mocking, warning, graceful-degradation]

requires:
  - phase: 02-model-and-stats-sweep
    provides: Phase 2 pre-call degenerate guards for GARCHModel/DCCGARCHModel; .handle_degenerate contract

provides:
  - "Panel-DiD estimators (callaway_santanna, dechaisemartin_dhaultfoeuille, borusyak_jaravel_spiess) degrade to warning+NULL on absent or failing optional packages"
  - "DIDmultiplegt opt-out via options(eventstudy.skip_didmultiplegt=TRUE) and opt-in callr subprocess probe"
  - ".compute_se emits warning() (not message()) when sandwich is absent; vcovCL wrapped in tryCatch"
  - "GARCHModel calculate_statistics failure resets is_fitted=FALSE + named warning + NA abnormal returns"
  - "DCCGARCHModel identical treatment for calculate_statistics failure"
  - "Synthetic control quadprog::solve.QP wrapped; empty donor pool guarded before max(theta)"

affects: [panel_event_study, GARCH_model, DCC_GARCH_model, synthetic_control, 03-01-SUMMARY]

actuals:
  tokens: 5934
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "stop()->warning(call.=FALSE)+return(invisible(NULL)) for absent optional packages"
    - "tryCatch around external call sites with conditionMessage(e) in warning text"
    - "is_fitted reset to FALSE in tryCatch error handler to prevent misleading state"
    - "local_mocked_bindings(.package='base') to intercept requireNamespace in EventStudy code"
    - "local_mocked_bindings(.package='rugarch'/.package='rmgarch'/.package='quadprog') for call-site mocking"
    - "NULL sentinel from .solve_sc_quadprog triggers optim fallback in caller"

key-files:
  created: []
  modified:
    - R/panel_event_study.R
    - R/models.R
    - R/models_time_varying.R
    - R/synthetic_control.R
    - tests/testthat/test_panel.R
    - tests/testthat/test_models_time_varying.R
    - tests/testthat/test_synthetic_control.R

key-decisions:
  - "Use .package='base' (not 'EventStudy') in local_mocked_bindings for requireNamespace — it lives in base, not in EventStudy namespace"
  - "DIDmultiplegt skip option (eventstudy.skip_didmultiplegt) checked AFTER package presence so mock in tests must also mock requireNamespace as returning TRUE"
  - ".solve_sc_quadprog returns NULL on failure; caller handles NULL->optim fallback (not inline in .solve_sc_quadprog)"
  - "Empty donor pool guard added at top of .solve_sc_optim (n==0 before max(theta) is called)"
  - "callr subprocess probe gated behind requireNamespace('callr') AND getOption('eventstudy.probe_didmultiplegt', FALSE) — default is tryCatch-only"

patterns-established:
  - "External-package absence: stop()->warning(call.=FALSE)+return(invisible(NULL)) naming the capability and suggesting an install command"
  - "External call-site wrapping: tryCatch(call, error = function(e) { warning(..., conditionMessage(e), ...); NULL })"
  - "Post-convergence statistics guard: tryCatch around private$calculate_statistics(); error handler resets is_fitted=FALSE"

requirements-completed: [EXTERNAL-01, EXTERNAL-02, EXTERNAL-03, EXTERNAL-04]

coverage:
  - id: D1
    description: "callaway_santanna degrades to warning+NULL when did is absent or att_gt fails"
    requirement: EXTERNAL-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_panel.R#callaway_santanna warns and returns task with NULL results when did is absent"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_panel.R#callaway_santanna tryCatch catches att_gt runtime failures"
        status: pass

  - id: D2
    description: "dechaisemartin_dhaultfoeuille degrades to warning+NULL on DIDmultiplegt absence; opt-out option; callr probe gate"
    requirement: EXTERNAL-02
    verification:
      - kind: unit
        ref: "tests/testthat/test_panel.R#dechaisemartin warns and returns task with NULL results when DIDmultiplegt is absent"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_panel.R#dechaisemartin opt-out option produces warning and NULL results"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_panel.R#dechaisemartin callr probe gate: probe option FALSE means no callr involvement"
        status: pass

  - id: D3
    description: "borusyak_jaravel_spiess degrades to warning+NULL when didimputation is absent or fails"
    requirement: EXTERNAL-03
    verification:
      - kind: unit
        ref: "tests/testthat/test_panel.R#borusyak_jaravel_spiess warns and returns task with NULL results when didimputation is absent"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_panel.R#borusyak_jaravel_spiess tryCatch catches did_imputation runtime failures"
        status: pass

  - id: D4
    description: ".compute_se emits warning() (not message()) when sandwich is absent; vcovCL wrapped in tryCatch"
    requirement: EXTERNAL-03
    verification:
      - kind: unit
        ref: "tests/testthat/test_panel.R#.compute_se emits warning (not message) when sandwich is absent"
        status: pass

  - id: D5
    description: "GARCHModel calculate_statistics failure resets is_fitted=FALSE + named warning + all-NA abnormal returns"
    requirement: EXTERNAL-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#GARCHModel: calculate_statistics failure resets is_fitted=FALSE + named warning + NA ARs"
        status: pass

  - id: D6
    description: "DCCGARCHModel calculate_statistics failure resets is_fitted=FALSE + named warning + all-NA abnormal returns"
    requirement: EXTERNAL-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#DCCGARCHModel: calculate_statistics failure resets is_fitted=FALSE + named warning + NA ARs"
        status: pass

  - id: D7
    description: "solve.QP failure degrades to optim fallback + warning; empty donor pool warns instead of crashing max()"
    requirement: EXTERNAL-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_synthetic_control.R#solve.QP failure (via mock) degrades to optim fallback without crashing"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_synthetic_control.R#solve.QP failure (via mock) produces named warning and falls back to optim"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_synthetic_control.R#empty donor pool (.solve_sc_optim n==0) warns and does not crash from max()"
        status: pass
---

# Phase 03 Plan 02: External-Package Wrapping Summary

**One-liner:** Wrapped all four external-package call sites (did, DIDmultiplegt, didimputation, sandwich) and both GARCH statistics paths (rugarch, rmgarch) with tryCatch+warning+NULL/NA degradation; added synthetic-control solve.QP and empty-pool guards.

## Accomplishments

- **Panel-DiD estimators (EXTERNAL-01/02/03):** Converted 3 `stop()` calls to `warning(call.=FALSE)+return(invisible(NULL))` in `.estimate_callaway_santanna`, `.estimate_dechaisemartin_dhaultfoeuille`, and `.estimate_borusyak_jaravel_spiess`. Added `tryCatch` around the actual `att_gt`, `did_multiplegt`, and `did_imputation` call sites so runtime failures (API mismatch, data errors) also produce warning+NULL instead of crashing.

- **DIDmultiplegt isolation (EXTERNAL-02):** Added opt-out `options(eventstudy.skip_didmultiplegt=TRUE)` and opt-in callr subprocess probe gated behind `requireNamespace("callr", quietly=TRUE) && isTRUE(getOption("eventstudy.probe_didmultiplegt", FALSE))`. callr stays out of DESCRIPTION.

- **sandwich upgrade (EXTERNAL-03):** `message()` to `warning()` at `.compute_se` absent-sandwich branch; `tryCatch` added around `sandwich::vcovCL` to catch singular cluster structures.

- **GARCHModel / DCCGARCHModel statistics guard (EXTERNAL-04):** `tryCatch` wraps `private$calculate_statistics(data_tbl)` in both models. Error handler sets `private$.is_fitted <- FALSE` + named warning with `conditionMessage(e)`. Phase 2 pre-call guards (lines 1001-1046 / 256-309) untouched.

- **Synthetic-control numerics (EXTERNAL-04):** `tryCatch` around `quadprog::solve.QP`; NULL return triggers optim fallback in `estimate_synthetic_control`. Empty donor pool (n=0) guard at top of `.solve_sc_optim` prevents `max(numeric(0))` crash.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing guard] .solve_sc_quadprog caller not updated for NULL sentinel**
- **Found during:** Task 3
- **Issue:** After wrapping `solve.QP` in tryCatch to return `NULL` on failure, the caller `estimate_synthetic_control` would pass `NULL` to `names(weights) <- donor_units`, crashing with "attempt to set attr on NULL"
- **Fix:** Added `if (is.null(weights)) { weights <- .solve_sc_optim(...) }` at the call site to route through optim fallback when quadprog returns NULL
- **Files modified:** R/synthetic_control.R
- **Commit:** 8d40019

**2. [Rule 1 - Bug] Collinear-donor test design flaw**
- **Found during:** Task 3 — initial test used identically-valued donors expecting solve.QP to crash; but the 1e-8 ridge prevents failure for mildly collinear cases
- **Fix:** Replaced with `local_mocked_bindings(.package="quadprog")` mocking `solve.QP` to directly simulate the failure condition; tests now reliably exercise the tryCatch code path
- **Commit:** 8d40019

**3. [Rule 1 - Bug] requireNamespace mock scope: .package="EventStudy" -> .package="base"**
- **Found during:** Task 1 — `local_mocked_bindings(.package="EventStudy")` throws "Can't find binding for requireNamespace" because `requireNamespace` is in the `base` namespace, not defined in EventStudy
- **Fix:** Changed all absence-mocking tests to `.package = "base"`
- **Files modified:** tests/testthat/test_panel.R
- **Commit:** 05376ba

**4. [Rule 2 - Missing guard] DIDmultiplegt opt-out test needed mock for requireNamespace**
- **Found during:** Task 1 — the opt-out test did not mock requireNamespace, so the missing-package warning fired before the skip option was reached, causing incorrect warning text mismatch
- **Fix:** Added `local_mocked_bindings(requireNamespace = function(pkg, ...) TRUE, .package = "base")` to make DIDmultiplegt appear installed so the skip option path is reached
- **Commit:** 05376ba

## Test Results

| Suite | Passed | Skipped | Failed |
|-------|--------|---------|--------|
| test_panel.R | 44 | 5 (did/DIDmultiplegt/didimputation not installed) | 0 |
| test_models_time_varying.R | 53 | 14 (rugarch/rmgarch not installed) | 0 |
| test_synthetic_control.R | 55 | 0 | 0 |
| Full suite | 1213 | 23 | 0 |

Full suite: 1 pre-existing error in `test_data_download.R` (network-dependent). Unrelated to this plan.

## Threat Flag Review

No new network endpoints, authentication paths, or file access patterns introduced. All changes wrap existing external function calls with error handlers. No new trust boundaries.

## Self-Check: PASSED

All committed files exist at their expected paths. All 3 task commits confirmed in git log:
- 05376ba: feat(03-02): panel-DiD absence+failure wrapping
- 01468ec: feat(03-02): GARCH/DCC-GARCH calculate_statistics failure wrapping
- 8d40019: feat(03-02): synthetic-control solve.QP + empty-donor-pool numerical guards
