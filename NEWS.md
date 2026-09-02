# EventStudy 0.50.0

## Robustness Hardening — Regression Catalog

This release hardens the package against degenerate, boundary, and adversarial
inputs (Phase 1–3). Every fix below is locked by a named test that will catch
a regression. The cross-component degenerate-input regression net is provided
by `tests/testthat/test_contract_matrix.R` (TEST-02, see final entry).

### Contract Foundation (Phase 1 — CONTRACT-01..05)

* **CONTRACT-01/02: Degenerate-input contract defined in `R/contract.R`**
  (`.handle_degenerate()`, `.resolve_degenerate_mode()`; ParameterSet
  `degenerate_handling` field; package option `EventStudy.degenerate_handling`).
  — Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-02: ParameterSet default resolves to lenient")` and
  `test_that("CONTRACT-02: ParameterSet strict field resolves to strict")`.

* **CONTRACT-03: Strict mode raises descriptive `stop()` naming event_id,
  firm_symbol, and component on degenerate input (MarketModel).** —
  Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-03: strict mode errors on insufficient obs — names event_id, firm_symbol, MarketModel")`.

* **CONTRACT-04: Lenient mode sets `is_fitted = FALSE`, emits exactly one
  warning per `(event_id, firm_symbol)`, propagates NA through abnormal_returns,
  and the pipeline emits exactly one warning per degenerate event.** —
  Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-04: lenient mode on insufficient obs sets is_fitted FALSE + exactly 1 warning")`
  and `test_that("CONTRACT-04 (pipeline): run_event_study emits exactly ONE warning per degenerate (event_id, firm_symbol)")`.

* **CONTRACT-05: Valid-input MarketModel statistics are byte-stable (baseline
  fixture).** —
  Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-05: valid-input MarketModel statistics match committed baseline within 1e-8")`.

### Model Migrations (Phase 1–2 — per-model contract enforcement)

* **MarketModel migrated onto `.handle_degenerate()`** (insufficient obs /
  zero-variance index guards). —
  Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-03: strict mode errors on insufficient obs — names event_id, firm_symbol, MarketModel")`.

* **MarketAdjustedModel, ComparisonPeriodMeanAdjustedModel, CustomModel,
  BHARModel, VolumeModel, VolatilityModel migrated** (each has insufficient-obs
  and/or zero-variance guard). —
  Locked by `tests/testthat/test_models.R` ::
  `test_that("VolatilityModel: insufficient obs raises contract error in strict mode")`
  and `test_that("CustomModel: degenerate input — abnormal_returns returns NA without calling predict(NULL)")`.

* **LinearFactorModel, FamaFrench3FactorModel, FamaFrench5FactorModel,
  Carhart4FactorModel migrated** (insufficient obs / zero-variance guards for
  excess_return / factor columns). —
  Locked by `tests/testthat/test_models.R` ::
  `test_that("All four factor models: fit+abnormal_returns emits exactly one warning on degenerate input")`.

* **Per-model CONTRACT-05 baseline fixtures** (MarketAdjusted, CompPeriodMean,
  Custom, BHARModel, VolumeModel, VolatilityModel, FF3, FF5, Carhart4). —
  Locked by `tests/testthat/test_models.R` ::
  `test_that("MarketAdjustedModel: valid-input baseline invariance (CONTRACT-05)")`,
  `test_that("FamaFrench3FactorModel: valid-input baseline invariance (CONTRACT-05)")`,
  etc.

* **RollingWindowModel migrated** (Guard 1: insufficient obs; Guard 2: all-NA
  estimation window; Guard 3: last-window NA params; df reflects finite pair
  count, not nrow — WR-04). —
  Locked by `tests/testthat/test_models_time_varying.R` ::
  `test_that("RollingWindowModel: lenient mode — insufficient obs (Guard 1) — one warning, all-NA ARs")`,
  `test_that("WR-04: RollingWindowModel df reflects finite pair count not nrow (NA-heavy window)")`.

* **GARCHModel migrated** (insufficient obs, zero-variance guards; pre-call guards
  added so `rugarch::ugarchfit()` never receives fewer rows than GARCH order). —
  Locked by `tests/testthat/test_models_time_varying.R` ::
  `test_that("GARCHModel: lenient mode — insufficient obs — one warning, all-NA ARs")`,
  `test_that("GARCHModel: strict mode — insufficient obs — named error")`.

