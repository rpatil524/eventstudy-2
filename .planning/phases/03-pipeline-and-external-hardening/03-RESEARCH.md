# Phase 3: Pipeline and External Hardening — Research

**Researched:** 2026-09-02
**Domain:** R pipeline hardening, external-package wrapping, degenerate-input contract extension
**Confidence:** HIGH (all claims derived from direct file reads this session)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**External-Package Failure & Absence Policy**
- Uniform missing-package policy: an estimator-required optional package that is absent produces a **warning naming the lost capability and returns `NULL`** (NOT `stop()`). Currently `estimate_panel_*` for DIDmultiplegt (panel_event_study.R:456-459) and didimputation (549-552) `stop()` — change to warning + NULL. Capability-enhancing packages (e.g. `sandwich`) absent → **warning** (upgrade the current `message()` at panel_event_study.R:171 and cross_sectional.R:75) naming the lost capability + documented OLS/non-robust fallback (no silent degrade).
- **DIDmultiplegt segfault isolation:** wrap the `DIDmultiplegt::did_multiplegt` call (panel_event_study.R:462) in `tryCatch` → warning + `NULL` on error. Add a **subprocess availability probe via `callr` ONLY if `requireNamespace("callr")`** (no new hard dependency); otherwise tryCatch-only plus an opt-out option (`options(eventstudy.skip_didmultiplegt=)`) so a known-segfault platform can skip the call and warn rather than crash.
- **rugarch/rmgarch FAILURE wrapping (deferred from Phase 2):** wrap the external fit calls in `tryCatch`; convergence failure / non-finite result / error → `is_fitted = FALSE` + NA + a named warning. Phase 2 pre-call degenerate guards stay untouched.
- **Synthetic-control numerical guards:** guard the numerical paths in `R/synthetic_control.R` — softmax max-subtraction (overflow), domain checks on `sqrt`/`log`, denominator epsilon guards.

**Pipeline Degradation Policy**
- Missing event date (PIPELINE-01): honor the degenerate mode — strict → error naming the offending event; lenient → warning naming the event + skip it. Reuse `.resolve_degenerate_mode()` / `.handle_degenerate()`. Currently `prepare_event_study.R:110` unconditionally `stop()`s.
- Empty estimation/event window: same mode-honoring policy via the contract.
- export/tidy NA-safety (PIPELINE-02): guard every `if()` that can receive NA with NA-safe checks (`isTRUE()` / `%||%` / `coalesce()` before the `if`); render NA abnormal returns as NA/blank, never crash. Apply consistent `na.rm`.
- cross_sectional collinear/singular (PIPELINE-03): wrap `stats::lm()` (cross_sectional.R:56) and the vcov path in `tryCatch`; rank-deficient / singular → NA coefficients + a warning.

**Scope, Contract Reuse & Testing**
- Contract reuse: use `.handle_degenerate()` where event_id/firm_symbol is identifiable. Use plain `warning()`s for package-availability issues.
- Plan grouping (2 plans): (1) Pipeline hardening — prepare/window/export/tidy/cross_sectional. (2) External-package wrapping — panel-DiD + rugarch/rmgarch + synthetic-control + uniform absence policy.
- Testing external absence: `skip_if_not_installed` for happy paths; simulate absence by mocking `requireNamespace` (testthat::local_mocked_bindings / with_mocked_bindings).
- Panel failure return convention: `estimate_panel_*` returns `NULL` + warning uniformly on failure/absence.

### Claude's Discretion
None stated.

### Deferred Ideas (OUT OF SCOPE)
- Native reimplementation of did / DIDmultiplegt / rugarch estimators → v2 (INDEP-01..03).
- Data-download retry/cache → out of scope (peripheral).
- The contract test matrix across all components in both modes + green R CMD check → Phase 4.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PIPELINE-01 | `prepare_event_study()` missing-date / empty-window: mode-honoring warn+skip or error | Covered: exact stop() location, mode-threading path, event_id/firm_symbol availability via purrr::pmap |
| PIPELINE-02 | `export_results()` / `tidy()` NA-safety: guard every if() that can receive NA | Covered: enumerated all risky if() in .build_export_tables and .tidy_aar |
| PIPELINE-03 | `cross_sectional_regression()` singular/collinear: tryCatch around lm() + vcovHC | Covered: exact line, rank-deficient crash path, fix pattern |
| EXTERNAL-01 | Panel-DiD estimators: uniform absence policy (warning+NULL), wrap actual call in tryCatch | Covered: exact stop() locations, call sites, return structures |
| EXTERNAL-02 | DIDmultiplegt segfault isolation: tryCatch + optional callr probe + opt-out option | Covered: callr NOT in DESCRIPTION, subprocess pattern already in tests |
| EXTERNAL-03 | Uniform optional-package absence policy (message→warning everywhere) | Covered: all message() sites enumerated |
| EXTERNAL-04 | rugarch/rmgarch failure wrapping + synthetic-control numerics | Covered: existing purrr::safely structure, Phase 2 guards, SC numeric hotspots |
</phase_requirements>

---

## Summary

Phase 3 hardens two distinct areas. The **pipeline** area (PIPELINE-01/02/03) involves extending the Phase 1–2 degenerate-input contract into `prepare_event_study()`, making `export_results()`/`tidy()` NA-safe at all `if()` branches, and wrapping `cross_sectional_regression()` against singular/collinear designs. The **external** area (EXTERNAL-01/02/03/04) involves converting four `stop()` calls to `warning()+NULL`, wrapping the actual estimator call sites (not just availability checks) in `tryCatch`, adding optional callr-backed subprocess probe for DIDmultiplegt (callr is NOT currently in DESCRIPTION — no new hard dep allowed), and guarding synthetic-control numerics.

**Critical finding — mode reachability in prepare_event_study:** `prepare_event_study(task, parameter_set)` at `R/prepare_event_study.R:12` receives `parameter_set` as an argument, but `.append_windows()` (called via `purrr::map2` at line 30) only receives `data` and `request`. The `parameter_set` is NOT threaded into `.append_windows()`. To reach mode and event_id/firm_symbol inside `.append_windows()`, the caller (`prepare_event_study`) must switch from `purrr::map2(data, request, .f=.append_windows)` to `purrr::pmap` over `(data, request, event_id, firm_symbol)` rows and pass mode explicitly. This is the principal open question/design decision for PIPELINE-01.

