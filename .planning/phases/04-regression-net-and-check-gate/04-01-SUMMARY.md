---
phase: 04-regression-net-and-check-gate
plan: 01
subsystem: testing
tags: [testthat, R, regression-net, degenerate-input, contract, NEWS]

requires:
  - phase: 01-contract-foundation
    provides: degenerate-input contract (.handle_degenerate, .resolve_degenerate_mode, ParameterSet)
  - phase: 02-model-sweep
    provides: all 14 models migrated onto degenerate contract
  - phase: 03-pipeline-hardening
    provides: pipeline/stat/external guards (PIPELINE, STATS, EXTERNAL fixes)

provides:
  - 25-row table-driven contract-matrix test (test_contract_matrix.R) covering 14 models + 10 stats + 1 pipeline
  - Exhaustiveness assertion (length==25, sub-counts 14/10/1, stat reconciliation 10+2=12)
  - PermutationTest/RankTest documented exclusions (code comment + machine-readable vector)
  - NEWS.md fix→test catalog mapping every milestone fix to a named locking test

affects: [04-02-check-gate, future milestone planning]

actuals:
  tokens: 26000
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Table-driven test registry: list of named lists {label, kind, make/data or make_stat/stat_col/stat_data or make_task} iterated with plain for loop so label appears in failure output"
    - "Degenerate-input selection per stat: sigma==0 for ARTTest/CARTTest/BHARTTest; n_events==1 for PatellZTest/SignTest/BMPTest/CSectTTest/KolariPynnonenTest; p_hat boundary for GeneralizedSignTest; 1-row event window for CalendarTimePortfolioTest"

key-files:
  created:
    - tests/testthat/test_contract_matrix.R
  modified:
    - NEWS.md

key-decisions:
  - "Contract matrix uses exactly 25 rows (not approximate) — exhaustiveness test asserts this explicitly to make row additions/removals immediately visible"
  - "Stat rows use lenient-only assertions (NA-safety); no strict error contract for stats — only model.fit() and prepare_event_study() have a strict mode"
  - "MarketAdjustedModel degenerate trigger: insufficient obs (not zero-variance) — zero-variance guard was removed in CR-01 (WR-04 fix)"
  - "GeneralizedSignTest degenerate: all-positive ARs (p_hat=1, denom=0→NA) not n_events==1 (which produces finite values due to estimation-window p_hat estimation)"
  - "CalendarTimePortfolioTest degenerate: 1-row event window (sd of single value is NA, so caltime_t→NA); uses caltime_t column not ctp_t"
  - "GARCH/DCCGARCHModel rows use skip_if_not_installed('rugarch'/'rmgarch') — optional packages; skip cleanly when absent"
  - "PermutationTest/RankTest excluded: not migrated onto .handle_degenerate() — resampling/rank tests with inherent degenerate arithmetic; covered by existing test files"

requirements-completed: [TEST-01, TEST-02]

coverage:
  - id: D1
    description: "test_contract_matrix.R with 25-row registry iterating all models/stats/pipeline in strict+lenient modes"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "tests/testthat/test_contract_matrix.R#contract-matrix registry is exhaustive"
        status: pass
      - kind: unit
        ref: "Rscript -e 'devtools::load_all(\".\"); df <- as.data.frame(testthat::test_file(\"tests/testthat/test_contract_matrix.R\", reporter=\"silent\")); stopifnot(sum(df$failed)==0)'"
        status: pass
    human_judgment: false
  - id: D2
    description: "PermutationTest/RankTest documented exclusions (code comment + contract_matrix_excluded vector)"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "tests/testthat/test_contract_matrix.R#contract-matrix registry is exhaustive (exclusion assertions)"
        status: pass
    human_judgment: false
  - id: D3
    description: "NEWS.md fix→test catalog covering every milestone fix with named test file + test_that label"
    requirement: TEST-01
    verification:
      - kind: automated_ui
        ref: "Rscript -e 'nz <- readLines(\"NEWS.md\"); stopifnot(any(grepl(\"Regression Catalog\", nz)), sum(grepl(\"test_[a-z_]+\\.R\", nz)) >= 6)'"
        status: pass
    human_judgment: false
  - id: D4
    description: "Full test suite stays green (1431 tests, 0 failures after additions)"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "Rscript -e 'df <- as.data.frame(testthat::test_dir(\"tests/testthat\", reporter=\"silent\")); stopifnot(sum(df$failed)==0)'"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-09-02
status: complete
---

# Phase 4 Plan 01: Regression Net Summary

**25-component table-driven contract matrix (test_contract_matrix.R) and complete fix→test catalog in NEWS.md lock all Phases 1-3 degenerate-input hardening against regression**

## Performance

- **Duration:** 8 min
- **Started:** 2026-09-02T13:59:26Z
- **Completed:** 2026-09-02T14:07:35Z
- **Tasks:** 3
- **Files modified:** 2 (test_contract_matrix.R created, NEWS.md updated)

## Accomplishments

- Created `tests/testthat/test_contract_matrix.R` with a 25-row table-driven registry covering 14 return models, 10 contract-covered test statistics, and 1 pipeline path — each iterated in strict and lenient modes on at least one degenerate input
- Exhaustiveness `test_that` asserts `length(contract_matrix_components) == 25L`, sub-counts 14/10/1, and that `covered_stats + excluded == 12` (all concrete stat classes accounted for)
- PermutationTest/RankTest documented as excluded (code comment explaining rationale + machine-readable `contract_matrix_excluded` vector)
- GARCH/DCCGARCHModel rows skip cleanly via `skip_if_not_installed("rugarch"/"rmgarch")` when optional packages are absent
- Updated NEWS.md with EventStudy 0.50.0 section containing a "Robustness Hardening — Regression Catalog" subsection mapping 20+ named fixes to their specific `test_that` labels across 11 test files
- Full test suite stays green: 1431 tests, 0 failures

