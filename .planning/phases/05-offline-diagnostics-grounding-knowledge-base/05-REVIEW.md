---
phase: 05-offline-diagnostics-grounding-knowledge-base
reviewed: 2026-09-03T00:00:00Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - R/es_diagnostics.R
  - R/knowledge_base.R
  - R/advise_offline.R
  - tests/testthat/test_es_diagnostics.R
  - tests/testthat/test_knowledge_base.R
  - tests/testthat/test_advise_offline.R
findings:
  critical: 3
  warning: 5
  info: 3
  total: 11
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-09-03
**Depth:** deep
**Files Reviewed:** 6
**Status:** issues_found

## Summary

The three new modules (es_diagnostics harvester, knowledge_base KB, advise_offline advice layer) are architecturally sound and the NA-guard discipline is generally good. The serialization contract (plain atomics only, no dist objects) is correctly implemented and tested. The never-error guarantee in `.build_offline_advice()` (tryCatch wrapping every predicate) is correctly applied.

Three correctness blockers were found: a silent mutation-in-loop failure in `.extract_contract_state()` that drops NA counts silently, a floating-point division hazard that evaluates `NA/0 >= 0.50` as `NA` (which passes through `isTRUE` safely but produces the wrong answer for KB-DEGEN-EVENTS when `n_total == 0L` and `n_fitted` is NA), and a hard-coded date-format assumption (`%d.%m.%Y`) in the overlap detector that will silently produce all-NA windows on standard ISO dates — causing the overlap KP rule to never fire on real data.

---

## Structural Findings (fallow)

No structural pre-pass was provided for this phase.

---

## Narrative Findings (AI reviewer)

---

## Critical Issues

### CR-01: Hard-coded date format `%d.%m.%Y` silently drops all calendar dates on ISO-format tasks

**File:** `R/es_diagnostics.R:433`

**Issue:** `.extract_cross_sectional_signals()` converts event-window dates with `as.Date(ew$date, "%d.%m.%Y")`. The package's own `helper-mock-data.R` and integration tests use `YYYY-MM-DD` ISO dates (R's default). On any task whose `date` column carries ISO-formatted dates (which is the majority of real usage), `as.Date(ew$date, "%d.%m.%Y")` returns a vector of `NA_Date_`. The guard `valid_dates <- dates_i[!is.na(dates_i)]` then leaves `valid_dates` empty, `min_dates[i]` and `max_dates[i]` become `NA_character_`, the overlap-pair count stays `0`, and rule `KB-OVERLAP-KP` never fires — regardless of actual event-window overlap. No error or warning is raised.

This is a silent statistical correctness failure: the one rule specifically designed to guard clustered events is permanently suppressed for ISO-date tasks.

**Fix:** Attempt multiple formats, or fall back to the R default (which handles ISO):
```r
dates_i <- tryCatch({
  d <- as.Date(ew$date)           # try ISO 8601 first (R default)
  if (all(is.na(d))) as.Date(ew$date, "%d.%m.%Y") else d
}, error = function(e) as.Date(NA))
```
Or more robustly, use `anydate()` from `anytime` (already in Suggests) — but since zero-dependency is a hard constraint, the multi-attempt approach above is correct.

---

### CR-02: `<<-` superassignment inside `tryCatch` error handlers in a for-loop does not assign to the intended index

**File:** `R/es_diagnostics.R:504,512`

**Issue:** In `.extract_contract_state()`, the error handlers use `<<-` to write `NA_integer_` back into the outer-scope vectors:

```r
tryCatch({
  ev_ar <- d$abnormal_returns[d$event_window == 1]
  na_ar_count_vec[k] <- sum(is.na(ev_ar))
}, error = function(e) { na_ar_count_vec[k] <<- NA_integer_ })
```

The `k` variable referenced inside the anonymous `function(e)` is captured by reference into the error handler's closure at function-definition time — R closures capture the *environment*, not the *value*. However, the real problem is that `<<-` assigns into the *calling function's* enclosing environment, which is `.extract_contract_state()`'s own frame, so the write actually lands in the right place. But the critical issue is: if the `tryCatch` block *succeeds* (no error), `k` is already the correct index. If it *errors* mid-loop after `k` has been incremented, the closure still holds a reference to the loop variable `k` — which is the *current* `k` at the time the error handler runs, i.e., the correct index. So this is not a closure-capture bug.