* **DCCGARCHModel migrated** (insufficient obs, zero-variance guards). —
  Locked by `tests/testthat/test_models_time_varying.R` ::
  `test_that("DCCGARCHModel: lenient mode — insufficient obs — one warning, all-NA ARs")`.

* **GARCHModel / DCCGARCHModel `calculate_statistics()` failure wrapping**
  (EXTERNAL-04: `tryCatch` resets `is_fitted = FALSE`, emits named warning,
  returns NA ARs when rugarch fitting fails). —
  Locked by `tests/testthat/test_models_time_varying.R` ::
  `test_that("GARCHModel: calculate_statistics failure resets is_fitted=FALSE + named warning + NA ARs")`,
  `test_that("DCCGARCHModel: calculate_statistics failure → exactly ONE warning (fit+abnormal_returns combined)")`.

### Test-Statistic Guards (Phase 2 — STATS-01..04)

* **STATS-01: `ARTTest`, `CARTTest`, `BHARTTest` return NA (not Inf/NaN) when
  `sigma == 0`** (divide-by-zero guard). —
  Locked by `tests/testthat/test_ar_car_test_statistics.R` ::
  `test_that("STATS-01: ARTTest returns NA (not Inf/NaN) when sigma == 0")`,
  `test_that("STATS-01: CARTTest returns NA (not Inf/NaN) in car_t when sigma == 0")`,
  `test_that("STATS-01: BHARTTest returns NA (not Inf/NaN) in bhar_t when sigma == 0")`.

* **STATS-02: `BMPTest`, `KolariPynnonenTest`, `PatellZTest`, `CSectTTest` join
  on `event_id` (not `firm_symbol`) — fixes GH #7 many-to-many inflation.** —
  Locked by `tests/testthat/test_multi_event_statistics.R` ::
  `test_that("BMPTest does not inflate n_events when firms recur (GH #7)")`,
  `test_that("KolariPynnonenTest does not inflate n_events when firms recur (GH #7)")`,
  `test_that("STATS-02: CSectTTest does not inflate n_events when firms recur")`.

* **STATS-04: `PatellZTest`, `SignTest` return NA when `n_events == 1`** (added
  `n_events <= 1` guards; `BMPTest`, `CSectTTest` already returned NA via
  `sd(single_value) = NA`). —
  Locked by `tests/testthat/test_multi_event_statistics.R` ::
  `test_that("STATS-04: PatellZTest aar_z is NA (not finite) when n_events == 1")`,
  `test_that("STATS-04: SignTest sign_z is NA (not finite) when n_events == 1")`.

### Pipeline Hardening (Phase 3 — PIPELINE-01..03)

* **PIPELINE-01: `prepare_event_study()` honours degenerate mode on missing
  event date** — strict errors naming component/event/firm; lenient warns and
  degrades to all-zero windows. —
  Locked by `tests/testthat/test_prepare.R` ::
  `test_that("missing event date strict: stop() names component, event_id, firm_symbol")`,
  `test_that("missing event date lenient: exactly one warning naming event_id and firm_symbol")`.

* **PIPELINE-02: `export_results()` NA-safe CAR cumsum** (reverted false
  coalesce — NA must propagate through cumsum, not be silently replaced with 0;
  CR-01). —
  Locked by `tests/testthat/test_export.R` ::
  `test_that("export_results: CAR — interior NA propagates through cumsum (correct NA behavior)")`,
  `test_that("export_results: NA abnormal_returns in AR column preserved as NA (not 0)")`.

* **PIPELINE-03: `cross_sectional_regression()` singular/collinear guard** —
  returns NA `std.error/statistic/p.value` with one warning instead of crashing;
  `sandwich` absent degrades to OLS SEs with a warning. —
  Locked by `tests/testthat/test_cross_sectional.R` ::
  `test_that("singular design: collinear regressor returns NA std.error/statistic/p.value + one warning")`,
  `test_that("sandwich absent: emits warning() naming robust SEs and OLS fallback")`.

### External-Package Wrapping (Phase 3 — EXTERNAL-01..04)

* **EXTERNAL-01..03: Panel DiD estimators (`callaway_santanna`,
  `dechaisemartin_dhaultfoeuille`, `borusyak_jaravel_spiess`) return `NULL`
  results with a warning when the required package is absent or the estimator
  fails.** —
  Locked by `tests/testthat/test_panel.R` ::
  `test_that("callaway_santanna warns and returns task with NULL results when did is absent")`.

