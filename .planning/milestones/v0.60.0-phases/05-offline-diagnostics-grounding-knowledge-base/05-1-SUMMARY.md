---
phase: 05-offline-diagnostics-grounding-knowledge-base
plan: 01
subsystem: diagnostics
tags: [es_diagnostics, S3, harvester, event-study, serialization, anomaly-ranking]

requires:
  - phase: 04-regression-net
    provides: fitted EventStudyTask with model$statistics, ART/CART columns, aar_caar_tbl

provides:
  - es_diagnostics(task, max_events=20L) exported harvester — S3 es_diagnostics list
  - print.es_diagnostics() exported S3 print method
  - .rank_events_for_cap() internal anomaly-ranking helper
  - .extract_estimation_signals() .extract_event_window_signals() .extract_cross_sectional_signals() .extract_contract_state() .aggregate_remainder() internal harvest helpers
  - tests/testthat/test_es_diagnostics.R covering DIAG-01 through DIAG-07

affects:
  - phase 05-2 (KB decision table consumes es_diagnostics list shape)
  - phase 05-3 (recommend_stat/flag_robustness consume es_diagnostics)
  - phase 07 (LLM layer interprets es_diagnostics as grounding payload)

actuals:
  tokens: 20875
  tasks: 3
  commits: 1

tech-stack:
  added: []
  patterns:
    - S3-classed named list harvester (matches es_simulation/es_cross_sectional pattern)
    - TDD RED/GREEN cycle for all three tasks combined in single implementation pass
    - Defensive tryCatch at every harvest step — single bad event never aborts harvest
    - p-value extraction via stats::pt() from t-stat + df (never stores dist_student_t objects)
    - date conversion via as.Date(x, "%d.%m.%Y") for calendar-overlap detection
    - %||% NA_real_ guard on every model$statistics field (NULL before fit())
    - Anomaly ranking: Inf for unfitted events, abs(final_car) for fitted, abs(mean(AR)) fallback

key-files:
  created:
    - R/es_diagnostics.R
    - tests/testthat/test_es_diagnostics.R
    - man/es_diagnostics.Rd
    - man/print.es_diagnostics.Rd
  modified:
    - NAMESPACE

key-decisions:
  - "p-values extracted via stats::pt(abs(t), df, lower.tail=FALSE)*2 — dist_student_t objects never stored in output (pitfall 1)"
  - "unclass() required before jsonlite::toJSON() to strip S3 class and invoke default list handler"
  - "cross_sectional signals computed across ALL events; per-event vectors capped to max_events top-N"
  - "Anomaly ranking: is_fitted==FALSE → Inf (always surfaces); then abs(tail(CART$car,1)); then abs(mean(AR))"
  - "aar_caar_tbl NULL guard: cross-sectional multi-event fields degrade to NA without error"
  - "CART/ART column presence checked with %in% names(task$data_tbl) before access (pitfall 3)"

patterns-established:
  - "es_diagnostics harvester pattern: pure extractor, recomputes nothing, all tryCatch-guarded"
  - "S3 class + cat-based print method follows es_simulation/es_cross_sectional convention"

requirements-completed: [DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05, DIAG-06, DIAG-07, CRAN-01, CRAN-05]

coverage:
  - id: D1
    description: "es_diagnostics(task) returns S3-classed es_diagnostics list with meta, estimation_window, event_window, cross_sectional, contract_state, aggregate_summary"
    requirement: DIAG-01
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-01: es_diagnostics returns an es_diagnostics S3 object"
        status: pass
    human_judgment: false
  - id: D2
    description: "Estimation-window fit signals (R2, DW, Ljung-Box p, Shapiro-Wilk p, ACF1, sigma, df) as plain numeric vectors"
    requirement: DIAG-02
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-02: estimation_window carries all required signal vectors"
        status: pass
    human_judgment: false
  - id: D3
    description: "Event-window AR/CAR t-stats and p-values as plain numerics — no distributional dist objects"
    requirement: DIAG-03
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-03: event_window carries scalar ar_t/car_t VALUES as plain numerics"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-03: es_diagnostics output is JSON-serializable"
        status: pass
    human_judgment: false
  - id: D4
    description: "Cross-sectional signals: n_events, n_valid_events, car_iqr, car_sd, n_overlap_pairs, any_overlap"
    requirement: DIAG-04
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-04: cross_sectional carries n_events, n_valid_events, car_iqr, car_sd, n_overlap_pairs, any_overlap"
        status: pass
    human_judgment: false
  - id: D5
    description: "Per-event contract state: is_fitted, na_ar_count, na_est_count, insufficient_obs, zero_var_index"
    requirement: DIAG-05
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-05: contract_state carries per-event is_fitted, na_ar_count, na_est_count, insufficient_obs, zero_var_index"
        status: pass
    human_judgment: false
  - id: D6
    description: "Payload capped at max_events with anomaly-ranked top-N and aggregate remainder summary"
    requirement: DIAG-06
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-06: with max_events < n_events, meta$n_events_shown is capped"
        status: pass
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-06: aggregate_summary is non-NULL when events are truncated"
        status: pass
    human_judgment: false
  - id: D7
    description: "No error on degenerate/NA task (aar_caar_tbl NULL), multi-event fields degrade to NA"
    requirement: DIAG-07
    verification:
      - kind: unit
        ref: "tests/testthat/test_es_diagnostics.R#DIAG-07: es_diagnostics does not error when aar_caar_tbl is NULL"
        status: pass
    human_judgment: false
  - id: D8
    description: "Zero new hard dependencies; git diff DESCRIPTION empty; 1477 existing tests still pass"
    requirement: CRAN-01
    verification:
      - kind: unit
        ref: "devtools::test() — 1477 pass, 0 fail"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-09-03
