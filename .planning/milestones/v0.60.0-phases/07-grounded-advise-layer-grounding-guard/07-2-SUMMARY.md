---
phase: 07-grounded-advise-layer-grounding-guard
plan: 2
subsystem: report-integration
status: complete
tags: [advice, generate_report, rmarkdown, backward-compat, ADV-07]
completed: 2026-09-04

dependency_graph:
  requires:
    - 07-1  # es_advise() + Advice S3 + print.Advice + .validate_grounding
  provides:
    - generate_report(advice=NULL) trailing param wired to skeleton.Rmd guarded chunk
    - test_report_advice.R: backward-compat + degrade + render integration tests
  affects:
    - R/report.R
    - inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd
    - man/generate_report.Rd
    - tests/testthat/test_report_advice.R

tech_stack:
  patterns:
    - Guarded eval= rmarkdown chunk (eval=!is.null(params$advice) && inherits(...,"Advice"))
    - Non-Advice degrade: one warning(call.=FALSE) + coerce to NULL + report proceeds
    - Trailing optional param before ... — zero positional-arg breakage

key_files:
  modified:
    - R/report.R
    - inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd
    - man/generate_report.Rd
  created:
    - tests/testthat/test_report_advice.R

decisions:
  - "advice param positioned after interactive and before ... — unaffected by positional callers"
  - "Validation block placed before rmarkdown::render so advice is coerced before params list is built"
  - "skeleton.Rmd eval= double-guards (is.null + inherits) ensure NULL path is byte-identical even if a non-Advice slips through"
  - "Structural skeleton.Rmd tests (no render required) are deterministic and fast; full render tests behind skip_on_cran()"

metrics:
  duration_minutes: 4
  tasks_completed: 2
  tasks_total: 2
  commits: 2
  files_modified: 3
  files_created: 1
  test_pass_before: 1803
  test_pass_after: 1883
  test_fail: 0

actuals:
  tokens: 8500
  tasks: 2
  commits: 2
---

# Phase 07 Plan 2: generate_report Advice Integration Summary

**One-liner:** Wire grounded `Advice` object into `generate_report()` via trailing `advice=NULL` param and guarded skeleton.Rmd chunk — NULL path is byte-identical, invalid advice degrades with one warning.

## What Was Built

### Task 1: advice=NULL param + guarded skeleton.Rmd section

**R/report.R changes:**
- Added `advice = NULL` as a trailing param before `...` (after `interactive`), with full `@param advice` roxygen documentation explaining the NULL default, the valid Advice path, and the degrade behavior.
- Added a validation block immediately before `rmarkdown::render()`: `if (!is.null(advice) && !inherits(advice, "Advice")) { warning(..., call.=FALSE); advice <- NULL }` — exactly one warning, coerce to NULL, never stops.
- Added `advice = advice` to the `params = list(...)` passed to `rmarkdown::render()`.

**inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd changes:**
- Added `advice: NULL` to the YAML `params:` block.
- Added a new `advice-section` chunk with `eval=!is.null(params$advice) && inherits(params$advice, "Advice")` guard, placed before the existing `appendix-section` chunk.
- The chunk renders: "## AI Advisor Interpretation" heading, source/deterministic metadata line, Interpretation subsection (when non-empty), Recommendations loop (action/rationale/expected_effect), Caveats loop.
- Double-guarded: both `is.null()` and `inherits()` must be true for the chunk to execute — NULL advice means `eval=FALSE`, giving byte-identical output.

**man/generate_report.Rd:** Regenerated via `devtools::document()` to include the new `@param advice` documentation.

### Task 2: Backward-compat + degrade + render integration tests

**tests/testthat/test_report_advice.R** (235 lines, 6 test groups):
1. **Formals inspection** — `advice` is trailing, defaults NULL, appears after `interactive` and before `...`; all pre-existing params still present.
2. **Degrade: non-Advice list** — `expect_warning(..., "not an Advice object")` passes; report still generated.
3. **Degrade: non-list (integer)** — same warning, no crash.
4. **Structural skeleton.Rmd assertions** — `readLines()` checks for `advice-section` chunk, `is.null(params$advice)` guard, `inherits(params$advice` guard, `advice: NULL` param, chunk order (advice before appendix). Deterministic, no render required.
5. **NULL advice render** — full HTML render confirms "AI Advisor Interpretation" is absent (behind `skip_on_cran()`).
6. **Grounded Advice render** — `CustomProvider` + `.make_test_diag()` from 07-1 fixtures produces a grounded `Advice`; full HTML render confirms "AI Advisor Interpretation" is present (behind `skip_on_cran()`).

## Verification Results

```
Rscript -e 'devtools::load_all("."); f <- formals(generate_report); stopifnot("advice" %in% names(f), is.null(f$advice)); cat("advice trailing param OK\n")'
# Output: advice trailing param OK
```

Full suite: **1883 pass / 0 fail** (was 1803 after 07-1 — 80 new tests across plans)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] grepl fixed=TRUE for literal $ in test patterns**
- **Found during:** Task 2 (first test run)
- **Issue:** `grepl("is.null(params\\$advice)", lines)` used regex mode; `$` is a regex anchor not a literal dollar sign — pattern never matched even though the skeleton was correct.
- **Fix:** Changed to `grepl("is.null(params$advice)", lines, fixed = TRUE)` and `grepl('inherits(params$advice', lines, fixed = TRUE)`.
- **Files modified:** `tests/testthat/test_report_advice.R`
- **Commit:** ba80524 (included in the same task commit after fix)

## Known Stubs

None — the advice section renders all fields from the Advice object; no hardcoded placeholders.

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| T-07-05 mitigated | R/report.R | validation block coerces non-Advice to NULL + one warning — covered |
| T-07-06 mitigated | skeleton.Rmd | `%||%` fallbacks + `length()` guards on all advice fields in chunk — covered |

No new unmitigated threat surface introduced.

## Self-Check: PASSED

- [x] R/report.R — advice param present, validation block present, params list updated
- [x] skeleton.Rmd — advice: NULL in params block, advice-section chunk before appendix
- [x] man/generate_report.Rd — regenerated
- [x] tests/testthat/test_report_advice.R — 23 pass / 0 fail (non-CRAN)
- [x] Commits: e9de041 (feat), ba80524 (test) — both verified in git log
- [x] Full suite: 1883 pass / 0 fail
