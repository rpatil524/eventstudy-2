---
phase: 03-pipeline-and-external-hardening
plan: 01
subsystem: pipeline
tags: [pipeline, prepare, export, cross_sectional, degenerate-input, contract, R6, testthat, PIPELINE-01, PIPELINE-02, PIPELINE-03]

requires:
  - 01-01 (R/contract.R with .handle_degenerate, .resolve_degenerate_mode)
  - 01-02 (ParameterSet degenerate_handling field)

provides:
  - prepare_event_study() with mode-honoring missing-date/empty-window degradation
  - .append_windows() signature extended with mode/event_id/firm_symbol params
  - export_results() / tidy() CAR columns use coalesce-guarded cumsum
  - cross_sectional_regression() with tryCatch around lm()+vcovHC, rank-deficiency guard, message->warning upgrade
  - tests/testthat/test_prepare.R (new)
  - tests/testthat/test_export.R (expanded with 9 NA-safety regression tests)
  - tests/testthat/test_cross_sectional.R (expanded with 5 singular/sandwich tests)

affects:
  - 03-02 (parallel plan — no shared files)
  - Phase 4 (regression net consumes these hardened behaviors)

actuals:
  tokens: 38000
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Explicit row-indexed purrr::map(seq_len(nrow(...)), function(i) ...) for threading mode/event_id/firm_symbol into .append_windows() (replicated from Phase 1 D-01 pattern)"
    - "tryCatch around stats::lm() + sandwich::vcovHC with name-aligned SE vector for rank-deficient designs"
    - "with_mocked_bindings(.package='base') for simulating requireNamespace absence in testthat 3.3.2"

key-files:
  created:
    - tests/testthat/test_prepare.R
  modified:
    - R/prepare_event_study.R
    - R/export.R
    - R/cross_sectional.R
    - tests/testthat/test_export.R
    - tests/testthat/test_cross_sectional.R
    - tests/testthat/test_edge_cases.R

decisions:
  - "Explicit row-indexed map reused from Phase 1 (D-01) — NOT purrr::pmap-inside-dplyr::mutate — to avoid NSE evaluation ambiguity"
  - "All-zero window return (event_window=0L/estimation_window=0L) chosen for lenient missing-date path so model-layer n_valid guard fires cleanly without a missing-column crash (OQ-1 resolved)"
  - "coalesce(abnormal_returns, 0) applied to CAR cumsum in .build_export_tables only; AR column preserves raw NA; .tidy_car already had coalesce and was left unchanged"
  - "Name-aligned SE vector built by setNames+subset when vcovHC returns a reduced matrix (dropping aliased columns) to prevent row-count mismatch in coef_tbl data.frame construction"
  - "with_mocked_bindings(.package='base') required for requireNamespace mock — the function lives in base, not in EventStudy namespace; local_mocked_bindings(.package='EventStudy') silently fails"
  - "Two pre-existing test_edge_cases.R tests updated (Rule 1 auto-fix): .append_windows now warns not errors; cross_sectional lm() failure now warns+NULL not crashes"

metrics:
  duration: 12min
  completed: "2026-09-02T13:02:10Z"
  started: "2026-09-02T12:49:59Z"

status: complete
---

# Phase 03 Plan 01: Pipeline Hardening Summary

**Mode-honoring missing-date degradation in prepare_event_study(), coalesce-guarded CAR cumsum in export, and tryCatch singular/collinear guard + message->warning in cross_sectional_regression()**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-09-02T12:49:59Z
- **Completed:** 2026-09-02T13:02:10Z
- **Tasks:** 3 (+ 1 deviation fix commit)
- **Files modified:** 6 R sources + 1 new test file

## Accomplishments

- Refactored `prepare_event_study()` to resolve degenerate mode once (via `.resolve_degenerate_mode()`) and thread it into `.append_windows()` via explicit row-indexed `purrr::map(seq_len(nrow(task$data_tbl)), function(i) ...)` (Phase 1 D-01 pattern replicated)
- Extended `.append_windows()` signature to `(data_tbl, request, mode="lenient", event_id=NULL, firm_symbol=NULL)` and replaced the unconditional `stop()` at lines 109-113 with `.handle_degenerate()` dispatch; lenient returns `data_tbl` with `event_window=0L/estimation_window=0L` so the model-layer `n_valid` guard fires cleanly
- Upgraded `.build_export_tables()` CAR path from `cumsum(abnormal_returns)` to `cumsum(dplyr::coalesce(abnormal_returns, 0))` (`.tidy_car` already had coalesce; now both export paths are consistent); AR column keeps raw NA
- Added `tryCatch` around `stats::lm()` in `cross_sectional_regression()`: lm() error -> warning + return(NULL)
- Added rank-deficiency detection (`fit$rank < length(coef(fit))`): emits one informative warning before the sandwich path
- Added `tryCatch` around `sandwich::vcovHC()` with name-aligned SE vector: aliased coefficient positions receive `NA_real_` so the `coef_tbl` rows match the full `coef(fit)` vector including NA-coefficient positions
- Upgraded `message()` -> `warning()` at cross_sectional.R line 75, naming the lost capability (cluster/robust SEs) and the OLS fallback (EXTERNAL-03 pipeline half)
- Created `tests/testthat/test_prepare.R` with 5 tests covering lenient (1 warning with keys), strict (stop with keys), valid-date unchanged, mixed valid+bad two-firm task
- Added 9 regression tests to `test_export.R` covering all four tidy types with NA abnormal returns + coalesce no-op on finite input
- Added 5 tests to `test_cross_sectional.R` covering singular design, sandwich-absent warning (via `with_mocked_bindings(.package="base")`), well-conditioned OLS unchanged