**Critical finding — callr NOT available:** `callr` is not in Imports or Suggests in `DESCRIPTION`. The CONTEXT.md decision is correct: gate the callr probe behind `requireNamespace("callr")`, so the feature degrades to tryCatch-only on environments without callr. No DESCRIPTION change is needed for Phase 3.

**rugarch/rmgarch:** Both GARCHModel and DCCGARCHModel already have a `purrr::safely()` wrapper + convergence check + `warning()` (Phase 2 left these partially wired). The Phase 3 task is to ensure they also set `private$.is_fitted <- FALSE` and emit the named warning in all failure branches — reviewing the code shows they already do for the error path; the remaining gap is the convergence=FALSE branch in GARCHModel (line 1077) and DCCGARCHModel (line 350) which emit a generic warning but do NOT set `.degenerate_handled <- TRUE`. This is benign (abnormal_returns() falls to the else branch and emits one "not fitted" warning), but the CONTEXT.md requires a *named* warning for EXTERNAL-04 — the existing messages are already descriptive enough; no structural change is needed, only verifying the wording satisfies the requirement.

**Primary recommendation:** Use `purrr::pmap` + explicit mode/event_id/firm_symbol threading in `.append_windows()` for PIPELINE-01; all other changes are localized wrapping/message-to-warning upgrades.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Missing-date / empty-window handling | Pipeline (prepare layer) | Contract layer (contract.R) | Detected during window construction; contract helpers provide mode-honoring dispatch |
| Export / tidy NA-safety | Results/Output layer (export.R) | — | NA flows in from model layer; must be absorbed here before rendering |
| Cross-sectional singular guard | Analysis layer (cross_sectional.R) | — | lm() is called here; vcov path is also here |
| Panel-DiD estimator wrapping | Panel layer (panel_event_study.R) | — | External call sites live exclusively here |
| rugarch/rmgarch failure wrapping | Model layer (models.R / models_time_varying.R) | — | Phase 2 pre-call guards are here; failure tryCatch also belongs here |
| Synthetic-control numerics | Special layer (synthetic_control.R) | — | Numerical hotspots are in .solve_sc_optim and sc_placebo_test |

---

## Detailed Research Findings

### 1. PIPELINE-01: prepare_event_study Missing-Date / Empty-Window

**File:** `R/prepare_event_study.R`

**Where the stop() fires:** `prepare_event_study.R:109-113` [VERIFIED: R/prepare_event_study.R:109-113]

```r
if (length(event_index) != 1) {
  stop("Event date '", request$event_date,
       "' not found in data (or found multiple times). ",
       "Check that the event date exists in the firm's trading data.")
}
```

This `stop()` is inside `.append_windows(data_tbl, request)` — a `@noRd` helper called via `purrr::map2` at line 30:

```r
task$data_tbl = task$data_tbl %>%
  mutate(data = purrr::map2(.x=data,
                             .y=request,
                             .f=.append_windows))
```

**What is available at line 109:**
- `request$event_date` — the event date that was not found [VERIFIED: R/prepare_event_study.R:95,110]
- `data_tbl` — the price tibble for one row

**What is NOT available at line 109:**
- `event_id` — NOT in scope; it lives in the outer `task$data_tbl` columns alongside `data` and `request` but is not passed to `.append_windows()`
- `firm_symbol` — same: NOT in scope
- `parameter_set` (so no degenerate mode) — NOT in scope

**Mode-threading design for PIPELINE-01:** [ASSUMED — design decision, not yet in code]

To call `.handle_degenerate()` from within the window-building step, the planner must change:

1. The `purrr::map2` call at line 30 to `purrr::pmap` iterating over `(data, request, event_id, firm_symbol)` rows, passing `mode` as a closure variable (captured from `parameter_set` before the map).

2. The `.append_windows()` signature from `(data_tbl, request)` to `(data_tbl, request, mode, event_id, firm_symbol)`.

3. The `stop()` at line 110 replaced with `.handle_degenerate(mode, condition, "prepare_event_study", event_id, firm_symbol)` followed by a `return(data_tbl)` (returning the raw data with no window columns, so downstream model fitting gets an empty estimation window and the model-layer contract also fires).

**Empty estimation/event window:** After the `stop()` is removed, the windows computed at lines 115-119 [VERIFIED: R/prepare_event_study.R:115-119] may be all-zero (no rows match). This is NOT currently guarded:

```r
data_tbl = data_tbl %>%
  mutate(relative_index    = tmp_index - event_index,
         event_window      = ifelse((relative_index >= event_window_start) & ...),
         estimation_window = ifelse((relative_index >= estimation_window_start) & ...))
```

An empty estimation window (all zeros) is legal to produce here; it will be caught by the model-layer contract (n_valid < 2 guard already present in MarketModel:184–199, etc.). No additional guard is needed in `.append_windows()` for the empty-window case beyond allowing it to propagate — the model layer already handles it.

**OPEN QUESTION for planner (OQ-1):** When `.handle_degenerate()` fires in lenient mode for a missing date, the function must return something to `purrr::pmap`. Returning the raw `data_tbl` (without window columns) means downstream `fit()` will receive data with no `event_window`/`estimation_window` columns, which will crash in `dplyr::filter(estimation_window == 1)`. The safer design is to return `data_tbl` with `event_window = 0L` and `estimation_window = 0L` appended to all rows, so the model layer gets an all-zeros window and fires its own n_valid guard cleanly. The planner should decide and document this in the plan.

---

### 2. PIPELINE-02: export/tidy NA-Safety

**File:** `R/export.R`

All `if()` branches in `.build_export_tables()` and `.tidy_*()` functions were audited. [VERIFIED: R/export.R:61-131, 261-425]

**Safe if() branches (condition guaranteed boolean, not NA-vulnerable):**

| Line | Condition | Why Safe |
|------|-----------|----------|
| 66 | `"ar" %in% which && has_ar` | `has_ar` is computed with `any(purrr::map_lgl(...))` which always returns logical |
| 80 | `"car" %in% which && has_ar` | Same |
| 92 | `"aar" %in% which && has_aar` | `has_aar <- !is.null(task$aar_caar_tbl)` — always logical |
| 93 | `stat_name %in% names(task$aar_caar_tbl)` | `%in%` always returns logical |
| 105 | `"model" %in% which && has_model` | Same |

**NA-vulnerable if() branches in export.R:**