* **EXTERNAL-04: `estimate_synthetic_control()` empty-donor-pool guard** —
  returns `NULL` with a warning instead of crashing when `quadprog::solve.QP`
  or the donor pool is empty. —
  Locked by `tests/testthat/test_synthetic_control.R` ::
  `test_that("estimate_synthetic_control with quadprog produces valid weights")`.

### Review Fix Round (Phase 1–3 — CR/WR/IN)

* **WR-01: `.degenerate_handled = TRUE` set in `calculate_statistics()`
  `tryCatch` path** — ensures GARCH/DCC failure path also honours one-warning
  guarantee (set in the catch block, not lost). —
  Locked by `tests/testthat/test_models_time_varying.R` ::
  `test_that("GARCHModel: calculate_statistics failure → exactly ONE warning (fit+abnormal_returns combined)")`.

* **WR-02: External-package wrapper emits warning when estimator returns NULL
  results** (was silently producing a NULL task). —
  Locked by `tests/testthat/test_panel.R` ::
  `test_that("callaway_santanna warns and returns task with NULL results when did is absent")`.

* **WR-03: ParameterSet stores normalised `match.arg` value** — field now holds
  `"strict"` or `"lenient"` (not raw user input). —
  Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-02: ParameterSet strict field resolves to strict")`.

* **IN-01: Removed redundant `degenerate_mode` / `event_id` / `firm_symbol`
  field re-declarations in `MarketModel`** — fields are defined once on
  `ModelBase`. —
  Locked by `tests/testthat/test_contract.R` (model construction and field
  assignment exercise these fields).

* **IN-02: Standardised package option key to `EventStudy.degenerate_handling`**
  (was inconsistently named in early drafts). —
  Locked by `tests/testthat/test_contract.R` ::
  `test_that("CONTRACT-02: package option overrides default when field is NULL")`.

* **IN-03: `withr` declared in `DESCRIPTION Suggests`** (was missing; tests
  using `withr::with_options` required it). —
  Verified by `R CMD check` and exercised by all `withr::with_options` calls
  in `tests/testthat/test_contract.R`.

* **CR-01: Reverted export `CAR` coalesce** — see PIPELINE-02 above.

* **CR-02: Empty-donor-pool `solve.QP` guard** — see EXTERNAL-04 above.

### Regression Net (Phase 4 — TEST-01/02)

* **TEST-02: `test_contract_matrix.R` — cross-component degenerate-input
  regression net.** Table-driven registry of 25 rows (14 models + 10
  contract-covered test statistics + 1 pipeline path) iterated in strict and
  lenient modes. Locked by `tests/testthat/test_contract_matrix.R` ::
  `test_that("contract-matrix registry is exhaustive")` (asserts `length == 25L`,
  sub-counts 14/10/1, exclusions reconcile to 12 stat classes) and all
  per-component `test_that("contract-matrix [strict] <label> ...")` /
  `test_that("contract-matrix [lenient] <label> ...")` rows.

---

# EventStudy 0.40.0

## Bug Fixes

* `BMPTest`, `KolariPynnonenTest`, and `PatellZTest` joined the per-event
  model (sigma / forecast-error-corrected sigma) on `firm_symbol` instead of
  `event_id`. When a firm appeared in more than one event this produced a
  many-to-many join that duplicated rows, inflating `n_events` and the test
  statistics (`bmp_t`, `kp_t`, `aar_z`). The joins and per-event groupings now
  key on `event_id` (GH #7).

## New Features

* 13 return models: Market Model, Market Adjusted, Comparison Period Mean
  Adjusted, Custom Model, Fama-French 3-Factor, Fama-French 5-Factor,
  Carhart 4-Factor, GARCH, BHAR, Volume, and Volatility models.
* 11 test statistics: AR T-Test, CAR T-Test, BHAR T-Test, Cross-Sectional
  T-Test, Patell Z-Test, Sign Test, Generalized Sign Test, Rank Test,
  BMP Test, and Calendar-Time Portfolio Test.
* Cross-sectional regression of CARs on firm characteristics with
  heteroskedasticity-consistent standard errors.
* Intraday event study support with POSIXct timestamps.
* Panel (DiD) event study module with TWFE and Sun-Abraham estimators,
  including cluster-robust standard errors.
* Export results to CSV, Excel, and LaTeX formats.
* Tidy method for converting results to long-format tibbles.
* Diagnostic tools: model residual plots, estimation window checks.
* 10 vignettes covering introduction, custom models, custom test statistics,
  result extraction, panel event studies, cross-sectional analysis, factor
  models/BHAR, diagnostics, volume/volatility studies, and intraday studies.
