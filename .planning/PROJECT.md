# EventStudy — Robustness Hardening

## What This Is

EventStudy is a comprehensive R package (CRAN) for financial event study analysis. It provides a composable R6 pipeline — `prepare_event_study()` → `fit_model()` → `calculate_statistics()` — with 13+ return models (Market, Fama-French 3/5, Carhart 4, GARCH, DCC-GARCH, Rolling-Window, BHAR, Volume, Volatility, Comparison-Period-Mean, Custom), 8+ test statistics (AR/CAR t-tests, Patell Z, BMP, Sign, Kolari-Pynnönen, Calendar-Time Portfolio, Cross-Sectional t), and specialized task types (panel DiD, intraday, synthetic control), plus bootstrap inference, cross-sectional regression, diagnostics, power simulation, and CSV/Excel/LaTeX export.

This milestone is **robustness hardening** — making the package behave predictably and never silently wrong on degenerate, boundary, and adversarial inputs, and locking that behavior with a durable regression net so the recurring audit-round bug churn stops.

## Core Value

The package must never produce a silently incorrect statistical result. On degenerate input it either errors clearly or returns NA with one warning — but it never returns a plausible-looking wrong number.

## Requirements

### Validated

<!-- Inferred from existing codebase (see .planning/codebase/). These ship today and are relied upon. -->

- ✓ Core pipeline: prepare → fit → calculate_statistics via `run_event_study()` — existing
- ✓ 13+ return models under a common `ModelBase` interface — existing
- ✓ Single-event (AR/CAR) and multi-event (AAR/CAAR, Patell, BMP, Sign, KP, CSect) test statistics — existing
- ✓ Panel DiD estimators (TWFE, Sun-Abraham, Callaway-Sant'Anna, BJS, de Chaisemartin-D'Haultfoeuille) — existing
- ✓ Intraday event studies (POSIXct, minute/second windows) — existing
- ✓ Synthetic control method — existing
- ✓ Bootstrap inference, cross-sectional regression, diagnostics, power simulation — existing
- ✓ CSV/Excel/LaTeX export and broom-compatible tidy() — existing
- ✓ testthat suite (~27 files, 400+ tests) with mock-data helpers and a dedicated `test_edge_cases.R` — existing
- ✓ **Documented degenerate-input contract** (`?degenerate-input-contract`, `R/contract.R`) covering insufficient obs, zero variance, single-event groups, NA propagation — Phase 1 (CONTRACT-01)
- ✓ **Configurable strict vs lenient handling** — `ParameterSet$degenerate_handling` field + `EventStudy.degenerate_handling` option, resolver `.resolve_degenerate_mode()` (default lenient); strict names the offending event_id/firm_symbol, lenient sets `is_fitted=FALSE` + NA + exactly one warning; proven on MarketModel — Phase 1 (CONTRACT-02..05)
- ✓ **Contract applied to every return model** — all 13 models route degenerate conditions through `.handle_degenerate()` with finite-only df; zero-variance guards correctly scoped to OLS/variance-dependent models (arithmetic models MAM/CPM/BHAR treat zero-variance as valid input); GARCH/DCC got pre-call guards — Phase 2 (MODELS-01..04)
- ✓ **Contract applied to every test statistic** — no Inf/NaN leakage (ART/CAR/BHAR sigma==0→NA); event_id joins verified (no many-to-many inflation); NA-safe CAR/CAAR chains; correct single-event denominators (Patell/Sign n_events==1→NA, Q_total excludes degenerate events) — Phase 2 (STATS-01..04)

- ✓ **Hardened prepare/window logic and export/tidy** — mode-honoring missing-date/empty-window (warning names the event; strict errors); export/tidy tolerate NA abnormal returns (NA propagates, not silently zeroed); cross_sectional collinear → NA coefficients + warning — Phase 3 (PIPELINE-01/02/03)
- ✓ **Defensively wrapped external-package areas** — panel DiD (did/DIDmultiplegt/didimputation) absence/failure → warning + NULL (never crashes session); DIDmultiplegt opt-in callr probe (no new hard dep); rugarch/rmgarch post-fit failure → is_fitted FALSE + warning; synthetic-control solve.QP + empty-donor-pool guards — Phase 3 (EXTERNAL-01/02/03/04)

### Active

<!-- This milestone's scope. Hardening the above without changing its statistical intent. -->

