# Phase 4: Regression Net and Check Gate - Context

**Gathered:** 2026-09-02
**Status:** Ready for planning

<domain>
## Phase Boundary

The final acceptance gate. Lock every fix from Phases 1-3 with a regression test, exercise the degenerate-input contract across all covered components in both strict and lenient mode via a contract matrix, keep the full suite green, and confirm `R CMD check` introduces no new NOTEs/WARNINGs vs the pre-milestone baseline.

In scope: a parametrized contract-matrix test file; a fix→test catalog (NEWS.md); running `R CMD check` and asserting no new NOTEs/WARNINGs; fixing anything the check surfaces (docs/NAMESPACE/Rd, undeclared globals, examples). This is a testing/acceptance phase — no new package logic.

Out of scope: new features/models/statistics; native reimplementation; performance. Any behavioral fix beyond what the check surfaces belongs to the earlier phases (already done).

Depends on: Phases 1-3 (all merged, suite at 1291 pass / 0 fail).
</domain>

<decisions>
## Implementation Decisions

### Contract Matrix (TEST-02)
- One parametrized `tests/testthat/test_contract_matrix.R` that iterates over **each covered component × {strict, lenient} × at least one degenerate input** and asserts the contract:
  - strict → error whose message contains the offending event_id/firm_symbol (and component name);
  - lenient → `is_fitted = FALSE` (models) or NA statistic (stats), NA downstream, and no Inf/NaN leakage, with the one-warning invariant where applicable.
- Covered components = the 13 return models + the single/multi-event test statistics migrated in Phases 1-2, plus the pipeline degradation paths (missing date) from Phase 3 where mode-honoring applies. Use `skip_if_not_installed()` for GARCH/DCC (rugarch/rmgarch).

### Regression-Test Catalog (TEST-01)
- Every fix made this milestone must have a named, findable regression test. Most already exist (added in the Phase 1-3 execution + review-fix rounds). Produce a catalog in **NEWS.md** (and/or a short doc) mapping each milestone fix — the review findings (CR-01/02, WR-01..05, IN-01..03), the GH-#7-class join fix verification, the per-model migrations, the pipeline/external wraps — to the test that locks it. Fill any gap where a fix lacks a dedicated named test.

### R CMD Check Gate (TEST-04)
- Run `R CMD check` (via `devtools::check()` or `R CMD check` on the built tarball). Record the **pre-milestone baseline** NOTEs/WARNINGs (optional-package Suggests NOTEs, any pre-existing ones) and assert **no NEW** NOTEs/WARNINGs are introduced by this milestone — NOT absolute zero. Address any new ones the milestone caused (e.g. undeclared globals from new NSE columns, missing Rd for new exports, `Suggests` for `withr`/`quadprog`/`callr` usage in tests).
- `TEST-03`: the full existing suite (1291+ tests) stays green.

### Plan Grouping
- 2 plans:
  1. **Contract matrix + regression-test catalog** (TEST-01, TEST-02) — write test_contract_matrix.R, audit fix→test coverage, update NEWS.md.
  2. **Check gate** (TEST-03, TEST-04) — run devtools::document() + R CMD check, capture baseline, fix new NOTEs/WARNINGs, confirm green suite.

</decisions>

<code_context>
## Existing Code Insights

- `tests/testthat/test_contract.R` already exists (Phase 1 contract tests) — the matrix EXTENDS coverage to all components, it does not replace it.
- Phases 1-3 added many named regression tests: `test_contract.R`, per-model baselines (`fixtures/contract05_*.rds`), `test_ar_car_test_statistics.R`, `test_multi_event_statistics.R` STATS-02/03/04 tests, `test_prepare.R`, `test_export.R`, `test_cross_sectional.R`, `test_panel.R`, `test_synthetic_control.R`, and the review-fix regression tests (CR-01/02, WR-01/02, etc.).
- Package uses roxygen2 → `devtools::document()` regenerates NAMESPACE/Rd. `EventStudy-package.R` holds `globalVariables()` for NSE columns — new columns introduced this milestone (e.g. any new derived columns) may need adding to avoid check NOTEs.
- `DESCRIPTION` Suggests already gained `withr` (Phase 1). Confirm `quadprog` (synthetic control), `callr` (optional DIDmultiplegt probe — used only via requireNamespace, may not need a Suggests entry), and any test-only packages are correctly declared.
- ~29 fix/feat commits since the pre-milestone baseline (63d67a1) are the catalog candidates.

</code_context>

<specifics>
## Specific Ideas

- The contract matrix should be table-driven (a list of component constructors + their degenerate-data factory) so adding a component later is one row.
- NEWS.md catalog entries should name the test file + test_that label so a reader can find the lock for each fix.
- If `R CMD check` cannot run in this environment, capture the exact reason and fall back to `devtools::check(document=TRUE)` or at minimum `devtools::document()` + a manual NOTE audit — do not fabricate a clean check.
</specifics>

<deferred>
## Deferred Ideas

- None — this is the final milestone phase. Anything surfaced beyond the acceptance bar that is a genuine new concern goes to the milestone audit / a future milestone.
</deferred>
