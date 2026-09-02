---
phase: 01-contract-foundation
fixed_at: 2026-09-02T00:00:00Z
review_path: .planning/phases/01-contract-foundation/01-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-09-02
**Source review:** .planning/phases/01-contract-foundation/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (WR-02, WR-03, IN-01, IN-02, IN-03; WR-01 deferred by design)
- Fixed: 5
- Skipped: 0

## Fixed Issues

### WR-02: Double warning from abnormal_returns() after degenerate fit()

**Files modified:** `R/contract.R`, `R/models.R`, `tests/testthat/test_contract.R`
**Commit:** e6e56d9
**Applied fix:**
- Added `$degenerate_handled = FALSE` private field to `ModelBase`'s private list, available to all subclasses via inheritance.
- In `.handle_degenerate()` lenient branch (R/contract.R), set `private_env$.degenerate_handled <- TRUE` after emitting the contract-formatted warning.
- Guarded `MarketModel$abnormal_returns()` with a three-branch check: (1) fitted → compute normally, (2) `degenerate_handled` TRUE → return NA silently (fit() already warned), (3) otherwise → emit "not fitted" warning (preserves legitimate case where fit() was never called).
- Updated the two CONTRACT-04 unit tests to remove `suppressWarnings()` wrappers and instead assert `expect_length(extra_warnings, 0L)` after calling `abnormal_returns()` — this actively catches any regression.
- Strengthened the CONTRACT-04 pipeline test: added a total FIRM_B warning count assertion (`expect_length(firm_b_all_warnings, 1L)`) so the masking comment is replaced by a real regression guard.

### WR-03: match.arg return value discarded in ParameterSet$initialize()

**Files modified:** `R/parameter_set.R`
**Commit:** 3de5685
**Applied fix:** Changed `match.arg(degenerate_handling, c("lenient", "strict"))` to `degenerate_handling <- match.arg(degenerate_handling, c("lenient", "strict"))` so the normalised value (e.g. "strict" from partial match "str") is stored in `self$degenerate_handling` rather than the raw user-supplied string.

### IN-01: degenerate_mode/event_id/firm_symbol re-declared in MarketModel

**Files modified:** `R/models.R`
**Commit:** fd8be30
**Applied fix:** Removed the three redundant field declarations (`degenerate_mode = NULL`, `event_id = NULL`, `firm_symbol = NULL`) and their roxygen `@field` docs from `MarketModel`. Replaced with a single inline comment `# degenerate_mode, event_id, firm_symbol — inherited from ModelBase.` All three fields remain accessible via inheritance; all 39 contract tests and 964 full-suite tests pass.

### IN-02: Package option name uses lowercase eventstudy vs package name EventStudy

**Files modified:** `R/contract.R`, `tests/testthat/test_contract.R`
**Commit:** 8611ede
**Applied fix:** Renamed `eventstudy.degenerate_handling` to `EventStudy.degenerate_handling` in all 7 occurrences: the `getOption()` call in `contract.R`, the roxygen doc example in `contract.R`, and five `withr::with_options()` calls in `test_contract.R`.

### IN-03: withr not declared in DESCRIPTION Suggests

**Files modified:** `DESCRIPTION`
**Commit:** 37c18c0
**Applied fix:** Added `withr,` to `Suggests:` immediately after `testthat (>= 3.0.0),` — logical grouping as a test helper dependency. Follows existing style (bare package name, no version constraint required since withr is pulled in transitively by testthat at any modern version).

## Deferred Issues

### WR-01: Strict mode silently ignored for LinearFactorModel family and other models

**Reason:** Explicitly deferred to Phase 2 (Model and Stats Sweep) per fix_context instructions. No behavioral change made. A one-line comment could be added to ModelBase noting "Phase 2 wires .handle_degenerate() into remaining models" — not added here to avoid scope creep.

---

## Verification

**Tests run in:** isolated git worktree (`gsd-reviewfix/01-1155849`) at
`.claude/worktrees/rf-01-1155849-1788338467` (repo-relative, no `node_modules`).
After fast-forward, the main checkout on `main` carries all fix commits.

**Contract tests (test_contract.R):** FAIL 0 | WARN 0 | SKIP 0 | PASS 39

**Full suite (devtools::test()):** FAIL 0 | WARN 3 | SKIP 9 | PASS 964

The 3 warnings in the full suite are pre-existing (VolatilityModel and
RollingWindowModel "not fitted" warnings from test_edge_cases.R — these are
Phase 2 targets under WR-01 and the tests use `expect_warning()` to assert
them explicitly). The 9 skips are due to optional packages not installed
(tidyquant, rmgarch, did, DIDmultiplegt, didimputation, rmarkdown).

**devtools::document()** ran cleanly. The `degenerate-input-contract.Rd` and
`MarketModel.Rd` pages were regenerated with the corrected option name and
without the redundant `MarketModel` field docs.

---

_Fixed: 2026-09-02_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