None of the top-level `if()` guards in `.build_export_tables()` are NA-vulnerable. The risk is inside the per-row `purrr::pmap_dfr` lambda at lines 109-124 [VERIFIED: R/export.R:109-124]:

```r
stats <- model$statistics
tibble::tibble(
  is_fitted = model$is_fitted,
  alpha     = stats$alpha %||% NA_real_,
  ...
)
```

The `%||%` guards here are safe. However, line 88 [VERIFIED: R/export.R:87-88]:

```r
dplyr::mutate(car = cumsum(abnormal_returns))
```

`cumsum()` on a vector containing `NA_real_` propagates NA from the first NA onward — this is documented behavior but may surprise users. The CONTEXT.md decision says "render NA abnormal returns as NA/blank, never crash" — `cumsum(NA)` does NOT crash, it returns NA, so this is already policy-compliant. No fix needed here.

**NA-vulnerable if() branches in .tidy_ar (export.R:268-281):** [VERIFIED: R/export.R:268-281]

```r
std.error = if (has_sigma) sigma else NA_real_,
statistic = if (has_sigma) abnormal_returns / sigma else NA_real_,
p.value   = if (has_df && has_sigma) { ... } else NA_real_
```

`has_sigma` is computed at lines 270-271 as `!is.null(sigma) && !is.na(sigma) && is.finite(sigma)` — this is fully NA-safe (short-circuit evaluation guards against NA in sigma). `has_df` at line 272 is `!is.null(df) && !is.na(df) && df > 0` — similarly NA-safe. These `if()` branches are safe.

**NA-vulnerable if() branches in .tidy_car (export.R:307-315):** [VERIFIED: R/export.R:307-315]

```r
std.error = if (has_sigma) sqrt(n) * sigma else NA_real_,
statistic = if (has_sigma) estimate / (sqrt(n) * sigma) else NA_real_,
p.value   = if (has_df && has_sigma) { ... } else NA_real_
```

`has_sigma` and `has_df` computed identically to .tidy_ar — NA-safe. Line 307:

```r
term = paste0("[", relative_index[1], ",", relative_index, "]"),
```

If `event_window == 1` filter returns zero rows, `relative_index[1]` is `NA_real_` and `paste0` silently coerces to `"[NA,...]"` — not a crash but semantically wrong. This is a low-risk cosmetic issue. Flag for planner.

**NA-vulnerable if() branches in .tidy_aar (export.R:362-373):** [VERIFIED: R/export.R:362-373]

```r
std.error = if (length(t_col) > 0) {
  ifelse(.data[[t_col[1]]] != 0, abs(aar / .data[[t_col[1]]]), NA_real_)
} else NA_real_,
statistic = if (length(t_col) > 0) .data[[t_col[1]]] else NA_real_,
p.value   = if (length(t_col) > 0) {
  .compute_pval(.data[[t_col[1]]], t_col[1], n_valid_events)
} else NA_real_,
```

`length(t_col) > 0` is always logical — safe. BUT: `n_valid_events` at line 367 is referenced from the calling tibble column `n_valid_events` — this column is defined in `multi_event_test_statistics.R` CSectTTest at line 30 [VERIFIED: R/multi_event_test_statistics.R:30]:

```r
n_valid_events = sum(!is.na(abnormal_returns)),
```

`sum(!is.na(...))` always returns integer (0 or positive). But if `tbl` (from `task$aar_caar_tbl[[stat_name]]`) is somehow a zero-row tibble, `.compute_pval` receives `numeric(0)` for `stat_vals` and `n_valid_events` will be length-0. `pmax(n_valid - 1, 1)` in `.compute_pval:350` [VERIFIED: R/export.R:350] with length-0 input returns `integer(0)`, and `stats::pt(numeric(0), df=integer(0))` returns `numeric(0)` — no crash, just an empty result. This is acceptable per the CONTEXT.md NA-propagation policy.

**Summary — risky if() count:** 0 crash-producing NA-on-if vulnerabilities found in export.R (3 if-branches in .tidy_ar, 3 in .tidy_car, 6 in .tidy_aar were audited — all safe). The main NA-safety gap is the `cumsum(abnormal_returns)` in `.build_export_tables` line 88 and `.tidy_car` line 307, which propagates NA rather than crashing. The CONTEXT.md policy ("render NA abnormal returns as NA/blank, never crash") is already satisfied. **The real risk is the `message()` → `warning()` upgrade at cross_sectional.R:75 and panel_event_study.R:171.**

**OPEN QUESTION for planner (OQ-2):** The CONTEXT.md says "guard every if() that can receive NA" — per the audit above, no crash-producing NA-on-if exists in export.R today. The planner should verify whether PIPELINE-02 tasks should focus on (a) confirming the existing guards are sufficient and adding regression tests, or (b) proactively upgrading `cumsum` in `.build_export_tables`/`.tidy_car` to `cumsum(coalesce(abnormal_returns, 0))` for the CAR columns while preserving raw NA in the AR column.

---

### 3. PIPELINE-03: cross_sectional Singular/Collinear

**File:** `R/cross_sectional.R`

**The bare lm() call:** `cross_sectional.R:56` [VERIFIED: R/cross_sectional.R:56]

```r
fit <- stats::lm(reg_formula, data = merged)
fit_summary <- summary(fit)
```

**The vcov path with sandwich:** `cross_sectional.R:61` [VERIFIED: R/cross_sectional.R:61]

```r
vcov_hc <- sandwich::vcovHC(fit, type = "HC1")
se <- sqrt(diag(vcov_hc))
```

**Where crash occurs on singular design:**
- `stats::lm()` itself does NOT error on rank-deficient designs; it silently drops aliased columns and sets their coefficients to `NA`. This is R's documented behavior.
- `sandwich::vcovHC()` calls `solve()` internally on the bread matrix. If the design is perfectly singular (not just near-singular), `solve()` throws `"system is computationally singular"`. This is the crash site.
- `stats::coef(fit) / se` on line 66: if `se` contains `0` or `NaN` from near-singular vcov, this produces `Inf`/`NaN` but does not crash.
- `fit_summary$r.squared` at line 82: safe, `summary.lm` always returns numeric.

**Proposed fix pattern:** [ASSUMED — design, not yet in code]