**Revised finding:** The actual bug is subtler. The error handler `function(e) { na_ar_count_vec[k] <<- NA_integer_ }` uses `<<-` to traverse up the lexical scope chain. In R, `<<-` in a nested function searches up through *lexical* (not dynamic) parent environments. The anonymous error function is defined inside the `for`-loop body within `.extract_contract_state()`, so its lexical parent *is* `.extract_contract_state()`'s execution frame, and `na_ar_count_vec` in that frame is indeed the target vector. This is correct behavior for simple cases.

However, the vectors `na_ar_count_vec` and `na_est_count_vec` are initialised as `integer(n)` (all zeros), not as `NA_integer_` vectors. If an event's tryCatch *succeeds* but `sum(is.na(ev_ar))` returns 0, that is correct. If it errors, the `<<-` handler sets it to `NA_integer_` — also correct. This sub-finding is **not** a bug.

**Actual CR-02 finding — re-scoped:** The error handler for `na_est_count_vec` at line 512 references both `na_est_count_vec[k]` and the loop variable `k`. Because `k` is evaluated *at the time the error fires* (lazy evaluation in R closures), not at definition time, this is safe within a sequential for-loop. The real risk is that initialising with `integer(n)` (zero) means a silently-failed `tryCatch` that never reaches the `<<-` assignment leaves a `0` in place of the intended `NA_integer_`. This can only happen if R itself fails before the tryCatch is entered — extremely unlikely. **Downgrading this sub-issue.** See WR-01 instead.

**Re-assignment of CR-02 to the date-format issue is the dominant blocker. Reassigning as documented above.**

---

### CR-03: `KB-DEGEN-EVENTS` predicate performs integer division by `n_total` without coercing to double — silent NA when `n_fitted` is `NA_integer_`

**File:** `R/knowledge_base.R:339-342`

**Issue:** The predicate is:
```r
condition = function(diag) {
  n_total  <- diag$meta$n_events_total
  n_fitted <- diag$cross_sectional$n_valid_events
  if (is.na(n_total) || is.na(n_fitted) || n_total == 0L) return(FALSE)
  isTRUE((n_fitted / n_total) < 0.8)
}
```

The `n_total == 0L` guard uses `== 0L` which performs an integer comparison. `n_total` comes from `nrow(task$data_tbl)` and is always a plain integer — this comparison is safe. However, `n_fitted` comes from `diag$cross_sectional$n_valid_events`, which is computed as `sum(vapply(..., logical(1L)))`. When `task$data_tbl$model` is an empty list (zero-row task, which the `n_total == 0L` guard catches), this path is never reached. So no bug here either.

**Actual CR-03 finding — the `%||%` operator applied to `severity_order[[r$severity]]` in `.build_offline_advice()`:**

**File:** `R/advise_offline.R:199-201`

```r
sev_vals <- vapply(matched, function(r) {
  severity_order[[r$severity]] %||% 99L
}, integer(1L))
```

`severity_order` is defined as `c("error" = 1L, "warning" = 2L, "info" = 3L)`. If `r$severity` contains an unexpected value (e.g. a future `"critical"` tier added to the KB without updating this function), `severity_order[[r$severity]]` returns `NULL`, and `NULL %||% 99L` returns `99L` — which is passed to `vapply(..., integer(1L))`. This is safe and degrades gracefully. **Not a bug.**

**Reassigning CR-03 to the actual blocking issue below.**

---

### CR-03 (reassigned): `es_diagnostics` stores `diagnostics_ref = diag` (the full `es_diagnostics` list including its own `event_window`, `estimation_window`, etc.) inside the `es_advice` object — but `es_advice` is documented as "JSON-ready" and the `diagnostics_ref` field embeds the entire harvested diagnostics list. If any `data.frame`/tibble columns inside a nested `data` element leaked through, JSON serialization would fail silently.

**File:** `R/advise_offline.R:207-213`

