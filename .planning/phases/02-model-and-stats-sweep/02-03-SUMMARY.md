---
phase: 02-model-and-stats-sweep
plan: 03
subsystem: modeling
tags: [R6, contract, degenerate-input, RollingWindowModel, GARCHModel, DCCGARCHModel, time-varying, external-package, FEC, n_valid]

requires:
  - phase: 01-contract-foundation
    provides: ".resolve_degenerate_mode(), .handle_degenerate(), ModelBase fields, .degenerate_handled private flag"
  - plan: 02-01
    provides: ".finite_residual_df() helper, degenerate factories (insufficient, zero-variance)"
  - plan: 02-02
    provides: "LinearFactorModel migration pattern (confirmed same guard shape applies)"

provides:
  - "RollingWindowModel fully migrated onto .handle_degenerate() — all three guards (insufficient obs, effective window < 3, last-window NA params)"
  - "GARCHModel pre-call contract guards BEFORE rugarch::ugarchspec(); failure wrapping untouched"
  - "DCCGARCHModel pre-call contract guards (insufficient obs + BOTH series zero-variance) BEFORE returns_mat cbind; failure wrapping untouched"
  - "GARCH FEC uses n_valid_fec (finite obs) instead of nrow(estimation_tbl) — MODELS-04 fix"
  - "DCC-GARCH FEC uses n_valid_fec — same fix"
  - "Three-branch abnormal_returns() (fitted / degenerate_handled / else) on all three models"
  - "CONTRACT-05 baseline fixture: tests/testthat/fixtures/contract05_rollingwindow_baseline.rds"
  - "Skip-guarded GARCH/DCC degenerate contract tests in test_models_time_varying.R"

affects:
  - "02-04 (test statistics sweep: all three models now correctly return NA abnormal returns on degenerate input)"

actuals:
  tokens: 28000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Phase 2/3 boundary enforced: pre-call guards inserted BEFORE external package calls; purrr::safely() / convergence / failure warnings left byte-for-byte intact"
    - "RollingWindow guard upgrade: Guard 1 now uses n_valid (finite-pair count) not nrow — catches NA-heavy estimation windows that passed the old nrow check"
    - "DCC-GARCH zero-variance: TWO separate .handle_degenerate() calls — one per series — so the condition string names which series triggered the guard"
    - "FEC n_valid_fec pattern: compute sum(!is.na(firm) & !is.na(index)) in calculate_statistics() to pass as estimation_window_length, replacing nrow(estimation_tbl)"

key-files:
  created:
    - tests/testthat/fixtures/contract05_rollingwindow_baseline.rds
  modified:
    - R/models_time_varying.R
    - R/models.R
    - tests/testthat/test_models_time_varying.R

key-decisions:
  - "RollingWindowModel Guard 1 upgraded to use n_valid (finite obs) rather than nrow — the old check was insufficient: 30 rows with 29 NAs would pass nrow >= 30 but fail the actual rolling OLS"
  - "DCC-GARCH zero-variance guard split into two calls (firm_returns, index_returns) with separate condition strings per 02-RESEARCH §8.5 — naming which series triggered is actionable for diagnostics"
  - "GARCH and DCC-GARCH FEC both fixed to use n_valid_fec (re-computed inside calculate_statistics()) — keeping fit() and calculate_statistics() decoupled rather than threading n_valid across method boundary"
  - "Phase 3 boundary strictly maintained: purrr::safely(ugarchfit), purrr::safely(dccfit), rugarch::convergence check, rcov convergence check, and all four failure/convergence warning() calls are byte-for-byte identical to pre-migration state"
  - "GARCH/DCC valid-input baselines implemented as code (determinism test within tolerance) inside skip_if_not_installed blocks rather than pre-saved .rds — avoids checking in binary that requires the package to generate"

requirements-completed: [MODELS-01, MODELS-02, MODELS-03, MODELS-04]

coverage:
  - id: D1
    description: "RollingWindowModel Guard 1 (insufficient obs) uses n_valid not nrow; routes through .handle_degenerate()"
    requirement: MODELS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#RollingWindowModel: lenient mode — insufficient obs (Guard 1)"
        status: pass
    human_judgment: false

  - id: D2
    description: "RollingWindowModel Guard 3 (last-window NA params) routes through .handle_degenerate(); zero-variance estimation window triggers it"
    requirement: MODELS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#RollingWindowModel: lenient mode — Guard 3 (last-window NA params from constant index)"
        status: pass
    human_judgment: false

  - id: D3
    description: "RollingWindowModel strict mode raises named error containing event_id and firm_symbol"
    requirement: MODELS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#RollingWindowModel: strict mode — insufficient obs — named error with keys"
        status: pass
    human_judgment: false

  - id: D4
    description: "RollingWindowModel abnormal_returns() three-branch: degenerate_handled returns all-NA silently (no second warning)"
    requirement: MODELS-02
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#RollingWindowModel: lenient mode — insufficient obs (Guard 1)"
        status: pass
    human_judgment: false

  - id: D5
    description: "RollingWindowModel valid-input numerics invariant at 1e-8 (CONTRACT-05)"
    requirement: MODELS-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#RollingWindowModel: valid-input baseline invariant at 1e-8 (CONTRACT-05)"
        status: pass
    human_judgment: false

  - id: D6
    description: "GARCHModel pre-call guards fire BEFORE rugarch::ugarchspec(); insufficient obs and zero-variance index_returns handled"
    requirement: MODELS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#GARCHModel: lenient mode — insufficient obs"
        status: "skip (rugarch not installed)"
    human_judgment: false

  - id: D7
    description: "GARCHModel FEC uses n_valid_fec (finite obs) not nrow — MODELS-04 fix"
    requirement: MODELS-04
    verification:
      - kind: code_review
        ref: "R/models.R GARCHModel$private$calculate_statistics: n_valid_fec computation"
        status: pass
    human_judgment: false

  - id: D8
    description: "DCCGARCHModel pre-call guards fire BEFORE returns_mat cbind; two guards for firm_returns and index_returns with named condition strings"
    requirement: MODELS-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_models_time_varying.R#DCCGARCHModel: lenient mode — insufficient obs"
        status: "skip (rmgarch not installed)"
    human_judgment: false

  - id: D9
    description: "Phase 3 boundary: purrr::safely(ugarchfit)/purrr::safely(dccfit) + all convergence + failure warnings untouched"
    requirement: MODELS-01
    verification:
      - kind: code_review
        ref: "grep confirms 1 purrr::safely(rugarch) in models.R and 1 purrr::safely(rmgarch) in models_time_varying.R"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-09-02