```r
fit_result <- tryCatch(
  stats::lm(reg_formula, data = merged),
  error = function(e) {
    warning("cross_sectional_regression: lm() failed — ", conditionMessage(e),
            call. = FALSE)
    NULL
  }
)
if (is.null(fit_result)) return(NULL)

# Rank check before vcovHC
rank_deficient <- fit_result$rank < length(stats::coef(fit_result))
if (rank_deficient) {
  warning("cross_sectional_regression: design matrix is rank-deficient; ",
          "dropping aliased columns. Robust SEs may be unreliable.", call. = FALSE)
}
```

And wrap the `sandwich::vcovHC` call:

```r
vcov_hc <- tryCatch(
  sandwich::vcovHC(fit_result, type = "HC1"),
  error = function(e) {
    warning("cross_sectional_regression: vcovHC failed (singular design) — ",
            "returning NA standard errors.", call. = FALSE)
    NULL
  }
)
se <- if (!is.null(vcov_hc)) sqrt(diag(vcov_hc)) else rep(NA_real_, length(stats::coef(fit_result)))
```

**message → warning upgrade:** `cross_sectional.R:75` [VERIFIED: R/cross_sectional.R:74-76]

```r
if (robust) {
  message("Package 'sandwich' not available. Using OLS standard errors.")
}
```

Must become `warning(...)` per the CONTEXT.md decision.

---

### 4. EXTERNAL-01/02/03: Panel-DiD Estimator Wrapping

**File:** `R/panel_event_study.R`

#### 4a. did::att_gt (Callaway-Sant'Anna, EXTERNAL-01)

**Availability check:** `panel_event_study.R:409-411` [VERIFIED: R/panel_event_study.R:409-411]

```r
if (!requireNamespace("did", quietly = TRUE)) {
  stop("Package 'did' is required for method='callaway_santanna'. ",
       "Install it with: install.packages('did')")
}
```

**Actual call site:** `panel_event_study.R:415-423` [VERIFIED: R/panel_event_study.R:415-423]

```r
att_gt_result <- did::att_gt(
  yname = task$outcome,
  tname = task$time_id,
  idname = task$unit_id,
  gname = task$treatment_time,
  data = panel,
  base_period = "universal",
  ...
)
agg <- did::aggte(att_gt_result, type = "dynamic")
```

**Current missing-package behavior:** `stop()` — must become `warning() + return(NULL)`.

**Current call wrapping:** None — bare call, no tryCatch.

**What the call returns on success:** `att_gt_result` is an `att_gt` S3 object; `agg` is an `aggte_obj`. Consumed fields: `agg$egt`, `agg$att.egt`, `agg$se.egt` at lines 428-429 [VERIFIED: R/panel_event_study.R:428-429].

**Degraded NULL return:** If this function returns NULL, `estimate_panel_event_study` at line 160 assigns `task` from the switch result. Since `.estimate_callaway_santanna` currently mutates `task$results` directly and returns nothing (the switch returns the result of the last assignment at line 444, not explicitly), the caller pattern at line 160 returns `task` unchanged — BUT the switch evaluates `.estimate_callaway_santanna(...)` as the branch. If the function returns `NULL` early, `task$results` is not set, and `estimate_panel_event_study` returns the unmodified task (results still NULL). This is the correct graceful-degradation behavior.

#### 4b. DIDmultiplegt::did_multiplegt (EXTERNAL-02)

**Availability check:** `panel_event_study.R:456-459` [VERIFIED: R/panel_event_study.R:456-459]

```r
if (!requireNamespace("DIDmultiplegt", quietly = TRUE)) {
  stop("Package 'DIDmultiplegt' is required for ",
       "method='dechaisemartin_dhaultfoeuille'. ",
       "Install it with: install.packages('DIDmultiplegt')")
}
```

**Actual call site:** `panel_event_study.R:462-472` [VERIFIED: R/panel_event_study.R:462-472]

```r
result <- DIDmultiplegt::did_multiplegt(
  df = as.data.frame(panel),
  Y = task$outcome,
  G = task$unit_id,
  T = task$time_id,
  D = task$treatment,
  dynamic = lags,
  placebo = leads,
  mode = "old",
  ...
)
```

**Current call wrapping:** None — bare call, no tryCatch.

**Segfault risk:** The CONCERNS.md confirms: "Segmentation faults on macOS arm64 when loading DIDmultiplegt; API varies across versions" [VERIFIED: .planning/codebase/CONCERNS.md:48-51]. The existing test (test_panel.R:216-252) already uses `system2(Rscript, ...)` as a subprocess probe to avoid loading in the main process [VERIFIED: tests/testthat/test_panel.R:222-230].

**callr availability:** `callr` is NOT in `DESCRIPTION` Imports or Suggests [VERIFIED: DESCRIPTION:32-63]. Therefore per CONTEXT.md the implementation must gate the callr subprocess probe behind `requireNamespace("callr", quietly = TRUE)` and fall back to tryCatch-only when callr is absent.

**Opt-out option design:** [ASSUMED — design, not yet in code]

```r
.estimate_dechaisemartin_dhaultfoeuille <- function(task, panel, leads, lags, ...) {
  if (!requireNamespace("DIDmultiplegt", quietly = TRUE)) {
    warning("Package 'DIDmultiplegt' is not installed. ",
            "Callaway-Sant'Anna or BJS estimators available as alternatives.",
            call. = FALSE)
    return(invisible(NULL))
  }

  if (isTRUE(getOption("eventstudy.skip_didmultiplegt"))) {
    warning("eventstudy.skip_didmultiplegt=TRUE: skipping DIDmultiplegt call.",
            call. = FALSE)
    return(invisible(NULL))
  }

  result <- tryCatch(
    DIDmultiplegt::did_multiplegt(...),
    error = function(e) {
      warning("DIDmultiplegt::did_multiplegt failed: ", conditionMessage(e),
              ". Returning NULL.", call. = FALSE)
      NULL
    }
  )
  if (is.null(result)) return(invisible(NULL))
  # ... rest of parsing ...
}
```

**What did_multiplegt returns on success:** A named numeric vector (or matrix/data.frame coerced at lines 479-489) with elements `effect`, `se_effect`, `placebo_k`, `se_placebo_k`, `dynamic_k`, `se_dynamic_k` [VERIFIED: R/panel_event_study.R:479-524].

#### 4c. didimputation::did_imputation (EXTERNAL-03)

**Availability check:** `panel_event_study.R:549-552` [VERIFIED: R/panel_event_study.R:549-552]

```r
if (!requireNamespace("didimputation", quietly = TRUE)) {
  stop("Package 'didimputation' is required for ",
       "method='borusyak_jaravel_spiess'. ",
       "Install it with: install.packages('didimputation')")
}
```