- [ ] **Systematic bug sweep of remaining fragile areas** — audit the areas CONCERNS.md flags, fix what's found (largely absorbed by Phases 1-3 review passes)
- [ ] **Regression test for every fix** — each fixed bug gets a test that fails before and passes after
- [ ] **Contract test matrix** — degenerate-input behavior tested across all covered components in both strict and lenient modes
- [ ] **Green `R CMD check`** — no new NOTEs or WARNINGs introduced by this milestone

### Out of Scope

- Native reimplementation of external estimators (did, DIDmultiplegt, rugarch) — this milestone wraps them defensively; a native rewrite is a separate dependency-independence milestone
- Performance/scaling work (streaming, data.table backend, sparse FE, chunked aggregation) — real concern per CONCERNS.md but orthogonal to correctness; deferred
- New models, test statistics, task types, or output formats — hardening only, no feature growth
- Result serialization format (JSON/HDF5) and reproducibility metadata — deferred
- Changing the statistical intent of any existing method — behavior on *valid* input must be unchanged

## Context

- **Mature brownfield package.** Codebase map is complete in `.planning/codebase/`. Written entirely in R 4.1.0+, R6 OOP, tidyverse pipeline. CRAN package (`cran-comments.md`, `NEWS.md` present).
- **This is a recurring pain point, not a one-off.** 14+ prior audit rounds (commits through 63d67a1) collectively fixed 100+ edge-case bugs — insufficient-observation handling, zero-variance Inf/NaN, NA propagation in cumsum, softmax overflow, incorrect df counting, and a many-to-many join that inflated BMP/Patell/KP statistics (GH #7, fixed in 63d67a1). The goal here is to convert this from reactive whack-a-mole into a defined contract + regression net.
- **Known fragile areas (from CONCERNS.md):** multi-event test-statistic joins (`R/multi_event_test_statistics.R`); time-varying model parameter extraction (`R/models_time_varying.R`); panel estimator selection/result extraction (`R/panel_event_study.R`); export/tidy NA guarding (`R/export.R`); synthetic-control numerical stability (`R/synthetic_control.R`).
- **External-package risk:** `did`, `DIDmultiplegt` (macOS arm64 segfaults, API drift), `rugarch` (compilation), `sandwich` (silent fallback to non-robust SEs), `quantmod`/`tidyquant` (no retry/cache). These get defensive wrapping this milestone.
- **Test infrastructure is solid:** testthat edition 3, `helper-mock-data.R` factories, `test_edge_cases.R` conventions already established — regression tests plug into an existing pattern.

## Constraints

- **Tech stack**: R 4.1.0+, R6, testthat 3e — no new language or framework; hardening stays within the existing stack
- **Compatibility**: Behavior on valid inputs must not change — this is correctness/robustness only, not a redesign; existing 400+ tests must stay green
- **CRAN**: No new `R CMD check` NOTEs/WARNINGs; Suggests-vs-Imports boundaries respected (optional packages stay optional, guarded by `requireNamespace()`)
- **External dependencies**: Cannot fix upstream packages (did, DIDmultiplegt, rugarch) — only wrap them so failures degrade gracefully

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Configurable strict vs lenient degenerate-input handling | Serves both fail-fast interactive use and NA-tolerant batch runs across many events | ✓ Phase 1 — ParameterSet field + `EventStudy.degenerate_handling` option, default lenient; proven on MarketModel |
| Mode threaded via model fields set in `.initialize_and_fit_model()` (not a `fit()` arg) | ParameterSet is not reachable inside per-event `fit()`; assigning `degenerate_mode`/`event_id`/`firm_symbol` on the cloned model + `purrr::map(seq_len(nrow()))` avoids an API change and untested NSE | ✓ Phase 1 — pattern for Phase 2 to replicate |
| Zero-variance guard scoped to variance-dependent models only | Arithmetic models (MarketAdjusted/ComparisonPeriodMean/BHAR) produce well-defined abnormal returns on constant-return inputs; a blanket zero-variance guard wrongly returned NA for valid data — the degenerate handling for these lives at the test-statistic layer (sigma==0→NA) | ✓ Phase 2 (review CR-01) |
| Harden everything incl. external-package areas | User wants full coverage; externals get defensive wrapping rather than reimplementation | — Pending |
| Acceptance bar = regression test per fix + contract matrix + green R CMD check | Converts recurring audit churn into a durable net; measurable and CRAN-aligned | — Pending |
| Layer the work: contract → bug sweep → correctness guarantees | Foundation first (uniform policy), then the sweep, then the acceptance bar | — Pending |
| Defer performance/scaling and native reimplementation | Real but orthogonal to correctness; keeps this milestone focused | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-02 after Phase 3*