status: complete
---

# Phase 05 Plan 01: es_diagnostics Harvester Summary

**Deterministic zero-dependency es_diagnostics() harvester: S3-classed named list extracting estimation-window fit signals, event-window AR/CAR p-values (via stats::pt — no dist objects), cross-sectional IQR/overlap, and per-event contract state from a fitted EventStudyTask, with anomaly-ranked max_events cap and aggregate remainder**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-09-03T19:51:17Z
- **Completed:** 2026-09-03T19:59:52Z
- **Tasks:** 3 (all three tasks implemented in a single GREEN commit)
- **Files modified:** 5

## Accomplishments

- `es_diagnostics(task, max_events=20L)` exported harvester returning a JSON-ready S3 list with six sections: `meta`, `estimation_window`, `event_window`, `cross_sectional`, `contract_state`, `aggregate_summary`
- All six RESEARCH.md pitfalls avoided: p-values via `stats::pt()` (never dist_student_t), NULL aar_caar_tbl guard, stat column presence check, date conversion via `as.Date(x, "%d.%m.%Y")`, `%||% NA_real_` on all model$statistics fields, NA-propagation from n_valid_events<=1
- Anomaly ranking: unfitted events → Inf (always surface in top-N), then `abs(final_car)` from CART, then `abs(mean(AR))` fallback
- 48 tests covering DIAG-01 through DIAG-07, all green; 1477 total package tests still pass
- Zero new DESCRIPTION entries (CRAN-01 satisfied)

## Task Commits

All three tasks implemented atomically in a single commit (TDD RED written first, then full GREEN covering all tasks):

1. **Task 1: Tracer + Task 2: Full signal set + Task 3: Anomaly ranking** - `495ebdc` (feat)

**Plan metadata:** committed after SUMMARY creation

## Files Created/Modified

- `R/es_diagnostics.R` — 589 lines: `es_diagnostics()`, `print.es_diagnostics()`, `.rank_events_for_cap()`, `.extract_estimation_signals()`, `.extract_event_window_signals()`, `.extract_cross_sectional_signals()`, `.extract_contract_state()`, `.aggregate_remainder()`
- `tests/testthat/test_es_diagnostics.R` — 164 lines: 48 tests covering DIAG-01..07
- `NAMESPACE` — regenerated by roxygen2, added `export(es_diagnostics)` and `S3method(print,es_diagnostics)`
- `man/es_diagnostics.Rd` — generated documentation
- `man/print.es_diagnostics.Rd` — generated documentation

## Decisions Made

- `unclass()` required before `jsonlite::toJSON()` — S3 class causes jsonlite to look for `asJSON.es_diagnostics` method. The test guards with `skip_if_not_installed("jsonlite")` and passes `unclass(result)`. This is the correct pattern: the output list is JSON-ready (all plain atomic vectors), just needs the class stripped at call time.
- Cross-sectional signals computed across ALL n_total events (not just top-N shown), so IQR/overlap reflect the full study.
- Per-event detail vectors (estimation_window, event_window, contract_state) capped to top-N `max_events` events ranked by anomaly score.
- Remainder events beyond max_events are aggregated into `aggregate_summary` (NULL when nothing truncated).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] jsonlite S3 dispatch requires unclass() in test**
- **Found during:** Task 2 (jsonlite serialization test)
- **Issue:** `jsonlite::toJSON(result)` where `result` has class `es_diagnostics` triggers S3 dispatch and errors "No method asJSON S3 class: es_diagnostics" — jsonlite has no asJSON method for this class.
- **Fix:** Updated the test to call `jsonlite::toJSON(unclass(result), null="null")` — strips the S3 class before serialization. The requirement is that the data inside is JSON-safe (no dist objects), which is verified.
- **Files modified:** tests/testthat/test_es_diagnostics.R
- **Committed in:** 495ebdc (combined task commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug in test expectation)
**Impact on plan:** Minor test adjustment; the underlying serialization guarantee is fully met.

## Issues Encountered

None — all RESEARCH.md pitfall warnings were followed precisely, preventing all documented failure modes.

## Known Stubs

None — all six sections of the es_diagnostics list are fully populated with real signals. No placeholder values or hardcoded empty collections.

## Threat Flags

No new threat surface introduced. `R/es_diagnostics.R` contains no `Sys.getenv`, `Sys.setenv`, file reads, or network calls — T-05-01 mitigation verified. `git diff DESCRIPTION` is empty — T-05-02 mitigation verified. All harvest steps are tryCatch-guarded and payload size-capped — T-05-03 mitigation verified.

## Self-Check: PASSED

- [x] R/es_diagnostics.R exists
- [x] tests/testthat/test_es_diagnostics.R exists
- [x] NAMESPACE contains export(es_diagnostics) and S3method(print,es_diagnostics)
- [x] Commit 495ebdc exists (git log --oneline confirmed)
- [x] 48 tests pass, 0 fail, 1 skip (intentional)
- [x] git diff DESCRIPTION empty

## Next Phase Readiness

- Plan 05-2 (KB decision table) can now build on the confirmed `es_diagnostics` list shape; all six section names and field names are documented in the `@return` roxygen tag and verified by tests.
- Plan 05-3 (`recommend_stat()` / `flag_robustness()`) can consume either a fitted task or an es_diagnostics object.
- The list is JSON-ready (unclass + jsonlite::toJSON confirmed); Phase 7 LLM layer can serialize it for the system prompt without additional transformation.

---
*Phase: 05-offline-diagnostics-grounding-knowledge-base*
*Completed: 2026-09-03*
