# Roadmap: EventStudy — Robustness Hardening

## Overview

This milestone converts the EventStudy package from reactive edge-case whack-a-mole into a package with a defined, uniform degenerate-input contract enforced across every component. The work proceeds in four coarse phases: define the contract and prove it on a reference component, sweep it across all return models and test statistics, harden the pipeline and external-package boundaries, then lock everything with a regression net and a green R CMD check.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Contract Foundation** - Define the degenerate-input contract and configurable strict/lenient mode; prove it on a reference model (completed 2026-09-02)
- [ ] **Phase 2: Model and Stats Sweep** - Apply the contract uniformly across all 13 return models and all test statistics
- [ ] **Phase 3: Pipeline and External Hardening** - Harden prepare/export paths and defensively wrap all external-package-bound areas
- [ ] **Phase 4: Regression Net and Check Gate** - Write regression tests per fix, contract test matrix, verify R CMD check clean

## Phase Details

### Phase 1: Contract Foundation

**Goal**: A documented, configurable degenerate-input contract exists and is provably enforced on at least one reference component so that downstream phases have a concrete pattern to follow
**Depends on**: Nothing (first phase)
**Requirements**: CONTRACT-01, CONTRACT-02, CONTRACT-03, CONTRACT-04, CONTRACT-05
**Success Criteria** (what must be TRUE):

  1. A prose contract document (or roxygen section) defines the package's expected behavior for insufficient observations, zero variance, single-event groups, and NA propagation, and is findable in the package docs
  2. Running any covered component in strict mode on a zero-variance or insufficient-observation input raises an error whose message contains the offending event_id or firm_symbol
  3. Running the same component in lenient mode on the same input sets is_fitted = FALSE, returns NA for all downstream statistics, and emits exactly one warning — no duplicate warnings per event
  4. Switching between strict and lenient mode via ParameterSet field (or package option) works without reloading the package
  5. A valid (non-degenerate) input through the same reference component produces identical numerical output before and after the contract implementation

**Plans**: 2/2 plans complete

- [x] 01-01-PLAN.md — Implement contract (R/contract.R doc+helpers, ParameterSet field, execute.R threading, MarketModel refactor)
- [x] 01-02-PLAN.md — Verification net (contract test suite, degenerate factories, docs/NAMESPACE regen, full suite green)

### Phase 2: Model and Stats Sweep

**Goal**: Every return model and every test statistic uniformly follows the Phase 1 contract — no component is left emitting Inf/NaN silently or crashing on degenerate input
**Depends on**: Phase 1
**Requirements**: MODELS-01, MODELS-02, MODELS-03, MODELS-04, STATS-01, STATS-02, STATS-03, STATS-04
**Success Criteria** (what must be TRUE):

  1. Passing a zero-variance estimation window to any of the 13 return models (MarketModel, MarketAdjusted, ComparisonPeriodMean, FF3, FF5, Carhart4, BHAR, Volume, Volatility, RollingWindow, GARCH, DCC-GARCH, Custom) in lenient mode returns NA for all statistics rather than Inf or NaN
  2. Passing fewer than 2 estimation observations to any return model follows the contract (error in strict, is_fitted = FALSE in lenient) rather than crashing with an uninformative R error
  3. Degree-of-freedom counts reported by every model reflect only finite residuals — a model fit on a window containing NA rows reports the correct lower df, not the total row count
  4. Running multi-event statistics (Patell Z, BMP, KP) on a dataset where a firm appears in more than one event produces correct denominators and counts — no many-to-many inflation of test statistics
  5. CAR/CAAR chains computed by CSectTTest and export methods tolerate a firm dropping out mid-window (its NA gap does not silently corrupt subsequent cumulative values for that firm)

**Plans**: TBD

### Phase 3: Pipeline and External Hardening

**Goal**: The preparation, windowing, export, and external-package-bound areas degrade predictably — missing dates, empty windows, collinear regressors, and upstream package failures all produce informative messages rather than uninformative crashes or silent wrong results
**Depends on**: Phase 2
**Requirements**: PIPELINE-01, PIPELINE-02, PIPELINE-03, EXTERNAL-01, EXTERNAL-02, EXTERNAL-03, EXTERNAL-04
**Success Criteria** (what must be TRUE):

  1. Passing an event date that does not exist in the stock data through prepare_event_study() produces a clear warning naming the missing event rather than an uninformative R error or a silently empty result
  2. Calling export_results() or tidy() on a task that contains NA abnormal returns produces a valid output (NAs rendered as NA/blank, not a crash from an if() on NA)
  3. Calling cross_sectional_regression() with a collinear firm-characteristic matrix returns NA coefficients with a warning rather than crashing with a singular matrix error
  4. Calling estimate_panel_event_study() with method = 'de_chaisemartin_dhaultfoeuille' on a platform where DIDmultiplegt is absent or prone to segfault emits a clear warning and returns NULL rather than crashing the R session
  5. Using any optional package (sandwich, rugarch, did) when it is not installed produces a named warning describing the capability lost, not a silent fallback to a different (non-robust) method

**Plans**: TBD

### Phase 4: Regression Net and Check Gate

**Goal**: Every fix made in Phases 1-3 is locked by a failing-before/passing-after regression test; degenerate-input behavior across all covered components in both modes is tested in a contract matrix; and R CMD check passes with no new NOTEs or WARNINGs
**Depends on**: Phase 3
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04
**Success Criteria** (what must be TRUE):

  1. Each bug fixed during this milestone has a named regression test in test_edge_cases.R (or a dedicated test file) that is documented as testing that specific fix — no fix exists without a test
  2. A contract test matrix file (e.g., test_contract_matrix.R) exercises every covered component in both strict and lenient mode with at least one degenerate input, and all assertions pass
  3. Running devtools::test() (or testthat::test_dir()) on the full suite passes all 400+ pre-existing tests with no regressions
  4. Running R CMD check produces no new NOTEs or WARNINGs compared to the pre-milestone baseline — the CRAN submission bar is met

**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Contract Foundation | 2/2 | Complete    | 2026-09-02 |
| 2. Model and Stats Sweep | 0/TBD | Not started | - |
| 3. Pipeline and External Hardening | 0/TBD | Not started | - |
| 4. Regression Net and Check Gate | 0/TBD | Not started | - |