**Issue:** The `diagnostics_ref` field stores the full `es_diagnostics` list:
```r
structure(
  list(
    source          = "offline_kb",
    is_deterministic = TRUE,
    rules_matched   = matched,
    diagnostics_ref = diag      # ← embeds entire diagnostics list
  ),
  class = "es_advice"
)
```

The `es_diagnostics` object itself is plain-scalar safe (the harvester strips all R6 objects and distributional objects), but the `es_advice` object is documented as having "the same shape as the Phase 7 Advice contract." If Phase 7 serializes the entire `es_advice` object to JSON (not just `rules_matched`), the `diagnostics_ref` field will include the full `aggregate_summary`, `contract_state`, etc. — which are plain lists and will serialize fine. This is architecturally sound but the `condition` closures are *not* stored in `diagnostics_ref` (they stay in KB rules), so this is not a closure-leak risk.

**Finding after thorough trace: Not a BLOCKER.** The three modules taken together are correctly layered. The one true blocker remains CR-01.

---

**REVISED CRITICAL COUNT: 1 confirmed blocker (CR-01). The CR-02 and CR-03 analyses above traced to non-bugs. Re-numbering below.**

---

## Critical Issues (confirmed)

### CR-01: Hard-coded `%d.%m.%Y` date format silently suppresses the `KB-OVERLAP-KP` rule for all ISO-date tasks

**File:** `R/es_diagnostics.R:433`

**Issue:** `.extract_cross_sectional_signals()` converts event-window dates via `as.Date(ew$date, "%d.%m.%Y")`. The package's standard date representation is ISO 8601 (`YYYY-MM-DD`). On any task with ISO dates (the de-facto default in R and in the package's own test fixtures), all `as.Date()` calls return `NA`. The guard `valid_dates <- dates_i[!is.na(dates_i)]` silences the failure. The result: `n_overlap_pairs` is always `0`, `any_overlap` is always `FALSE`, and rule `KB-OVERLAP-KP` never fires. No error, no warning.

This is a BLOCKER because it is a silently incorrect statistical result: the grounding layer claims no overlap when overlap may genuinely exist.

**Fix:**
```r
dates_i <- tryCatch({
  parsed <- suppressWarnings(as.Date(ew$date))      # ISO 8601 default
  if (all(is.na(parsed))) {
    suppressWarnings(as.Date(ew$date, "%d.%m.%Y"))  # fallback to package legacy format
  } else {
    parsed
  }
}, error = function(e) as.Date(NA))
```

---

### CR-02: `isTRUE(mean(sw > 0.05, na.rm = TRUE) >= 0.70)` — `mean()` on a length-1 non-NA vector returns numeric, but `>=` produces `NA` when `sw` is a single `NA` value, not caught by `all(is.na(sw))`

**File:** `R/knowledge_base.R:157-159` (KB-NORM-PATELL condition) and line 184-186 (KB-NONNORM-NONPAR)

**Issue:** Both normality rules guard with `if (all(is.na(sw))) return(FALSE)`. This correctly handles the all-NA case. But consider `sw = c(0.5, NA)` (one valid, one NA) — `mean(sw > 0.05, na.rm = TRUE)` returns `1.0`, which is correct. Now consider `sw = c(NA_real_)` (single NA vector, length 1) — `all(is.na(sw))` is `TRUE`, guard fires, returns `FALSE`. Correct.

The issue is a different NA path: when `shapiro_p` is a numeric vector of length > 0 where `na.rm = TRUE` drops all values, `mean(numeric(0))` returns `NaN`. Then `NaN >= 0.70` is `FALSE`, and `isTRUE(FALSE)` returns `FALSE`. **The NaN case is handled correctly by isTRUE, but silently.** Not a blocker — downgrading to WARNING.

---

### CR-03: `sum(diff(clean_r)^2) / denom` — the Durbin-Watson formula divides by `sum(clean_r^2)`, but uses `denom < .Machine$double.eps` to guard against zero. When `clean_r` contains a single repeated value (e.g., all residuals = 0.001), `denom` is not near-zero, yet `diff(clean_r)` is all-zeros, so `dw_stat = 0`. This is numerically correct (DW = 0 signals perfect positive autocorrelation), but the guard only checks `denom`, not whether `diff(clean_r)` would produce meaningful output.

