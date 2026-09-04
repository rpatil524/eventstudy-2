---
phase: 08-agent-skill-waitlist-green-check-gate
reviewed: 2026-09-04T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - R/advisor_pro.R
  - R/advise.R
  - R/advise_offline.R
  - tests/testthat/test_advisor_pro_footer.R
  - DESCRIPTION
  - NEWS.md
  - .Rbuildignore
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: clean
---

# Phase 08: Code Review Report

**Reviewed:** 2026-09-04
**Depth:** standard
**Files Reviewed:** 7
**Status:** clean

## REVIEW: clean

## Summary

Phase 8 adds three things: (1) `.advisor_pro_footer()` — a purely presentational opt-in footer helper; (2) one-line hooks in `print.Advice` and `print.es_advice`; (3) a 179-line regression test suite. DESCRIPTION is bumped to 0.60.0 and `.Rbuildignore` gains `.planning` / `.gsd` exclusions. The Agent Skill markdown lives under `.claude/skills/` which is already in `.Rbuildignore`.

All five review priorities check out:

**No-phone-home (BIZ-02/CRAN):** `.advisor_pro_footer()` calls only `cat()`, `getOption()`, and `invisible()`. No `url()`, `download.file()`, `httr2`, `curl`, `readLines`, `open()`, `socketConnection()`, or any other network primitive is present in the function body. The test suite includes both a static deparse-scan (pattern list) and an httr2 mock guard. Confirmed zero network surface.

**Default-path unchanged (CRAN-05):** The gate is `isTRUE(getOption("eventstudy.advisor_pro_footer", default = FALSE))`. When the option is unset, `getOption()` returns `NULL`; `isTRUE(NULL)` is `FALSE`; the function returns `invisible(NULL)` immediately — no output, no side-effects. The `invisible(x)` return of each print method is untouched: the hook is inserted before `invisible(x)`, not replacing it.

**Option-gate correctness:** `isTRUE()` is the correct idiom — it rejects `NA`, `1L`, `"true"`, and all non-`TRUE` scalars silently. No partial-match risk; the full option name `"eventstudy.advisor_pro_footer"` is used at every call site. `default = FALSE` in `getOption()` is correct (not `default = NULL` which would still propagate to `isTRUE`).

**CRAN doc hygiene:** `@name advisor_pro` + `@keywords internal` + `NULL` is the standard roxygen pattern for a topic-only doc page with no export. `@noRd` on `.advisor_pro_footer` suppresses Rd generation for the helper. `NAMESPACE` has no entry for either symbol. Em-dashes in comments/roxygen (`—`, U+2014) are a package-wide pre-existing convention present in 13+ other R files — not introduced by this diff, and R CMD check passes because they appear in comments and roxygen strings, not in string literals passed to functions.

**Test quality:** The suite is non-tautological. `(a)` default-silent is tested for both `NULL` and `FALSE` option values, for both S3 classes. `(b)` opt-in print is asserted with `length(matches) == 1L` (exact count, not just presence). `(c)` the no-network assertion combines a static body-deparse scan with an httr2 mock guard (skipped when httr2 absent — correct use of `skip_if_not_installed`). `(d)` invisible-return is verified with `capture.output(ret_val <- print(obj))` + `expect_identical` for both option states and both classes.

**.Rbuildignore:** Adding `^\.planning$` and `^\.gsd$` is correct and overdue. Both directories contain only workflow artifacts and must not ship in the CRAN tarball. The `.claude` pattern was already present from a prior commit.

---

## Info

### IN-01: `httr2::with_mocked_responses` API stability

**File:** `tests/testthat/test_advisor_pro_footer.R:140`
**Issue:** `httr2::with_mocked_responses()` is an internal/experimental helper whose signature changed between httr2 0.x and 1.x. The test correctly gates with `skip_if_not_installed("httr2")` but does not guard the httr2 version. If a CRAN check runner has httr2 < 1.0.0 installed, the test will error rather than skip.
**Fix:** Add `skip_if_not_installed("httr2", minimum_version = "1.0.0")` or wrap in `tryCatch` with `skip()`. Low urgency — `skip_if_not_installed` already prevents the failure on machines without httr2 entirely; only affects environments that have an old httr2.

### IN-02: Static network pattern list is not exhaustive

**File:** `tests/testthat/test_advisor_pro_footer.R:107-117`
**Issue:** The deparse-scan checks 10 specific function names. This is a useful belt-and-suspenders check but is not a guarantee — a future edit could introduce `connections::connect()` or `RCurl::getURL()` without tripping the guard. This is by design (static analysis of a static function), but a code comment noting the list is illustrative rather than exhaustive would prevent false confidence.
**Fix:** Add inline comment: `# Pattern list is illustrative; authoritative guarantee is the httr2 mock guard below.`

---

_Reviewed: 2026-09-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