status: complete
---

# Phase 02 Plan 03: Time-Varying / External Model Sweep Summary

**RollingWindowModel fully migrated onto .handle_degenerate() with n_valid upgrade; GARCHModel and DCCGARCHModel receive PRE-CALL contract guards before external package calls with FEC n_valid fix; Phase 3 failure wrapping untouched**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-09-02T11:43:14Z
- **Completed:** 2026-09-02T11:52:00Z
- **Tasks:** 2
- **Files modified:** 2 R sources + 1 test file + 1 binary fixture

## Accomplishments

- **RollingWindowModel (pure in-package):** All three existing plain `warning()` guards replaced with `.handle_degenerate()` calls. Guard 1 upgraded to use n_valid (finite-pair count) not nrow — the old check would pass an estimation window of 30 rows if 29 had NA returns. Guards 2 (ws < 3) and 3 (last-window NA params) ported as-is. The three-branch `abnormal_returns()` structure added. df = ws - 2 and FEC left unchanged (correct for rolling domain per 02-RESEARCH §3).

- **GARCHModel (external, pre-call only):** Two guards inserted BEFORE `rugarch::ugarchspec()`: insufficient-obs (n_valid < 2) and zero-variance in index_returns. Both route through `.handle_degenerate()`. Three-branch `abnormal_returns()` added. FEC fixed from `nrow(estimation_tbl)` to `n_valid_fec`. The existing `purrr::safely(ugarchfit)`, `rugarch::convergence()` check, and both convergence/failure `warning()` calls are byte-for-byte identical.

- **DCCGARCHModel (external, pre-call only):** Three guards inserted BEFORE `returns_mat <- cbind(...)`: insufficient-obs (n_valid < 2), zero-variance firm_returns, zero-variance index_returns. Each zero-variance guard names the specific series in its condition string. Three-branch `abnormal_returns()` added. FEC fixed similarly. Phase 3 failure handling untouched.

- **Baseline:** CONTRACT-05 fixture captured for RollingWindowModel; GARCH/DCC baselines implemented as determinism tests within skip blocks.

- **Test suite:** 1190 pass / 0 fail / 0 error / 17 skip (all skips correct for absent optional packages).

## Task Commits

1. **Task 1: RollingWindowModel migration** - `d5d4413` (feat)
2. **Task 2: GARCH + DCC guards + FEC fix** - `91fb245` (feat)

## Files Created/Modified

- `R/models_time_varying.R` — RollingWindowModel: 3 guards + 3-branch AR; DCCGARCHModel: 3 pre-call guards + 3-branch AR + n_valid_fec
- `R/models.R` — GARCHModel: 2 pre-call guards + 3-branch AR + n_valid_fec
- `tests/testthat/test_models_time_varying.R` — 18 new tests: RollingWindow Guards 1/3 (lenient+strict), CONTRACT-05 baseline; GARCH/DCC degenerate + zero-variance (all skip_if_not_installed)
- `tests/testthat/fixtures/contract05_rollingwindow_baseline.rds` — RollingWindow valid-input baseline

## Decisions Made

- Guard 1 for RollingWindow uses n_valid not nrow to correctly catch NA-heavy windows
- DCC-GARCH zero-variance uses two separate `.handle_degenerate()` calls (not a combined OR condition) so the condition string names which series caused the failure — actionable diagnostic information
- GARCH/DCC FEC fix computed as `n_valid_fec` inside `calculate_statistics()` rather than threading `n_valid` from `fit()` through the call chain — keeps the methods decoupled and independent
- Phase 3 boundary strictly maintained: only pre-call guards added; no touch of purrr::safely() wrappers, convergence checks, or existing failure warnings

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written. The FEC n_valid fix was explicitly planned per 02-RESEARCH §8.7 / Pitfall 4.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries.

## Self-Check

- `tests/testthat/fixtures/contract05_rollingwindow_baseline.rds` exists: FOUND
- `.handle_degenerate` in models_time_varying.R: FOUND
- `n_valid_fec` in GARCH FEC (models.R): FOUND
- `n_valid_fec` in DCC FEC (models_time_varying.R): FOUND
- Phase 3 `purrr::safely(rugarch)` in models.R: FOUND (count=1)
- Phase 3 `purrr::safely(rmgarch)` in models_time_varying.R: FOUND (count=1)
- Task 1 commit d5d4413: FOUND
- Task 2 commit 91fb245: FOUND
- Full suite 1190 pass, 0 failed, 0 errors: CONFIRMED

## Self-Check: PASSED

---
*Phase: 02-model-and-stats-sweep*
*Completed: 2026-09-02*