**Actual call site:** `panel_event_study.R:555-562` [VERIFIED: R/panel_event_study.R:555-562]

```r
result <- didimputation::did_imputation(
  data = as.data.frame(panel),
  yname = task$outcome,
  gname = task$treatment_time,
  tname = task$time_id,
  idname = task$unit_id,
  horizon = TRUE,
  ...
)
```

**Current call wrapping:** None — bare call, no tryCatch.

**What did_imputation returns on success:** A tibble with columns `term`, `estimate`, `std.error` used at lines 565-566 [VERIFIED: R/panel_event_study.R:565-566].

#### 4d. sandwich::vcovCL in .compute_se (EXTERNAL-03)

**Location:** `panel_event_study.R:167-174` [VERIFIED: R/panel_event_study.R:167-174]

```r
.compute_se <- function(fit, panel, cluster) {
  if (requireNamespace("sandwich", quietly = TRUE)) {
    vcov_cl <- sandwich::vcovCL(fit, cluster = panel[[cluster]])
    sqrt(diag(vcov_cl))
  } else {
    message("Install the 'sandwich' package for cluster-robust standard errors. ",
            "Falling back to OLS standard errors.")
    summary(fit)$coefficients[, 2]
  }
}
```

**Current missing-package behavior:** `message()` — must become `warning()` per CONTEXT.md.

**No tryCatch on the vcovCL call:** If `sandwich::vcovCL` fails (e.g. singular cluster structure), it will throw unguarded. This should also be wrapped, though it is a secondary concern vs. the message→warning upgrade.

---

### 5. EXTERNAL-04: rugarch/rmgarch Failure Wrapping

#### 5a. GARCHModel (R/models.R)

**Phase 2 pre-call guards:** Lines 1001-1042 [VERIFIED: R/models.R:1001-1042] — n_valid < 2 guard and sd < .Machine$double.eps guard. These stay untouched per CONTEXT.md.

**Actual rugarch call structure (Phase 3 target):** Lines 1057-1083 [VERIFIED: R/models.R:1057-1083]

```r
safe_fit <- purrr::safely(rugarch::ugarchfit)
res <- safe_fit(spec = spec, data = ..., solver = "hybrid", ...)

if (is.null(res$error)) {
  converged <- tryCatch({
    conv <- rugarch::convergence(res$result)
    is.numeric(conv) && conv == 0
  }, error = function(e) TRUE)  # assume OK if no convergence method
  if (converged) {
    private$.fitted_model <- res$result
    private$.is_fitted <- TRUE
    private$calculate_statistics(data_tbl)
  } else {
    private$.is_fitted <- FALSE
    warning("GARCH model did not converge. Returning NA abnormal returns.")
  }
} else {
  private$.is_fitted <- FALSE
  private$.error <- res$error
  warning("GARCH model fitting failed: ", conditionMessage(res$error))
}
```

**Current state:** `purrr::safely()` is already the outer wrapper. The `is.null(res$error)` branch correctly sets `is_fitted = FALSE` for both failure paths. The warnings are already named (convergence failure: line 1077; error: line 1082).

**Phase 3 gap:** The CONTEXT.md says "convergence failure / non-finite result / error → is_fitted = FALSE + NA + a named warning." The convergence=FALSE branch at line 1076-1078 already does this. The `calculate_statistics` call at line 1074 could itself fail (e.g., `rugarch::sigma()` fails on partially-fitted model) — this is not currently wrapped. Adding a `tryCatch` around `private$calculate_statistics(data_tbl)` is the remaining gap.

#### 5b. DCCGARCHModel (R/models_time_varying.R)

**Phase 2 pre-call guards:** Lines 256-309 [VERIFIED: R/models_time_varying.R:256-309]. Untouched.

**Actual rmgarch call structure:** Lines 333-357 [VERIFIED: R/models_time_varying.R:333-357]

```r
safe_fit <- purrr::safely(rmgarch::dccfit)
res <- safe_fit(dcc_spec, data = returns_mat)

if (is.null(res$error)) {
  converged <- tryCatch({
    H_check <- rmgarch::rcov(res$result)
    all(is.finite(H_check))
  }, error = function(e) FALSE)
  if (converged) {
    private$.fitted_model <- res$result
    private$.is_fitted <- TRUE
    private$calculate_statistics(data_tbl)
  } else {
    private$.is_fitted <- FALSE
    warning("DCC-GARCH model produced non-finite covariance. Returning NA.")
  }
} else {
  private$.is_fitted <- FALSE
  private$.error <- res$error
  warning("DCC-GARCH fitting failed: ", conditionMessage(res$error))
}
```

**Phase 3 gap:** Same as GARCHModel — `private$calculate_statistics(data_tbl)` at line 347 calls `rmgarch::rcov(dcc_fit)` internally at lines 390-392 [VERIFIED: R/models_time_varying.R:390-392], which could fail if the model object is corrupted. Wrap `calculate_statistics` in `tryCatch` with `is_fitted = FALSE + named warning` on error.

**Both models — named warning requirement:** The existing warnings ("GARCH model did not converge", "DCC-GARCH model produced non-finite covariance", "DCC-GARCH fitting failed") are already descriptive and name the component. They satisfy CONTEXT.md's "named warning" requirement without text changes. The planner only needs to add the `calculate_statistics` tryCatch.

---

### 6. EXTERNAL-04: Synthetic Control Numerics

**File:** `R/synthetic_control.R`

#### 6a. Softmax in .solve_sc_optim (already guarded)

Lines 210-214 [VERIFIED: R/synthetic_control.R:210-214]:

```r
.stable_softmax <- function(theta) {
  theta_shift <- theta - max(theta)
  e <- exp(theta_shift)
  e / sum(e)
}
```

`max(theta)` subtraction is already implemented. The denominator `sum(e)` can be zero only if all `exp(theta_shift)` are zero — which cannot happen because `theta_shift` always includes at least one element equal to 0 (from `max(theta) - max(theta)`), so `exp(0) = 1` and `sum(e) >= 1`. **This is already correct.** [VERIFIED: R/synthetic_control.R:210-214]

**Remaining numeric risk:** If `n = 0` (empty donor pool), `theta <- rep(0, n)` is `numeric(0)`, `max(numeric(0))` throws `"no non-missing arguments to max"`. This is the one unguarded case.

#### 6b. MSPE denominators in sc_placebo_test