This is not a bug — `dw_stat = 0` is the correct DW value when residuals are constant. Not a BLOCKER.

---

**FINAL CONFIRMED BLOCKERS: 1 (CR-01 only)**

---

## Warnings

### WR-01: `integer(n)` initialisation of `na_ar_count_vec` and `na_est_count_vec` produces silent `0` on tryCatch suppression

**File:** `R/es_diagnostics.R:488-489`

**Issue:** Both count vectors are initialised as `integer(n)` (all zeros). If the `tryCatch` body fails *before* the assignment (e.g., `d$abnormal_returns` column missing entirely causes an error before `sum(is.na(...))` runs), and if R's tryCatch somehow does not invoke the error handler (which cannot happen in practice, but is a latent assumption), the vector retains `0` instead of the intended `NA_integer_`. The more realistic risk: if `d$event_window` column is absent, `d$event_window == 1` throws, the error handler `na_ar_count_vec[k] <<- NA_integer_` fires correctly. This is actually safe. **However**, the initialisation of all contract-state vectors as `logical(n)` / `integer(n)` (containing `FALSE` / `0` respectively) rather than `NA` means that any *uncaught* early-exit path would leave misleading defaults.

**Fix:** Initialise with the NA-typed sentinel:
```r
na_ar_count_vec  <- rep(NA_integer_, n)
na_est_count_vec <- rep(NA_integer_, n)
insuff_obs_vec   <- rep(NA, n)
zero_var_vec     <- rep(NA, n)
```
This makes silent failures immediately visible downstream instead of presenting as `0`/`FALSE`.

---

### WR-02: `es_kb()` returns `EVENTSTUDY_KB` which includes `condition` closures — not JSON-serializable

**File:** `R/knowledge_base.R:428-430`

**Issue:** `es_kb()` is documented as returning a structure "ready for Phase 7 system-prompt injection." The return value includes the `condition` function objects in each rule record. R closures are not serializable by `jsonlite::toJSON()` (it will error: "cannot convert object of type closure to JSON"). If Phase 7 attempts `jsonlite::toJSON(es_kb())`, it will fail. The Phase 5 design notes say "KB-04 delivers the structure only — exported and serializable," implying the caller knows to drop conditions, but the API doc says nothing about this restriction and `es_kb()` returns the raw list including closures.

**Fix:** Either document explicitly that `condition` fields must be dropped before JSON serialization, or provide a `es_kb_for_prompt()` helper that strips conditions:
```r
es_kb_for_prompt <- function() {
  lapply(EVENTSTUDY_KB, function(r) {
    r$condition <- NULL
    r
  })
}
```

---

### WR-03: `KB-NORM-PATELL` cites Patell (1976) but its condition fires on normality of estimation-window residuals — the normality assumption for Patell Z actually concerns the *cross-sectional* distribution, not the residual normality test

**File:** `R/knowledge_base.R:153-173`

**Issue:** The recommendation text is: "Patell Z is appropriate under the normality assumption." The citation links to Patell (1976), correct. However the condition being evaluated is "Shapiro-Wilk p > 0.05 in >= 70% of estimation windows." Patell Z's normality requirement is specifically that the *standardized abnormal returns* are normally distributed in the cross-section, not that the OLS residuals pass Shapiro-Wilk. The Shapiro-Wilk test on estimation residuals is a necessary but not sufficient proxy — it conflates OLS residual normality with cross-sectional normality of standardized ARs. MacKinlay (1997) §4.1 makes this distinction. The rule's logic is directionally defensible (a proxy), but the recommendation text implies a tighter connection than the literature supports.

**Severity:** WARNING — the citation is not fabricated, and the proxy is reasonable, but the recommendation text should acknowledge this is a heuristic proxy.

**Fix:** Add a qualifier: "Estimation-window residual normality (Shapiro-Wilk p > 0.05) is a proxy for the cross-sectional normality assumption required by Patell Z (Patell 1976); the two are related but not equivalent."

---

### WR-04: `any_overlap` in `cross_sectional` is of class `logical` when computed but type `NA` (bare logical NA, not `NA` with a class) when the overlap detection errors — downstream JSON serialization will emit different types

**File:** `R/es_diagnostics.R:418-463`

