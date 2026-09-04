---
phase: 07-grounded-advise-layer-grounding-guard
reviewed: 2026-09-04T00:00:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - R/advise.R
  - R/report.R
  - inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd
  - tests/testthat/test_advise.R
  - tests/testthat/helper-advice-fixtures.R
findings:
  critical: 3
  warning: 2
  info: 1
  total: 6
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-09-04
**Depth:** deep (cross-file call-chain tracing)
**Files Reviewed:** 5
**Status:** issues_found

---

## Summary

The grounded advise engine is architecturally sound. The overall failure-discipline
(exactly-one-warning contract, provider-already-failed silent degrade, jsonlite
requireNamespace guard, backward-compat of `generate_report`) is correctly implemented
on every common path. No API key or credential touches `R/advise.R` at all — the
provider layer correctly keeps secrets in Phase 6. The `.resolve_diag_key` regex is
correct for all valid formats and safely returns `NA_real_` for malformed paths.

Three bugs break the grounding invariant (ADV-04) on adversarial or degenerate inputs.
Two are crashes that violate the "never crash the session" contract; one is a grounding
bypass that directly violates the "never silently wrong" contract.

---

## Critical Issues

### CR-01: Empty `evidence[]` list bypasses the grounding guard entirely — ungrounded recs survive

**File:** `R/advise.R:225-282` (inner `for (ev in ev_list)` loop)

**Issue:** When an LLM returns a recommendation with `evidence: []` (empty array), the
inner evidence loop never executes. `all_good` stays `TRUE`, so the recommendation is
kept unconditionally. An adversarially-crafted or schema-non-conforming LLM response
can therefore embed arbitrary `action`/`rationale` text with zero evidence and pass the
guard untouched. The JSON schema marks `evidence` as a required field but places no
`minItems` constraint, so structured-output providers can legally return `evidence: []`.
This is a direct violation of ADV-04 — the grounding invariant.

**Demonstrated path:**
```json
{"interpretation":"...",
 "recommendations":[{"action":"Fabricated rec","kind":"stat_choice",
   "rationale":"Anything.","expected_effect":"Anything.",
   "evidence":[]}],
 "caveats":[]}
```
→ `length(result$recommendations)` = 1, `n_dropped` = 0, `source = "<provider>"`.
The caller gets back a recommendation with no grounding proof.

**Fix — two-part:**

1. In `.validate_grounding()`, treat an empty evidence list as an immediate drop:
```r
for (rec in recs) {
  ev_list  <- rec$evidence %||% list()
  # A recommendation with no evidence cannot be grounded — drop immediately.
  if (length(ev_list) == 0L) {
    n_drop <- n_drop + 1L
    next
  }
  all_good <- TRUE
  ...
}
```

2. In `.advice_schema()`, add `minItems = 1L` to the evidence array:
```r
evidence = list(
  type     = "array",
  minItems = 1L,
  items    = list(...)
)
```

---

### CR-02: All-NA diagnostic vector produces `NaN` that crashes `.validate_grounding()` with a fatal error

**File:** `R/advise.R:240-264`

**Issue:** The `actual_na` check at line 240 only detects NA for scalars (`length(actual) == 1L && is.na(actual)`). A diagnostic field that is a vector of all NAs (e.g., `estimation_window$shapiro_p = c(NA_real_, NA_real_)`) passes the `actual_na` check as `FALSE` (length > 1). The code then reaches line 252 and computes `mean(c(NA, NA), na.rm = TRUE) = NaN`. NaN then propagates to line 263: `tol = max(1e-6, 1e-4 * abs(NaN)) = NaN`. At line 264, `abs(reported - NaN) > NaN` produces `NA` (not `FALSE`). R's `if(NA)` throws `Error: missing value where TRUE/FALSE needed`, crashing `.validate_grounding()` without any warning, violating the never-crash contract.

**Verified with:**
```r
mean(c(NA_real_, NA_real_), na.rm = TRUE)  # NaN
max(1e-6, 1e-4 * abs(NaN))                 # NaN
if (abs(99.9 - NaN) > NaN) "x"             # Error: missing value where TRUE/FALSE needed
```

This is possible whenever a fitted model fails for all events in an estimation window section, producing all-NA diagnostics. The package already accepts such inputs gracefully in upstream layers.

**Fix:**
```r
# After mean() summarization at line 253:
if (length(actual) > 1L && is.numeric(actual)) {
  actual <- mean(actual, na.rm = TRUE)
}
# Add: treat NaN actual (all-NA input) as absent:
if (is.numeric(actual) && length(actual) == 1L && is.nan(actual)) {
  all_good <- FALSE
  break
}
```

---

### CR-03: `Inf` diagnostic value is a grounding guard false-accept — any reported value passes

**File:** `R/advise.R:263-265`

**Issue:** When a diagnostic field holds `Inf` (e.g., `sigma = Inf` from a zero-variance estimation window, or `dw_stat = Inf`), `actual_na` is `FALSE` (`is.na(Inf)` = `FALSE`). The tolerance calculation at line 263 becomes `max(1e-6, 1e-4 * Inf) = Inf`. Then `abs(reported - Inf) > Inf` is `FALSE` for any finite `reported` value (since `abs(finite - Inf) = Inf`, and `Inf > Inf` = `FALSE`). The guard passes any finite cited value as "matching" an `Inf` actual — a complete bypass for any diagnostic that degenerated to infinity. The LLM can cite any value for such a key and the recommendation survives.