Lines 266, 301 [VERIFIED: R/synthetic_control.R:266,301]:

```r
ratio_treated <- task$results$post_mspe / max(task$results$pre_mspe, 1e-10)
# ...
mspe_ratios[i] <- pseudo_task$results$post_mspe /
  max(pseudo_task$results$pre_mspe, 1e-10)
```

`max(pre_mspe, 1e-10)` epsilon guard already present. **These are already correct.**

#### 6c. .solve_sc_quadprog ridge regularization

Line 188 [VERIFIED: R/synthetic_control.R:188]:

```r
Dmat <- Dmat + diag(1e-8, n)
```

Ridge already added. **Correct.**

#### 6d. Missing guards

The `X_pre %*% weights` at line 144 [VERIFIED: R/synthetic_control.R:144]: safe as long as dimensions match, which the earlier nrow checks guarantee.

`sqrt()` is not called on any user data in the main estimation path. No domain check needed there.

**Actual remaining gap:** No `tryCatch` around `quadprog::solve.QP` at line 197 [VERIFIED: R/synthetic_control.R:197]:

```r
res <- quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq = meq)
```

If `Dmat` is numerically singular despite the `1e-8` ridge (e.g. perfectly collinear donors), `solve.QP` throws. No current wrapping. Fix: `tryCatch(quadprog::solve.QP(...), error = function(e) { warning(...); NULL })` and fall back to optim if NULL.

The `optim()` call at line 222 [VERIFIED: R/synthetic_control.R:222] already emits a `warning()` if `res$convergence != 0` at line 225. Safe.

---

### 7. DESCRIPTION / Dependencies

**File:** `DESCRIPTION` [VERIFIED: DESCRIPTION:1-64]

**Imports (hard):** R6, distributional, plotly, tibble, ggplot2, dplyr, purrr, tidyr, stringr, rlang, stats, tools, utils.

**Suggests (optional):** testthat (>= 3.0.0), withr, gridExtra, knitr, rmarkdown, openxlsx, rugarch, sandwich, covr, rmgarch, quadprog, did, DIDmultiplegt, didimputation, tidyquant, quantmod, DT, zoo.

**callr:** NOT in Imports or Suggests. [VERIFIED: DESCRIPTION:45-63]

**testthat version:** 3.3.2 installed [VERIFIED: Rscript -e "packageVersion('testthat')"] — `local_mocked_bindings` is available in testthat >= 3.2.0. [ASSUMED: exact API — training knowledge, confirmed by version number meeting threshold]

**`with_mocked_bindings` availability:** Available since testthat 3.1.2 [ASSUMED: training knowledge]. At 3.3.2, both `local_mocked_bindings` and `with_mocked_bindings` are available.

**No new Suggests needed** for Phase 3: `callr` is optional (requireNamespace gate), all other wrapped packages are already in Suggests. If the planner wants to add an `eventstudy.skip_didmultiplegt` test that uses callr, callr could be added to Suggests, but this is not required.

---

### 8. Testing Patterns

#### Simulating optional-package absence

**Pattern already in test_panel.R for DIDmultiplegt** (lines 216-252) [VERIFIED: tests/testthat/test_panel.R:216-252]: uses `nzchar(system.file(package="DIDmultiplegt"))` + `system2(Rscript, ...)` subprocess probe. This is the happy-path pattern.

**For absence tests:** `testthat::local_mocked_bindings` is the correct pattern for Phase 3:

```r
test_that("callaway_santanna warns and returns NULL when did absent", {
  local_mocked_bindings(
    requireNamespace = function(pkg, ...) pkg != "did",
    .package = "base"
  )
  task <- PanelEventStudyTask$new(create_mock_staggered_panel())
  expect_warning(
    result <- estimate_panel_event_study(task, method = "callaway_santanna"),
    "did"
  )
  expect_null(result$results)
})
```

**Note on mocking `requireNamespace`:** `requireNamespace` is in `base`; mocking it with `.package = "base"` or `.package = "EventStudy"` requires care. The mock must be scoped to the package namespace under test. The testthat 3e `local_mocked_bindings(.package = "EventStudy")` scopes the mock to calls from within the EventStudy package. [ASSUMED: exact .package scoping syntax — training knowledge; verify against testthat docs during implementation]

#### skip_if_not_installed pattern (existing)

`test_panel.R:195-196`: `skip_if_not_installed("did")` [VERIFIED: tests/testthat/test_panel.R:195-196] — standard pattern for happy-path tests requiring optional packages. Continue using this for all external-package happy-path tests.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rank-deficiency detection | Custom linear algebra | `fit$rank < length(coef(fit))` (base R lm) | lm already computes rank; field is populated |
| vcov failure recovery | Custom matrix inversion | tryCatch around sandwich::vcovHC + NA fallback | sandwich error messages are informative; catching is sufficient |
| GARCH convergence check | Re-implementing ugarchfit | rugarch::convergence() already exposed | Phase 2 already uses this |
| Subprocess probe for DIDmultiplegt | Custom fork/exec | system2(Rscript, ...) (already in tests) or callr::r() | Pattern already proven in test_panel.R:222-230 |
| Softmax overflow | Custom exp clamping | max-subtraction (already in .stable_softmax) | Already correctly implemented |

---

## Common Pitfalls

### Pitfall 1: map2 → pmap threading for .append_windows
**What goes wrong:** Attempting to pass `mode`, `event_id`, `firm_symbol` into `.append_windows` while keeping `purrr::map2(data, request)` will fail — map2 only passes two arguments.
**How to avoid:** Switch to `purrr::pmap(list(data=..., request=..., event_id=..., firm_symbol=...), function(data, request, event_id, firm_symbol) { .append_windows(data, request, mode, event_id, firm_symbol) })` where `mode` is captured from the enclosing scope.
**Warning sign:** "unused argument" or wrong results in the missing-date warning message.

### Pitfall 2: estimate_panel_* return value convention
**What goes wrong:** The current `.estimate_callaway_santanna` / `.estimate_dechaisemartin_dhaultfoeuille` / `.estimate_borusyak_jaravel_spiess` helpers mutate `task$results` in place and return nothing meaningful — the outer `estimate_panel_event_study` returns `task` regardless. Adding `return(invisible(NULL))` early inside a helper does NOT prevent `task` from being returned by `estimate_panel_event_study`. The planner must ensure NULL is NOT interpreted as success by checking `is.null(task$results)` after the call.
**How to avoid:** Document this: when a helper returns NULL early (absence or failure), `task$results` stays NULL; callers can detect failure via `is.null(task$results)`.