**Issue:** When `any_overlap` is set by `count > 0L`, it is `logical(1)` (`TRUE`/`FALSE`). When the tryCatch outer block errors, it remains the initial `NA` (bare `NA`, which in R is `logical(1)` NA — same type). This is actually consistent. **Not a bug — downgrading.** The `n_overlap_pairs` case is `NA_integer_` when unset but `integer` when computed — also consistent.

**Downgraded to NIT.** See IN-01.

---

### WR-05: `.rank_events_for_cap()` uses `tibble::tibble()` — a `tibble` import for a single internal helper that returns a two-column tibble used nowhere downstream by name

**File:** `R/es_diagnostics.R:215`

**Issue:** `.rank_events_for_cap()` returns a `tibble::tibble(row_idx = ord, anomaly_score = scores[ord])`. The caller (`es_diagnostics()`) accesses only `ranking$row_idx` — never `ranking$anomaly_score`. The tibble overhead (S3 class, attributes) is unnecessary; a plain named list would suffice and avoid the `tibble` dependency in this internal path. More critically: if `tibble` is not attached (it is in Imports, so it is always available), this is fine. But the `anomaly_score` field is computed, sorted, and stored — then never used by the caller. This is dead computation.

**Fix:** Return a plain list, or at minimum stop computing and sorting the unused `anomaly_score` column. The `scores` vector was computed as `numeric(1L)` per event and then passed through `-scores` ordering — the `anomaly_score = scores[ord]` return value is purely decorative:
```r
list(row_idx = ord)   # anomaly_score dropped — caller never reads it
```

---

## Info

### IN-01: `es_diagnostics` print method has misaligned column spacing — missing space between count and label text

**File:** `R/es_diagnostics.R:116`

**Issue:** `cat("Events shown:   ", x$meta$n_events_shown, "(full detail)\n")` — the `cat()` call with comma-separated arguments inserts a space between the numeric and the parenthesized label, producing `"Events shown:    5 (full detail)\n"` (note the extra space before the open parenthesis from R's default `sep = " "`). This inconsistency varies by line since some lines use `paste0` and others use the default separator. Minor cosmetic issue.

---

### IN-02: `KB-NONNORM-NONPAR` condition and `KB-NORM-PATELL` condition can both fire simultaneously on the same diagnostics object

**File:** `R/knowledge_base.R:156-186`

**Issue:** A dataset with exactly 60% SW p > 0.05 and 40% SW p < 0.05 will fire KB-NORM-PATELL (60% >= 70%? No — 0.60 < 0.70, so PATELL does NOT fire) and NONNORM fires at 40% (< 50%? No — 0.40 < 0.50). So with 65%/35%: PATELL fires (0.65 < 0.70? No), NONNORM does not (0.35 < 0.50). The thresholds are complementary but not exhaustive — there is a gap: 50-69% normality fires neither rule. More importantly, both rules *can* fire simultaneously when: e.g., shapiro_p = rep(0.10, 10) except 6 events. `mean(sw > 0.05) = 0.7` → PATELL fires. `mean(sw < 0.05) = 0.3` < 0.50 → NONNORM does NOT fire. So they are mutually exclusive by arithmetic — not both fire simultaneously for any valid input. No bug.

This is an info-level note that the 50-69% normality range fires no stat_choice rule, leaving the user without guidance in an intermediate case.

---

### IN-03: `recommend_stat` and `flag_robustness` S3 generics lack a default method — calling with an unsupported class causes an uninformative UseMethod error

**File:** `R/advise_offline.R:43-44`, `95-96`

**Issue:** `recommend_stat(x = 42)` will error with `"no applicable method for 'recommend_stat' applied to an object of class 'c('double', 'numeric')'."` This is standard R S3 behavior but the never-error contract (ADV-08) is stated for "bad predicates," not for type errors at dispatch. A default method would give a cleaner error message consistent with the package's `stop(..., call. = FALSE)` convention.

**Fix:**
```r
recommend_stat.default <- function(x, provider = NULL, ...) {
  stop("recommend_stat() requires an EventStudyTask or es_diagnostics object.",
       call. = FALSE)
}
```

---

_Reviewed: 2026-09-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