## Component Registry Contents

| Kind | Count | Components |
|------|-------|------------|
| model | 14 | MarketModel, MarketAdjustedModel, ComparisonPeriodMeanAdjustedModel, CustomModel, LinearFactorModel, FamaFrench3FactorModel, FamaFrench5FactorModel, Carhart4FactorModel, BHARModel, VolumeModel, VolatilityModel, RollingWindowModel, GARCHModel, DCCGARCHModel |
| stat | 10 | ARTTest, CARTTest, BHARTTest, CSectTTest, PatellZTest, BMPTest, KolariPynnonenTest, SignTest, GeneralizedSignTest, CalendarTimePortfolioTest |
| pipeline | 1 | prepare_event_study_missing_date (PIPELINE-01) |
| **excluded** | **2** | PermutationTest, RankTest |

## Task Commits

1. **Task 1 (tracer) + Task 2 (expand): contract-matrix skeleton and full 25-row registry** - `8802c5f` (feat)
2. **Task 3: NEWS.md fix→test catalog** - `fd3aab7` (feat)

## Files Created/Modified

- `tests/testthat/test_contract_matrix.R` — Table-driven contract matrix with 25-row registry, strict/lenient drivers, exhaustiveness assertion
- `NEWS.md` — Added EventStudy 0.50.0 section with Robustness Hardening Regression Catalog (11 test files cited, 29 test_that labels)

## Decisions Made

- Registry uses a plain `for` loop (not `purrr::map`) so failure output shows the offending `entry$label` directly
- Stat rows assert lenient NA-safety only — strict mode was not shipped for stats (no `.handle_degenerate()` call in stat R6 classes)
- Degenerate inputs are component-specific: sigma==0 for single-event stats, n_events==1 for PatellZTest/SignTest/BMPTest/CSectTTest, p_hat boundary for GeneralizedSignTest, 1-row event window for CalendarTimePortfolioTest
- Task 1 and Task 2 were written as a single commit (full 25-row registry built upfront) because the registry structure was uniform and pre-expanding to 25 rows was cleaner than building 14 rows and then immediately adding 11 more

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MarketAdjustedModel data factory corrected to insufficient-obs**
- **Found during:** Task 1/2 (registry construction)
- **Issue:** Plan suggested zero-variance as a degenerate factory for MarketAdjustedModel; however, CR-01 (Phase 3) removed the zero-variance guard from MarketAdjustedModel (it was a false-positive guard). The model correctly errors on insufficient obs.
- **Fix:** Changed MarketAdjustedModel registry entry to use `create_degenerate_model_data_insufficient(n_valid=1)`.
- **Files modified:** tests/testthat/test_contract_matrix.R
- **Verification:** 3 strict + 5 lenient assertions pass for MarketAdjustedModel row.
- **Committed in:** 8802c5f

**2. [Rule 1 - Bug] GeneralizedSignTest degenerate input corrected (p_hat boundary)**
- **Found during:** Task 2 (stat row construction)
- **Issue:** Plan assumed GeneralizedSignTest produces NA on n_events==1 (matching SignTest), but it uses estimation-window p_hat averaging that yields finite values for single events with mixed-sign ARs.
- **Fix:** Changed stat_data factory to use all-positive ARs (p_hat=1, denom=sqrt(n*1*0)=0 → NA).
- **Files modified:** tests/testthat/test_contract_matrix.R
- **Verification:** `all(is.na(result$gsign_z)) == TRUE`.
- **Committed in:** 8802c5f

**3. [Rule 1 - Bug] CalendarTimePortfolioTest column name and degenerate input corrected**
- **Found during:** Task 2 (stat row construction)
- **Issue:** Plan referenced `ctp_t` column; actual column is `caltime_t`. Also, single event_id with 5 event-window days produces finite caltime_t values (sd across days is non-NA). Need exactly 1 event-window row to make sd(AAR)=NA.
- **Fix:** Changed stat_col to `"caltime_t"` and stat_data to a single event-window-day tibble.
- **Files modified:** tests/testthat/test_contract_matrix.R
- **Verification:** `all(is.na(result$caltime_t)) == TRUE`.
- **Committed in:** 8802c5f

---

**Total deviations:** 3 auto-fixed (Rule 1 bugs — incorrect degenerate-input assumptions in the plan)
**Impact on plan:** All three fixes were necessary for correct test assertions. No scope creep; tests pass the correct contract for each component.

## Issues Encountered

None — once degenerate inputs were corrected per component behavior, all assertions passed on the first run.

## Self-Check: PASSED

- `[ -f tests/testthat/test_contract_matrix.R ]` → FOUND
- `[ -f NEWS.md ]` with "Regression Catalog" heading → FOUND
- `git log --oneline | grep "8802c5f"` → FOUND
- `git log --oneline | grep "fd3aab7"` → FOUND
- Full suite: 1431 tests, 0 failures → VERIFIED

## Next Phase Readiness

- Ready for `04-02` (Check Gate): the contract matrix and NEWS.md catalog provide the regression net that the check gate verifies
- All 25 components covered; GARCH/DCC rows will run when rugarch is available in the CI environment

---
*Phase: 04-regression-net-and-check-gate*
*Completed: 2026-09-02*