### Pitfall 3: local_mocked_bindings for requireNamespace
**What goes wrong:** Mocking `requireNamespace` in the wrong namespace scope causes the real function to still run inside the package under test.
**How to avoid:** Use `.package = "EventStudy"` (the package calling `requireNamespace`, not "base") in `local_mocked_bindings`. Verify with a quick test that the warning is actually emitted.

### Pitfall 4: tryCatch around calculate_statistics leaves is_fitted = TRUE
**What goes wrong:** If `calculate_statistics` fails after `private$.is_fitted <- TRUE` is set (line 1073/1074 in GARCHModel), the model reports `is_fitted = TRUE` but has no statistics populated. Downstream export code accesses `model$statistics$sigma %||% NA_real_` and gets NA (correct), but `model$is_fitted` = TRUE (misleading).
**How to avoid:** Set `private$.is_fitted <- FALSE` in the `tryCatch` error handler for `calculate_statistics`, after emitting the named warning.

### Pitfall 5: DIDmultiplegt mode="old" API
**What goes wrong:** `DIDmultiplegt::did_multiplegt` with `mode="old"` is required in recent package versions; the current call already includes this at line 467 [VERIFIED: R/panel_event_study.R:467]. Wrapping in tryCatch may catch this API mismatch error and hide a configuration issue.
**How to avoid:** The warning message in the tryCatch error handler should include the full `conditionMessage(e)` so API mismatch is visible to the user.

---

## Architecture Patterns

### Pattern 1: Mode-Honoring Pipeline Degradation (PIPELINE-01)

```r
prepare_event_study <- function(task, parameter_set) {
  # ...
  mode <- .resolve_degenerate_mode(parameter_set$degenerate_handling)

  task$data_tbl <- task$data_tbl %>%
    dplyr::mutate(data = purrr::pmap(
      list(data = data, request = request,
           event_id = event_id, firm_symbol = firm_symbol),
      function(data, request, event_id, firm_symbol) {
        .append_windows(data, request, mode, event_id, firm_symbol)
      }
    ))
  task
}

.append_windows <- function(data_tbl, request, mode = "lenient",
                             event_id = NULL, firm_symbol = NULL) {
  # ...
  if (length(event_index) != 1) {
    .handle_degenerate(
      mode        = mode,
      condition   = paste0("event date '", request$event_date, "' not found in trading data"),
      component   = "prepare_event_study",
      event_id    = event_id,
      firm_symbol = firm_symbol
    )
    # Return data with empty windows so model-layer contract fires
    return(data_tbl %>%
             dplyr::mutate(relative_index = NA_real_,
                           event_window = 0L,
                           estimation_window = 0L))
  }
  # ...
}
```

Source: derived from `.handle_degenerate` signature at `R/contract.R:74-97` [VERIFIED: R/contract.R:74-97]

### Pattern 2: Warning + NULL for Missing Optional Package

```r
if (!requireNamespace("did", quietly = TRUE)) {
  warning("Package 'did' is not installed — callaway_santanna estimator unavailable. ",
          "Install with: install.packages('did')", call. = FALSE)
  return(invisible(NULL))
}
```

### Pattern 3: tryCatch Wrapping of External Estimator Call

```r
result <- tryCatch(
  did::att_gt(yname = ..., ...),
  error = function(e) {
    warning("did::att_gt failed: ", conditionMessage(e),
            " — returning NULL.", call. = FALSE)
    NULL
  }
)
if (is.null(result)) return(invisible(NULL))
```

---

## Open Questions

1. **OQ-1 (PIPELINE-01): Empty-window return from .append_windows in lenient mode.**
   - What we know: `.handle_degenerate` in lenient mode returns `invisible(FALSE)` and sets `private$.is_fitted = FALSE` on the model. But `.append_windows` has no `private` — it is a free function.
   - What's unclear: Should `.append_windows` return the raw `data_tbl` (no window columns) or `data_tbl` with all-zero `event_window`/`estimation_window` columns? The former crashes `fit()` at `filter(estimation_window == 1)`; the latter propagates cleanly.
   - Recommendation: Return `data_tbl` with `event_window = 0L`, `estimation_window = 0L` for all rows. Document this in the plan.

2. **OQ-2 (PIPELINE-02): Scope of NA-safety work in export/tidy.**
   - What we know: No crash-producing NA-on-if exists in export.R today per the audit above.
   - What's unclear: Does the planner want (a) add regression tests confirming current guards hold, or (b) proactively upgrade `cumsum(abnormal_returns)` in car tables to `cumsum(coalesce(abnormal_returns, 0))`?
   - Recommendation: Option (b) for the CAR export/tidy-car path only; preserve NA in AR column. Add regression tests for both.

3. **OQ-3 (EXTERNAL-02): callr subprocess probe scope.**
   - What we know: `callr` not in DESCRIPTION; must be optional.
   - What's unclear: The subprocess probe should verify DIDmultiplegt can *load* without segfaulting — but this requires actually importing the package in a subprocess, which is what `system2(Rscript, "library(DIDmultiplegt)")` does (already in test_panel.R:222-230). The Phase 3 version would run this probe inside the *production code* path (not tests) before calling `did_multiplegt`. Is a 30-second subprocess timeout acceptable in production use?
   - Recommendation: Gate the probe behind `getOption("eventstudy.probe_didmultiplegt", default = FALSE)` so it opt-in only; default is tryCatch-only. Document the option.

4. **OQ-4 (EXTERNAL-04): calculate_statistics tryCatch in GARCHModel.**
   - What we know: `private$calculate_statistics(data_tbl)` is called at line 1074 (inside `if (converged)` branch). If it fails, `private$.is_fitted` is already `TRUE`.
   - What's unclear: Should failure in `calculate_statistics` reset `is_fitted = FALSE` (making the model behave as unfitted) or leave `is_fitted = TRUE` with NA statistics?
   - Recommendation: Reset to `FALSE` and emit named warning. Consistent with the "never silently wrong" core value.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R (>= 4.1.0) | All | Yes | — | — |
