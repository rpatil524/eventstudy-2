---
phase: 01-contract-foundation
plan: 01
subsystem: modeling
tags: [R6, contract, degenerate-input, MarketModel, lenient, strict, ParameterSet]

requires: []

provides:
  - R/contract.R with ?degenerate-input-contract roxygen topic, .resolve_degenerate_mode(), and .handle_degenerate()
  - degenerate_handling field on ParameterSet (validated, printed)
  - MarketModel refactored onto shared helpers with degenerate_mode/event_id/firm_symbol fields
  - fit_model() threading mode+keys via explicit row-indexed purrr::map
  - tests/testthat/fixtures/contract05_baseline.rds frozen pre-refactor baseline

affects:
  - 01-02 (plan 02 regression tests consume .resolve_degenerate_mode, .handle_degenerate, and the contract05_baseline.rds fixture)
  - Phase 2 (applies contract pattern to all other models and test statistics)
  - Phase 3 (pipeline/window hardening reuses .handle_degenerate)

actuals:
  tokens: 21565
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Degenerate-input contract pattern: field-injection on cloned R6 model -> .resolve_degenerate_mode -> .handle_degenerate -> explicit private$.is_fitted<-FALSE"
    - "Explicit row-indexed purrr::map(seq_len(nrow(...)), function(i) ...) for threading outer-tibble keys into nested operations (avoids NSE ambiguity)"
    - "Roxygen doc-only NULL topic (@name) for user-findable contract documentation"

key-files:
  created:
    - R/contract.R
    - tests/testthat/fixtures/contract05_baseline.rds
  modified:
    - R/parameter_set.R
    - R/execute.R
    - R/models.R

key-decisions:
  - "Explicit row-indexed map used instead of purrr::pmap-inside-dplyr::mutate to avoid NSE evaluation ambiguity (plan mandate)"
  - "Three public fields (degenerate_mode, event_id, firm_symbol) added to MarketModel as post-clone injectable context; fit() signature unchanged"
  - "Strict stop() branch fully implemented in Task 2 — not deferred; .handle_degenerate returns invisible(FALSE) in lenient mode"
  - "Private environment mutation: private_env$.is_fitted <- FALSE inside .handle_degenerate works correctly because R6 private is an environment passed by reference; callers also set private$.is_fitted <- FALSE explicitly per warning 6"
  - "Task 3 required zero code changes: the refactor preserved valid-input numerical output exactly (diff=0 on all statistics)"

patterns-established:
  - "Pattern: all degenerate conditions route through .handle_degenerate(mode, condition, component, event_id, firm_symbol, private_env)"
  - "Pattern: .resolve_degenerate_mode(ps_value) — single choke point, no component reads the raw option"
  - "Pattern: explicit private$.is_fitted <- FALSE after .handle_degenerate at every lenient call site (strict branch stop()s, so flag never reached)"

requirements-completed: [CONTRACT-01, CONTRACT-02, CONTRACT-03, CONTRACT-04, CONTRACT-05]

coverage:
  - id: D1
    description: "R/contract.R: ?degenerate-input-contract roxygen topic + .resolve_degenerate_mode() + .handle_degenerate() with full strict stop() branch"
    requirement: CONTRACT-01
    verification:
      - kind: unit
        ref: "Rscript verification: .resolve_degenerate_mode(NULL)==\"lenient\", .resolve_degenerate_mode(\"strict\")==\"strict\""
        status: pass
    human_judgment: false

  - id: D2
    description: "ParameterSet degenerate_handling field: validated via match.arg, NULL defers to option/default, print() reports resolved mode"
    requirement: CONTRACT-02
    verification:
      - kind: unit
        ref: "Rscript verification: ParameterSet$new()$degenerate_handling==NULL; ParameterSet$new(degenerate_handling=\"strict\")$degenerate_handling==\"strict\""
        status: pass
    human_judgment: false

  - id: D3
    description: "MarketModel strict mode: stop() with component+event_id+firm_symbol+reason for insufficient-obs and zero-variance"
    requirement: CONTRACT-03
    verification:
      - kind: unit
        ref: "Task 2 verify script: grepl(\"EVT_K\", e) && grepl(\"FIRM_K\", e) && grepl(\"MarketModel\", e) for both insuff and zerovar conditions"
        status: pass
    human_judgment: false

  - id: D4
    description: "MarketModel lenient mode: is_fitted=FALSE, exactly 1 warning, all-NA abnormal_returns for both degenerate conditions"
    requirement: CONTRACT-04
    verification:
      - kind: unit
        ref: "Task 2 verify script: isFALSE(m$is_fitted) && length(ws)==1 && all(is.na(ar$abnormal_returns)) for insuff and zerovar conditions"
        status: pass
    human_judgment: false

  - id: D5
    description: "Valid non-degenerate input produces byte-identical statistics before and after refactor (CONTRACT-05)"
    requirement: CONTRACT-05
    verification:
      - kind: unit
        ref: "Task 3 verify: all differences from contract05_baseline.rds exactly 0 for alpha, beta, sigma, df=118, r2, f_stat, p-values, FEC[1:5], AR[1:5]"
        status: pass
    human_judgment: false