## Task Commits

1. **Task 1: Mode-honoring missing-date degradation** — `2962a10` (feat)
2. **Task 2: Coalesce-guarded CAR + NA-safety tests** — `305d9d3` (feat)
3. **Task 3: Singular/collinear guard + sandwich warning** — `52f3d40` (feat)
4. **Deviation fix: test_edge_cases.R updated** — `d48f90a` (fix)

## Files Created/Modified

- `R/prepare_event_study.R` — Degenerate mode threading; .append_windows() extended signature and .handle_degenerate() dispatch
- `R/export.R` — CAR cumsum upgraded to coalesce in .build_export_tables()
- `R/cross_sectional.R` — tryCatch around lm()+vcovHC; rank-deficiency guard; message->warning
- `tests/testthat/test_prepare.R` — New: 5 tests for PIPELINE-01
- `tests/testthat/test_export.R` — Expanded: 9 NA-safety regression tests for PIPELINE-02
- `tests/testthat/test_cross_sectional.R` — Expanded: 5 tests for PIPELINE-03/EXTERNAL-03
- `tests/testthat/test_edge_cases.R` — 2 pre-existing tests updated to match new behavior

## Decisions Made

- Explicit row-indexed map (Phase 1 D-01) replicated exactly — no purrr::pmap-inside-mutate
- All-zero window return in lenient missing-date path (OQ-1 resolution) so downstream filter(estimation_window==1) yields 0 rows without crashing
- Name-aligned SE vector via `setNames + subset` to handle the vcovHC reduced matrix (which drops aliased columns) without a row-count mismatch in data.frame construction
- `with_mocked_bindings(.package="base")` required for `requireNamespace` mocking — testthat's `.package="EventStudy"` cannot find the binding since requireNamespace is not imported into the EventStudy namespace

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] pre-existing test_edge_cases.R tests assumed old stop() behavior**
- **Found during:** Full suite regression check after Task 3
- **Issue:** Two tests in `test_edge_cases.R` expected the OLD unconditional `stop()` behavior:
  - `.append_windows errors when event date not found in data` — expected `expect_error()`
  - `cross_sectional_regression with all-NA abnormal returns gives NA CARs` — expected `expect_error("0 (non-NA) cases")`
- **Fix:** Updated both tests to match the new mode-honoring contract: `.append_windows` now emits a warning in lenient mode (not an error), and `cross_sectional_regression` emits a warning + returns NULL when lm() fails (not a crash)
- **Files modified:** `tests/testthat/test_edge_cases.R`
- **Commit:** `d48f90a`

### Research Finding (OQ-2 confirmed)
The RESEARCH.md noted no crash-producing NA-on-if vulnerabilities in export.R (all if() branches are safe). The plan chose Option (b): proactively upgrade CAR cumsum to coalesce + add regression tests. This was implemented as specified.

### vcovHC Dimension Mismatch Discovery
`sandwich::vcovHC()` on a rank-deficient lm() fit returns a matrix with rows/columns only for the non-aliased terms, while `stats::coef(fit)` returns a vector with NA entries for aliased terms. A naive `sqrt(diag(vcov_hc))` assignment would produce a length mismatch in the `data.frame()` call. Fix: built a full-length SE vector via `setNames(rep(NA_real_, length(all_names)), all_names)` then filled in the fitted SE by name.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check

- `R/prepare_event_study.R` modified: FOUND
- `R/export.R` modified: FOUND
- `R/cross_sectional.R` modified: FOUND
- `tests/testthat/test_prepare.R` created: FOUND
- `tests/testthat/test_export.R` expanded: FOUND
- `tests/testthat/test_cross_sectional.R` expanded: FOUND
- `tests/testthat/test_edge_cases.R` updated: FOUND
- Task 1 commit 2962a10: FOUND
- Task 2 commit 305d9d3: FOUND
- Task 3 commit 52f3d40: FOUND
- Deviation fix commit d48f90a: FOUND
- Full suite: 0 failed, 0 errors: CONFIRMED

## Self-Check: PASSED