| testthat | Testing | Yes | 3.3.2 | — |
| did | Callaway-Sant'Anna | Optional (Suggests) | — | skip_if_not_installed |
| DIDmultiplegt | dCDH estimator | Optional (Suggests) | — | tryCatch + opt-out option |
| didimputation | BJS estimator | Optional (Suggests) | — | skip_if_not_installed |
| sandwich | Robust SEs | Optional (Suggests) | — | OLS SE fallback + warning |
| rugarch | GARCHModel | Optional (Suggests) | — | is_fitted=FALSE + warning |
| rmgarch | DCCGARCHModel | Optional (Suggests) | — | is_fitted=FALSE + warning |
| callr | DIDmultiplegt probe | NOT in DESCRIPTION | — | tryCatch-only |
| quadprog | SC quadprog solver | Optional (Suggests) | — | optim fallback (already coded) |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | testthat 3.3.2 |
| Config file | Config/testthat/edition: 3 in DESCRIPTION |
| Quick run command | `Rscript -e "devtools::test(filter='pipeline')"` |
| Full suite command | `Rscript -e "devtools::test()"` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PIPELINE-01 | Missing date → warning + skip (lenient) | unit | `devtools::test(filter='prepare')` | No (add to test_execute.R or new test_prepare.R) |
| PIPELINE-01 | Missing date → stop() (strict) | unit | same | No |
| PIPELINE-02 | cumsum with NA → NA not crash | unit | `devtools::test(filter='export')` | Partial (test_export.R exists) |
| PIPELINE-03 | Singular lm → warning + NA coefs | unit | `devtools::test(filter='cross_sectional')` | Partial (test_cross_sectional.R exists) |
| EXTERNAL-01 | did absent → warning + NULL task | unit (mocked) | `devtools::test(filter='panel')` | Partial (test_panel.R exists) |
| EXTERNAL-02 | DIDmultiplegt absent → warning + NULL | unit (mocked) | same | Partial |
| EXTERNAL-02 | DIDmultiplegt opt-out option works | unit | same | No |
| EXTERNAL-03 | didimputation absent → warning + NULL | unit (mocked) | same | No |
| EXTERNAL-04 | GARCH convergence fail → is_fitted=FALSE | unit | `devtools::test(filter='models_time_varying')` | Partial |
| EXTERNAL-04 | SC empty donor pool → guard | unit | `devtools::test(filter='synthetic_control')` | Partial |

### Wave 0 Gaps
- [ ] `tests/testthat/test_prepare.R` — covers PIPELINE-01 (missing date, empty estimation window, both modes)
- [ ] Expand `tests/testthat/test_export.R` — NA abnormal_returns propagation through all four tidy types
- [ ] Expand `tests/testthat/test_cross_sectional.R` — singular/collinear design test
- [ ] Expand `tests/testthat/test_panel.R` — absence tests via `local_mocked_bindings` for did, DIDmultiplegt, didimputation, sandwich
- [ ] Expand `tests/testthat/test_models_time_varying.R` — calculate_statistics failure path for GARCH/DCC-GARCH
- [ ] Expand `tests/testthat/test_synthetic_control.R` — empty donor pool + quadprog singular guard

---

## Security Domain

`security_enforcement` not explicitly set to false in config; treating as enabled.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | All guards use R's type system + explicit length/NA checks |
| V6 Cryptography | no | No cryptographic operations |
| V2 Authentication | no | Package has no auth layer |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | No access control layer |

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| NA injection via malformed input data → crash | Tampering | All new guards + NA-safe if() |
| Segfault via malicious DIDmultiplegt load | Denial of Service | tryCatch + opt-out option + optional callr probe |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `local_mocked_bindings(.package = "EventStudy")` correctly intercepts `requireNamespace` calls within the EventStudy namespace | Testing Patterns | Mocking doesn't work; absence tests pass trivially; degrade path untested |
| A2 | `with_mocked_bindings` and `local_mocked_bindings` are both available in testthat 3.3.2 | Testing Patterns | Alternative: use `withr::with_options` to set a package-level bypass flag instead of mocking |
| A3 | Returning `data_tbl` with `event_window=0L` / `estimation_window=0L` from `.append_windows` in the missing-date lenient case will cause model-layer contract to fire rather than crash in `filter()` | PIPELINE-01 | If filter on integer 0 column crashes unexpectedly, need different return shape |

---

## Sources

### Primary (HIGH confidence — file reads this session)
- `R/prepare_event_study.R` — full read; lines 12-122 analyzed
- `R/contract.R` — full read; `.resolve_degenerate_mode` lines 51-61, `.handle_degenerate` lines 74-97
- `R/export.R` — full read; all if() branches audited lines 57-425
- `R/cross_sectional.R` — full read; lm() at line 56, vcovHC at line 61, message() at line 75
- `R/panel_event_study.R` — full read; did (409-448), DIDmultiplegt (456-541), didimputation (549-582), .compute_se (166-175)
- `R/models.R` — GARCHModel lines 980-1150; MarketModel lines 139-332
- `R/models_time_varying.R` — full read; DCCGARCHModel lines 218-451, RollingWindowModel lines 9-206
- `R/synthetic_control.R` — full read; .solve_sc_optim lines 204-231, .solve_sc_quadprog lines 184-199
- `R/execute.R` — full read; fit_model lines 29-57, mode-threading pattern lines 31-71
- `DESCRIPTION` — full read; Imports/Suggests enumerated
- `.planning/codebase/CONCERNS.md` — full read
- `.planning/phases/03-pipeline-and-external-hardening/03-CONTEXT.md` — full read
- `tests/testthat/test_panel.R` — partial read; lines 195-270

### Secondary (MEDIUM confidence)
- testthat 3.3.2 version confirmed via `Rscript -e "packageVersion('testthat')"` — `local_mocked_bindings` availability inferred from version

---

## Metadata

**Confidence breakdown:**
- Pipeline hardening (PIPELINE-01/02/03): HIGH — all stop() locations, if() branches, and lm() call confirmed by direct file read with line numbers
- External wrapping (EXTERNAL-01/02/03): HIGH — all call sites confirmed; callr absence confirmed from DESCRIPTION
- rugarch/rmgarch (EXTERNAL-04): HIGH — existing purrr::safely structure confirmed; gap (calculate_statistics tryCatch) identified by direct read
- Synthetic control (EXTERNAL-04): HIGH — hotspots confirmed; softmax already guarded, remaining gap is quadprog tryCatch
- Testing patterns: MEDIUM — testthat version confirmed; local_mocked_bindings scoping behavior is assumed based on version

**Research date:** 2026-09-02
**Valid until:** 2026-10-02 (stable R package ecosystem)