duration: 4min
completed: 2026-09-02
status: complete
---

# Phase 01 Plan 01: Contract Foundation Summary

**Degenerate-input contract for MarketModel: R/contract.R with .resolve_degenerate_mode/.handle_degenerate, ParameterSet field, execute.R row-indexed key threading, byte-identical valid-input output confirmed**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-09-02T07:58:21Z
- **Completed:** 2026-09-02T08:03:00Z
- **Tasks:** 3
- **Files modified:** 5 (4 R sources + 1 fixture)

## Accomplishments

- Created `R/contract.R` with the `?degenerate-input-contract` roxygen help topic, `.resolve_degenerate_mode()` (ParameterSet field -> package option -> "lenient"), and `.handle_degenerate()` with full strict `stop()` branch and lenient `warning()` + is_fitted mutation
- Added `degenerate_handling` field to `ParameterSet` with `match.arg` validation; `NULL` is legal (defer to option/default); `print()` reports resolved mode
- Refactored `fit_model()` in `execute.R` to use explicit `purrr::map(seq_len(nrow(task$data_tbl)), function(i) ...)` threading `degenerate_mode`, `event_id`, and `firm_symbol` into each model clone
- Refactored `MarketModel$fit()` onto the shared helpers: insufficient-obs (n_valid<2) and zero-variance guards route through `.handle_degenerate()`; lm() failure also routed; explicit `private$.is_fitted <- FALSE` at every lenient call site
- Captured pre-refactor `tests/testthat/fixtures/contract05_baseline.rds` (alpha=0.0007794771, beta=1.230661, sigma=0.009114413, df=118) and confirmed post-refactor differences are exactly 0

## Task Commits

Each task was committed atomically:

1. **Task 1: Capture pre-refactor CONTRACT-05 baseline** - `56122b8` (chore)
2. **Task 2: Full degenerate-input contract wired end-to-end** - `d510d8c` (feat)
3. **Task 3: CONTRACT-05 assert** — verified with zero code changes (refactor preserved valid-input behavior exactly)

## Files Created/Modified

- `R/contract.R` — New: roxygen doc topic, `.resolve_degenerate_mode()`, `.handle_degenerate()`
- `R/parameter_set.R` — Added `degenerate_handling` field with validation and print() output
- `R/execute.R` — Refactored `fit_model()` to explicit row-indexed map; updated `.initialize_and_fit_model()` to accept and inject mode+keys
- `R/models.R` — Added `degenerate_mode`, `event_id`, `firm_symbol` public fields to `MarketModel`; refactored `fit()` with two contract guards and lm()-failure routing
- `tests/testthat/fixtures/contract05_baseline.rds` — Frozen pre-refactor numerical baseline

## Decisions Made

- Explicit `purrr::map(seq_len(nrow(...)), function(i) ...)` chosen over `purrr::pmap-inside-dplyr::mutate` to avoid NSE evaluation ambiguity (per plan mandate)
- Three public fields (`degenerate_mode`, `event_id`, `firm_symbol`) added post-clone; `fit()` signature unchanged — no breakage to `ModelBase` interface or any other callers
- `private_env = private` passed to `.handle_degenerate()`; R6's `private` is an environment so external mutation works; callers also set `private$.is_fitted <- FALSE` explicitly (warning 6 defense-in-depth)
- `ModelBase$calculate_forecast_error_correction()` line 76 (`ss_market < .Machine$double.eps`) left byte-for-byte unchanged — it is a FEC fallback, not a degeneracy signal

## Deviations from Plan

None — plan executed exactly as written.

Task 3 produced no separate commit because no source code changes were required (the refactor in Task 2 preserved valid-input behavior exactly). This is correct: Task 3 is a verification task whose done-criteria is proven and documented here.

## Issues Encountered

None. The R6 private-environment mutation assumption (Research Open Question 1) was validated in-situ: `private_env$.is_fitted <- FALSE` inside `.handle_degenerate()` correctly mutates the original R6 private environment.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes. The `match.arg()` validation on `degenerate_handling` (STRIDE T-01-01 mitigation) is implemented.

## Self-Check

- `R/contract.R` exists: FOUND
- `R/parameter_set.R` modified: FOUND
- `R/execute.R` modified: FOUND
- `R/models.R` modified: FOUND
- `tests/testthat/fixtures/contract05_baseline.rds` exists: FOUND
- Task 1 commit 56122b8: FOUND
- Task 2 commit d510d8c: FOUND
- All CONTRACT-05 assertions pass (diff=0): CONFIRMED

## Self-Check: PASSED

## Next Phase Readiness

- Plan 02 can immediately consume `.resolve_degenerate_mode()`, `.handle_degenerate()`, and `contract05_baseline.rds` for regression tests
- The pattern (field injection -> resolver -> handler -> explicit flag) is ready for Phase 2 to apply across all models and test statistics
- `?degenerate-input-contract` will be user-findable once `devtools::document()` is run (Plan 02 includes this step)

---
*Phase: 01-contract-foundation*
*Completed: 2026-09-02*