Secondary: when both `actual` and `reported` are `Inf`, `abs(Inf - Inf) = NaN`, and `NaN > Inf` = `NA`, causing the same `if(NA)` crash as CR-02.

**Fix:** Guard against non-finite actuals before entering the tolerance comparison:
```r
if (is.numeric(actual) && is.numeric(reported)) {
  if (length(reported) != 1L) { all_good <- FALSE; break }
  # Non-finite actual cannot be cited meaningfully: drop the rec.
  if (!is.finite(actual)) { all_good <- FALSE; break }
  tol <- max(abs_tol, rel_tol * abs(actual))
  if (abs(reported - actual) > tol) { all_good <- FALSE; break }
}
```

---

## Warnings

### WR-01: `model` parameter is silently ignored — never passed to `provider$complete()`

**File:** `R/advise.R:720, 800`

**Issue:** `es_advise()` accepts a `model = NULL` parameter (documented as "Optional character model identifier; passed through to the provider"), but `provider$complete()` is called at line 800 as `provider$complete(prompt, .advice_schema())` — `model` is never forwarded. A user who passes `model = "gpt-4o"` to override the provider default will get silently ignored behaviour. Depending on the provider layer's API, this may produce wrong-model output with no indication anything differed from the default.

**Fix:**
```r
resp <- tryCatch(
  provider$complete(prompt, .advice_schema(), model = model),
  error = function(e) { ... }
)
```
(Assumes the Phase 6 provider `$complete()` method accepts an optional `model` argument, as implied by the parameter documentation.)

---

### WR-02: `actual_na` detection is incomplete — length > 1 vectors are only partially checked

**File:** `R/advise.R:240-241`

**Issue:** This is the root cause shared by CR-02. The current check:
```r
actual_na <- length(actual) == 0L || is.null(actual) ||
             (length(actual) == 1L && is.na(actual))
```
only flags scalar NAs. A length > 1 vector with at least one non-NA element is handled safely by `mean(na.rm=TRUE)`. But a length > 1 all-NA vector is not caught — it produces `NaN` and crashes (CR-02 above). The `actual_na` flag should cover this case explicitly so all downstream paths receive a reliable TRUE/FALSE.

The fix from CR-02 (guarding against `is.nan(actual)` after the mean) is the minimal correct repair. The cleaner fix unifies the check:
```r
actual_na <- length(actual) == 0L || is.null(actual) ||
             all(is.na(actual))   # covers scalar NA, vector all-NA, and NaN
```
Then the mean() path for length > 1 vectors naturally produces `NaN`, but `actual_na` is already `TRUE` and the code branches to the mismatch path before reaching the tolerance calculation.

---

## Info

### IN-01: Test helper `.advise_expect_warning()` evaluates its expression twice — doubles side-effects

**File:** `tests/testthat/test_advise.R:30-41`

**Issue:** The helper evaluates `expr_call` twice: once inside `expect_warning()` to assert the warning fires, and once with `withCallingHandlers` to capture the return value. Any expression with observable side effects (e.g., network calls, state mutation, incrementing a counter) would run twice. For the current canned-provider tests this is harmless, but the pattern is fragile: if a future test passes a real-provider call or mutating expression to this helper, the double-evaluation will cause a confusing test failure or double billing. The comment acknowledges the pattern but doesn't flag the risk.

**Fix:** Capture the warning and return value in a single evaluation:
```r
.advise_expect_warning <- function(expr_call, pattern) {
  env    <- parent.frame()
  result <- NULL
  withCallingHandlers(
    result <- eval(expr_call, envir = env),
    warning = function(w) {
      expect_match(conditionMessage(w), pattern)
      invokeRestart("muffleWarning")
    }
  )
  result
}
```

---

## Focus-Area Verdicts

| Focus Area | Verdict |
|---|---|
| Grounding invariant (ADV-04) | FAIL — CR-01 (empty evidence bypass), CR-02 (NaN crash), CR-03 (Inf false-accept) |
| Exactly-one-warning contract | PASS — all failure paths are correctly routed; no double-warning found on normal inputs |
| Key/secret safety | PASS — `R/advise.R` never accesses or propagates credentials; provider object only used for `$source` and `$complete()` |
| KB-grounds / LLM-interprets (ADV-05) | PASS on common paths; impaired by CR-01 (empty evidence bypass applies equally to KB+LLM path) |
| jsonlite/httr2 guarding | PASS — every `jsonlite::` call is guarded by `requireNamespace`; absent-jsonlite degrades cleanly |
| Backward-compat (ADV-07) | PASS — `generate_report(advice=NULL)` is byte-identical to the old path; invalid advice degrades with exactly one warning |
| General R correctness | PASS — `%||%` usage is correct throughout; `seq_along` used where needed; S3 dispatch is correct |

---

**Verdict: FIX-REQUIRED**

Must fix before ship: **CR-01** (grounding bypass via empty evidence), **CR-02** (crash on all-NA diagnostic vector), **CR-03** (grounding false-accept for Inf diagnostic values). All three directly violate the milestone's core invariant ("never produce a silently incorrect statistical/advice result, never crash the session"). WR-01 is a documentation-vs-implementation gap that should be fixed before the next external consumer of the `model=` parameter hits silent misbehaviour.

---

_Reviewed: 2026-09-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
