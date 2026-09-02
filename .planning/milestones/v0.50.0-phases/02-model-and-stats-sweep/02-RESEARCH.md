# Phase 2: Model and Stats Sweep — Research

**Researched:** 2026-09-02
**Domain:** R package robustness — degenerate-input contract applied across all return models and test statistics
**Confidence:** HIGH (all findings from direct file reads this session; every claim cites exact path:line)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**External-Package Model Boundary (Phase 2 vs Phase 3)**
- GARCH, DCC-GARCH, and RollingWindow **do** get the degenerate-input contract guards in Phase 2: apply the *pre-call* guards (insufficient obs, zero/near-zero variance, finite df) via `.handle_degenerate()` before the rugarch/rmgarch call and route existing window-level degeneracies (RollingWindow's insufficient-obs / effective-window / NA-params) through the contract.
- The rugarch/rmgarch **failure** wrapping (tryCatch around the external fit, convergence failure, non-finite covariance) stays in **Phase 3** (EXTERNAL-03/04). Phase 2 leaves those existing failure warnings as-is and only adds the contract's degenerate-input guards.

**Test-Statistic Correctness Scope**
- **STATS-02 (many-to-many):** already fixed — the multi-event stats (BMP/Patell/KP/CSect) join on `event_id`, not `firm_symbol` (GH #7, commit 63d67a1). Phase 2 **verifies and locks** this with regression tests; it does NOT rewrite the joins.
- **STATS-03 (NA-safe CAR/CAAR):** `cumsum(dplyr::coalesce(..., 0))` is already present. Verify + add a firm-drops-mid-window regression test proving the NA gap doesn't corrupt subsequent cumulative values.
- **STATS-04 (single-event / firms-in-multiple-events denominators):** add uniform guards so `n_events == 1` (and zero-variance cross-sectional dispersion) yields NA rather than Inf / divide-by-zero, across Patell/BMP/KP/CSect/Sign; add tests.
- **STATS-01 (Inf/NaN leakage):** guard denominators (`sd < .Machine$double.eps` → NA) consistently in single-event statistics (AR t, CAR t, BHAR).

**Model Rollout & df Counting**
- Group the model migration into **~4 plans by structural similarity**:
  1. Simple/adjusted models: MarketAdjusted, ComparisonPeriodMean, Custom + BHAR, Volume, Volatility
  2. Factor models: LinearFactorModel (base) → FamaFrench3/5, Carhart4 (inherit)
  3. Time-varying / external: RollingWindow, GARCH, DCC-GARCH (pre-call guards only)
  4. Test statistics: single- and multi-event verification + guards + regression tests
- **MODELS-03 (finite-only df):** extract/reuse a shared finite-residual df helper in `R/contract.R` and apply it to every model so df reflects only finite residuals, not total row count.
- **MODELS-04 (FEC):** apply forecast-error correction where the model supports it (as MarketModel does); leave models that don't support it unchanged.
- **Valid-input invariance:** capture per-model valid-input baselines BEFORE migrating each model group and assert byte/near-identical (within ~1e-8) after — the same CONTRACT-05 discipline as Phase 1, per model.

### Claude's Discretion
(None specified — all implementation decisions are locked.)

### Deferred Ideas (OUT OF SCOPE)
- rugarch/rmgarch/did external-**failure** wrapping (tryCatch, convergence, non-finite, availability guards, subprocess isolation) → Phase 3.
- prepare/window/export/tidy and cross-sectional-regression collinearity hardening → Phase 3.
- Full contract test matrix across all components in both modes + green R CMD check → Phase 4.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MODELS-01 | Every return model routes insufficient-obs and zero-variance degenerate conditions through `.handle_degenerate()` | Per-model guard locations documented below; MarketModel exemplar at `R/models.R:176-236` |
| MODELS-02 | `.degenerate_handled` one-warning suppression pattern applied in every model's `abnormal_returns()` | Pattern confirmed at `R/models.R:249-261`; missing in all 9 remaining models |
| MODELS-03 | A shared finite-residual df helper in `R/contract.R` replaces inline `nrow()/length()` df counts in each model | df counting analysed per model below; some use `sum(is.finite())` already, others use raw `nrow()` |
| MODELS-04 | Forecast-error correction applied in every model that structurally supports it | FEC support map documented below |
| STATS-01 | Single-event statistic denominators guarded: `sigma == 0` / NA → return NA rather than Inf/NaN | `ARTTest` and `CARTTest` verified at `R/single_event_test_statistics.R:64-127`; `BHARTTest` has an unguarded denominator (`bhar_se = sigma * sqrt(n)` when sigma=NA) |
| STATS-02 | Multi-event join correctness verified and locked with regression tests | BMP, KP, Patell, CSect confirmed on `event_id` joins; RankTest and GeneralizedSignTest still join/group on `firm_symbol` — verified |
| STATS-03 | NA-safe CAR/CAAR chain confirmed and tested with a firm-drops-mid-window scenario | `coalesce(..., 0)` present in CSect, Sign, BMP, KP, Patell; regression test needed |
| STATS-04 | `n_events == 1` and zero cross-sectional dispersion yield NA, not Inf, in all multi-event stats | CSectT has guard; Patell Q_total=sqrt(sum(Q_i)) can produce Q_total=0 with n_events=1; BMP/KP sd_sar guard present; Sign guard present |
</phase_requirements>

---

## Summary

Phase 2 applies the Phase 1 degenerate-input contract horizontally to every model and test statistic. Direct code reading reveals:

**Nine models need migration.** Three groups have clear mechanical work: (1) simple/no-OLS models (MarketAdjusted, ComparisonPeriodMean, BHAR, Volume) each have one or two plain `warning()` calls that must become `.handle_degenerate()` calls, plus a missing `.degenerate_handled` branch in `abnormal_returns()` — roughly 15–20 lines per model; (2) LinearFactorModel plus its three subclasses (FF3, FF5, Carhart4) need one fix on the base class that the subclasses inherit for free — but each subclass `abnormal_returns()` still needs its own `.degenerate_handled` branch because they override `abnormal_returns()`; (3) RollingWindow, GARCH, and DCC-GARCH need pre-call guards inserted before their existing external calls — moderate work because multi-condition guards and NA-param checks must stay in Phase 2 while tryCatch-around-external stays in Phase 3.

**VolatilityModel is structurally unique:** its zero-variance guard sits in `calculate_statistics()` (called *after* `private$.is_fitted <- TRUE` is set in `fit()`), so migrating it requires moving the guard into `fit()` before the is_fitted assignment.

**CustomModel inherits MarketModel fully** — its `fit()` is MarketModel's (already migrated), so it gets the contract for free. Its `abnormal_returns()` overrides but does not check `is_fitted` at all, which is a separate correctness gap.

**Test statistics are mostly verify-and-lock.** The many-to-many join fix and the coalesce cumsum chain are already in place. Work is: (1) regression tests for the fixed patterns; (2) two surgical denominator guards (STATS-01: BHARTTest `bhar_t` when sigma=NA, STATS-04: PatellZTest `Q_total` when n_events=1); (3) auditing that RankTest and GeneralizedSignTest group on `firm_symbol` (confirmed, but their design intentionally ranks within firm — this is correct, not a bug; document and lock with tests).

**Primary recommendation:** Implement the 4-plan grouping exactly as locked. The biggest risk of introducing regressions is VolatilityModel (guard relocation) and the LinearFactorModel chain (one fix, three subclasses that override `abnormal_returns()`).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Degenerate-input detection | Return Model (`fit()`) | `R/contract.R` helpers | Each model owns its domain-specific condition (e.g. variance, obs count, NA params) |
| Mode dispatch (strict/lenient) | `R/contract.R` `.handle_degenerate()` | `R/execute.R` field injection | Single choke point; models never read the option directly |
| one-warning suppression | Return Model (`abnormal_returns()`) | `ModelBase` `.degenerate_handled` flag | Flag set by `.handle_degenerate()` in lenient mode; read in `abnormal_returns()` |
| df counting | Per-model `calculate_statistics()` (currently) → shared helper | `R/contract.R` `.finite_df()` | Centralise to prevent off-by-one between total rows and finite residuals |
| Test statistic denomination guards | Multi-event stat `compute()` | — | Each statistic guards its own denominator; no shared helper needed |

---

## 1. Per-Model Migration Map

### 1.1 MarketModel — ALREADY MIGRATED (exemplar)

**File:** `R/models.R:139–332`
**Status:** Complete — serves as the reference implementation.

**Insufficient-obs guard:** `R/models.R:183–199`
```r
n_valid <- sum(!is.na(estimation_tbl$firm_returns) &
                !is.na(estimation_tbl$index_returns))
if (n_valid < 2) {
  .handle_degenerate(mode, condition, component, event_id, firm_symbol, private)
  private$.is_fitted <- FALSE
  return(invisible(self))
}
```
[VERIFIED: R/models.R:183-199]

**Zero-variance guard:** `R/models.R:201–213`
```r
if (stats::sd(estimation_tbl$index_returns, na.rm = TRUE) < .Machine$double.eps) {
  .handle_degenerate(...)
  private$.is_fitted <- FALSE
  return(invisible(self))
}
```
[VERIFIED: R/models.R:201-213]

**lm() failure route:** `R/models.R:218–236` — safe_mm wraps lm(); error path calls `.handle_degenerate()`.
[VERIFIED: R/models.R:218-236]

**`.degenerate_handled` suppression in `abnormal_returns()`:** `R/models.R:249–254` — three-branch: fitted / degenerate_handled (silent NA) / not-fitted warning.
[VERIFIED: R/models.R:249-261]

**df counting (calculate_statistics):** `R/models.R:284` — `private$.fitted_model$df.residual` (lm's own df, which counts only non-NA residuals). This is correct and will serve as the pattern; the helper should wrap this for models without an lm object.
[VERIFIED: R/models.R:284]

---

### 1.2 MarketAdjustedModel

**File:** `R/models.R:348–405`
**Status:** Needs migration.

**Current guard (lines 361–366):**
```r
if (n_valid < 2) {
  warning("MarketAdjustedModel: insufficient estimation data (...)  Model not fitted.")
  private$.is_fitted <- FALSE
  return(invisible(NULL))   # <-- returns NULL not self; contract requires invisible(self)
}
```
[VERIFIED: R/models.R:361-366]

**What `fit()` does:** filters estimation window, counts non-NA (firm_returns + index_returns), then `private$.is_fitted = TRUE` and calls `calculate_statistics()`.

**What `calculate_statistics()` does:** computes residuals = firm_returns − index_returns, sigma = sd(residuals, na.rm=TRUE), df = `sum(!is.na(residuals)) - 1`. Includes constant-mean FEC.
[VERIFIED: R/models.R:382-403]

**What `abnormal_returns()` does:** line 376–379 — unconditionally returns `data_tbl %>% mutate(abnormal_returns = firm_returns - index_returns)`. NO is_fitted check, NO `.degenerate_handled` check.
[VERIFIED: R/models.R:376-379]

**Zero-variance gap:** No zero-variance guard for index_returns. (MarketAdjusted does not regress on index_returns, so index zero-variance doesn't affect OLS — but firm_returns zero-variance will yield sigma=0, propagating Inf to downstream test statistics via ar_t = AR/0. Guard needed: `sd(firm_returns - index_returns) < .Machine$double.eps` → degenerate.)

**df counting:** `sum(!is.na(residuals)) - 1` — already finite-only. Correct.
[VERIFIED: R/models.R:395]

**FEC:** Constant-mean FEC computed at lines 398–402. Supported.
[VERIFIED: R/models.R:398-402]

**Required changes:**
1. Replace plain `warning()` with `.handle_degenerate()` call (lines 362–364).
2. Change `return(invisible(NULL))` → `return(invisible(self))`.
3. Add zero-variance guard on `sd(firm_returns - index_returns)`.
4. Add three-branch `.degenerate_handled` check to `abnormal_returns()`.
5. No df change needed.

---

### 1.3 ComparisonPeriodMeanAdjustedModel

**File:** `R/models.R:420–481`
**Status:** Needs migration.

**Current guard (lines 434–439):**
```r
if (n_valid < 2) {
  warning("ComparisonPeriodMeanAdjustedModel: insufficient estimation data (...)  Model not fitted.")
  private$.is_fitted <- FALSE
  return(invisible(NULL))
}
```
[VERIFIED: R/models.R:434-439]

**What `fit()` does:** extracts `est_returns` (firm_returns only — does NOT use index_returns), computes `reference_mean`. No zero-variance guard exists.

**What `calculate_statistics()` does:** residuals = firm_returns − mean(firm_returns), sigma = sd(residuals, na.rm=TRUE), df = `sum(!is.na(residuals)) - 1`. Constant-mean FEC.
[VERIFIED: R/models.R:458-479]

**What `abnormal_returns()` does:** line 452–455 — unconditionally subtracts `private$.fitted_model` (the reference_mean) from firm_returns. NO is_fitted or degenerate_handled check.
[VERIFIED: R/models.R:452-455]

**Zero-variance gap:** sd(firm_returns) == 0 during estimation → sigma=0 → downstream Inf. Guard needed: `sd(est_returns, na.rm=TRUE) < .Machine$double.eps`.

**df counting:** `sum(!is.na(residuals)) - 1` — already finite-only. Correct.
[VERIFIED: R/models.R:471]

**FEC:** Constant-mean FEC supported at lines 474–478. Note: uses `nrow(estimation_tbl)` not `sum(!is.na(...))` in the correction denominator — minor accuracy issue, but out of scope for this phase.
[VERIFIED: R/models.R:474-478]

**Required changes:**
1. Replace plain `warning()` with `.handle_degenerate()`.
2. Change `return(invisible(NULL))` → `return(invisible(self))`.
3. Add zero-variance guard on `sd(est_returns)`.
4. Add three-branch `.degenerate_handled` check to `abnormal_returns()`.

---

### 1.4 CustomModel

**File:** `R/models.R:485–497`
**Status:** Inherits MarketModel — `fit()` is fully inherited and already migrated. One gap in `abnormal_returns()`.

**Inheritance:** `inherit = MarketModel`
[VERIFIED: R/models.R:486]

**`fit()` method:** Not overridden → uses MarketModel's `fit()` which already has all three contract guards. FREE.

**`abnormal_returns()` (lines 489–496):**
```r
abnormal_returns = function(data_tbl) {
  mm_model = private$.fitted_model
  data_tbl %>%
    mutate(abnormal_returns = firm_returns - predict(mm_model, data_tbl),
           abnormal_returns = ifelse(event_date == 1, abnormal_returns + loss_market_cap, abnormal_returns))
}
```
[VERIFIED: R/models.R:489-496]

**Problem:** No `is_fitted` or `.degenerate_handled` check. If `fit()` fails degenerately, `private$.fitted_model` is NULL, and `predict(NULL, ...)` throws an error rather than returning NA.

**Required changes:**
1. Add the three-branch `is_fitted` / `.degenerate_handled` / warning guard at the start of `abnormal_returns()`, returning `data_tbl %>% mutate(abnormal_returns = NA_real_)` in the degenerate cases.

---

### 1.5 LinearFactorModel (base) + FF3 + FF5 + Carhart4

**File:** `R/models.R:509–831`
**Status:** All four need migration; fix once on LinearFactorModel, replicate `.degenerate_handled` branch to each subclass `abnormal_returns()`.

**LinearFactorModel `fit()` (lines 535–557) — current state:**
```r
fit = function(data_tbl) {
  missing_cols <- setdiff(self$required_columns, names(data_tbl))
  if (length(missing_cols) > 0) {
    stop(self$model_name, " requires columns: ", paste(missing_cols, collapse = ", "))
  }
  estimation_tbl <- data_tbl %>% dplyr::filter(estimation_window == 1)
  safe_lm <- purrr::safely(.f = .estimate_mm_model)
  res <- safe_lm(self$formula, estimation_tbl)
  if (is.null(res$error)) {
    private$.fitted_model <- res$result
    private$.is_fitted <- TRUE
    private$calculate_statistics(data_tbl)
  } else {
    private$.is_fitted <- FALSE
    private$.error <- res$error
    warning("Model fitting failed: ", conditionMessage(res$error))
  }
}
```
[VERIFIED: R/models.R:535-557]

**Gaps:**
- No insufficient-obs guard before the `safe_lm` call.
- No zero-variance guard on regressor(s).
- lm() failure goes to plain `warning()` not `.handle_degenerate()`.
- No `.degenerate_handled` flag set anywhere.

**`LinearFactorModel$abnormal_returns()` (lines 563–573):**
```r
if (private$.is_fitted) {
  predicted <- predict(private$.fitted_model, newdata = data_tbl)
  data_tbl %>% dplyr::mutate(abnormal_returns = firm_returns - predicted)
} else {
  warning(self$model_name, " is not fitted. Returning NA abnormal returns.")
  data_tbl %>% dplyr::mutate(abnormal_returns = NA_real_)
}
```
[VERIFIED: R/models.R:563-573]

Missing `.degenerate_handled` middle branch.

**Subclass `abnormal_returns()` all follow same two-branch pattern — each overrides it:**
- FF3: `R/models.R:722-731` [VERIFIED: R/models.R:722-731]
- FF5: `R/models.R:770-779` [VERIFIED: R/models.R:770-779]
- Carhart4: `R/models.R:819-828` [VERIFIED: R/models.R:819-828]

All three have the same structure as LinearFactorModel's base: fitted branch / unfitted warning — no `.degenerate_handled` middle branch.

**df counting:** `private$.statistics$degree_of_freedom <- mod$df.residual` at `R/models.R:614`.
[VERIFIED: R/models.R:614]

`mod$df.residual` is lm's own df (total rows minus rank), which respects NA drops by lm's na.omit. Correct — same as MarketModel.

**FEC:** Full multi-factor FEC using `(X'X)^{-1}` hat values at `R/models.R:650–682`. Already implemented with a `tryCatch(solve(...), error = function(e) NULL)` fallback. Supported.
[VERIFIED: R/models.R:650-682]

**Zero-variance for factor models:** Index_returns is not the only regressor (e.g. FF3 uses market_excess + smb + hml). If ALL regressors are collinear, lm() will fail, which routes through the existing lm-failure path. But if a single factor has zero variance while others don't, lm() silently drops the collinear term — this is NOT a degenerate condition under the contract (contract guards insufficient obs and zero variance in the primary predictor for OLS-based models). The plan should not add per-factor zero-variance guards; let lm() handle it.

**Required changes (LinearFactorModel base):**
1. Add `n_valid <- sum(complete.cases(estimation_tbl[self$required_columns]))` + insufficient-obs guard routed through `.handle_degenerate()`.
2. Replace plain `warning("Model fitting failed...")` with `.handle_degenerate()` call.
3. Add `.degenerate_handled` middle branch to `LinearFactorModel$abnormal_returns()`.

**Required changes (each subclass: FF3, FF5, Carhart4):**
1. Add `.degenerate_handled` middle branch to each subclass `abnormal_returns()` — these override the base method so must be patched individually.
2. No changes to `fit()` in subclasses (they inherit LinearFactorModel's `fit()`).

---

### 1.6 BHARModel

**File:** `R/models.R:979–1047`
**Status:** Needs migration.

**Current guard (lines 993–998):**
```r
if (n_valid < 2) {
  warning("BHARModel: insufficient estimation data (...)  Model not fitted.")
  private$.is_fitted <- FALSE
  return(invisible(NULL))
}
```
[VERIFIED: R/models.R:993-998]

**What `fit()` does:** checks both firm_returns and index_returns non-NA, then computes cumprod-based BHAR residuals and sigma.

**What `calculate_statistics()` does:** computes BHAR residuals via diff(cumprod(...)), sigma = sd(firm_returns - index_returns, na.rm=TRUE), `degree_of_freedom = nrow(estimation_tbl) - 1`.
[VERIFIED: R/models.R:1020-1047]

**df gap:** `nrow(estimation_tbl) - 1` counts ALL rows in the estimation window including NAs. Should use `sum(!is.na(estimation_tbl$firm_returns) & !is.na(estimation_tbl$index_returns)) - 1`. Needs finite-df helper.
[VERIFIED: R/models.R:1037]

**What `abnormal_returns()` does:** lines 1006–1017 — unconditionally performs `cumprod(1 + coalesce(firm_returns, 0))` regardless of `is_fitted`. No is_fitted / degenerate_handled check. If fit() failed, this still computes (using 0 as fill) — producing plausible-looking wrong numbers.
[VERIFIED: R/models.R:1006-1017]

**Zero-variance gap:** No guard for zero-variance in firm or index returns. Sigma=0 will produce Inf in downstream test statistics.

**FEC:** Constant-mean FEC supported at lines 1041–1044. Uses `nrow(estimation_tbl)` — same denominator gap as df counting.
[VERIFIED: R/models.R:1041-1044]

**Required changes:**
1. Replace plain `warning()` with `.handle_degenerate()`.
2. Change `return(invisible(NULL))` → `return(invisible(self))`.
3. Add zero-variance guard on `sd(firm_returns - index_returns)`.
4. Fix df counting: `sum(!is.na(...)) - 1` via shared helper.
5. Add three-branch `.degenerate_handled` check to `abnormal_returns()`.

---

### 1.7 VolumeModel

**File:** `R/models.R:1062–1144`
**Status:** Needs migration. Structurally different: operates on `firm_volume` not returns.

**Current guard (lines 1091–1096):**
```r
n_valid <- sum(is.finite(vol))
if (n_valid < 2) {
  warning("VolumeModel: insufficient estimation data (...)  Model not fitted.")
  private$.is_fitted <- FALSE
  return(invisible(NULL))
}
```
[VERIFIED: R/models.R:1091-1096]

Uses `is.finite(vol)` (after optional log transform) — already the correct finite-only count for this domain. Good pattern.

**What `fit()` does:** checks `firm_volume` column exists (hard stop), optionally log-transforms, guards n_valid < 2, stores mean as fitted model.

**What `calculate_statistics()` does:** residuals = vol - mean(vol), sigma = sd(residuals, na.rm=TRUE), `degree_of_freedom = sum(is.finite(residuals)) - 1`. Already uses finite count — correct.
[VERIFIED: R/models.R:1132-1133]

**What `abnormal_returns()` does:** lines 1106–1114 — reads `private$.fitted_model` (the mean) unconditionally. NO is_fitted check. If fit() failed, `.fitted_model` is NULL, and `.vol - NULL` crashes or returns NA with a confusing error.
[VERIFIED: R/models.R:1106-1114]

**Zero-variance gap:** No guard for `sd(vol) == 0` (all identical volume values). Sigma=0 → Inf in test statistics.

**FEC:** Constant-mean FEC supported at lines 1138–1141. Uses `sum(is.finite(residuals))` for `n_est` — finite-only, correct.
[VERIFIED: R/models.R:1138-1141]

**Domain note:** Volume operates on `firm_volume` column, not `firm_returns`. The `create_degenerate_model_data_insufficient` factory in helper-mock-data.R only creates firm_returns/index_returns-based data. A new factory `create_degenerate_volume_model_data_*()` is needed.

**Required changes:**
1. Replace plain `warning()` with `.handle_degenerate()`.
2. Change `return(invisible(NULL))` → `return(invisible(self))`.
3. Add zero-variance guard on `sd(vol, na.rm=TRUE) < .Machine$double.eps`.
4. Add three-branch `.degenerate_handled` check to `abnormal_returns()`.
5. df counting already correct — no change needed.

---

### 1.8 VolatilityModel

**File:** `R/models.R:1155–1223`
**Status:** Needs migration. Structurally different and has a structural placement bug.

**Current `fit()` (lines 1165–1172):** NO guard — directly calls `var()` and sets `private$.is_fitted <- TRUE` BEFORE `calculate_statistics()`.
[VERIFIED: R/models.R:1165-1172]

**Current guard is in `calculate_statistics()` (lines 1197–1202):**
```r
est_var <- var(estimation_tbl$firm_returns, na.rm = TRUE)
if (is.na(est_var) || est_var < .Machine$double.eps) {
  private$.is_fitted <- FALSE
  warning("VolatilityModel: zero or NA variance in estimation window. ...")
  return(invisible(NULL))
}
```
[VERIFIED: R/models.R:1197-1202]

**Problem:** `private$.is_fitted` is set TRUE in `fit()` at line 1171, THEN `calculate_statistics()` may set it back to FALSE at line 1199. This creates an inconsistency window and, more critically, the `warning()` is not routed through `.handle_degenerate()`, so strict mode is never enforced and event_id/firm_symbol are never included.

**What `abnormal_returns()` does:** lines 1178–1188 — checks `private$.is_fitted` properly (unlike MarketAdjusted/Comparison). Uses `est_var = private$.fitted_model` (the variance scalar). If is_fitted is FALSE, emits `warning("VolatilityModel is not fitted...")` and returns NA. NO `.degenerate_handled` suppression.
[VERIFIED: R/models.R:1178-1188]

**df counting:** `sum(is.finite(residuals)) - 1` at line 1212 — already finite-only. Correct.
[VERIFIED: R/models.R:1212]

**Domain note:** Operates on `firm_returns^2 / est_var - 1` (ratio form). A separate test factory is needed: `create_degenerate_volatility_model_data_zero_var()` where all estimation-window firm_returns are constant.

**FEC:** Constant-mean FEC at lines 1215–1220. Supported.
[VERIFIED: R/models.R:1215-1220]

**Required changes:**
1. **Move the zero-variance/NA guard from `calculate_statistics()` into `fit()`, BEFORE `private$.is_fitted <- TRUE`.**
2. Also add insufficient-obs guard in `fit()` (currently absent — if estimation window has 0 rows, `var()` returns NA and falls through to the relocated guard, which handles it; but should also guard for n_valid < 2 explicitly).
3. Route the guard through `.handle_degenerate()`.
4. Remove the guard from `calculate_statistics()`.
5. Add `.degenerate_handled` middle branch to `abnormal_returns()`.
6. No df change needed.

---

### 1.9 RollingWindowModel

**File:** `R/models_time_varying.R:1–165`
**Status:** Needs migration. Three existing plain `warning()` calls that must become `.handle_degenerate()`.

**Current guards:**

Guard 1 — insufficient estimation obs (lines 37–42):
```r
if (n_est < self$min_obs) {
  private$.is_fitted <- FALSE
  warning("RollingWindowModel: insufficient estimation data (...)")
  return(invisible(self))
}
```
[VERIFIED: R/models_time_varying.R:37-42]

Guard 2 — effective window size < 3 (lines 45–50):
```r
if (ws < 3) {
  private$.is_fitted <- FALSE
  warning("RollingWindowModel: effective window size (...)")
  return(invisible(self))
}
```
[VERIFIED: R/models_time_varying.R:45-50]

Guard 3 — last-window NA parameters (lines 91–96):
```r
if (is.na(alpha_last) || is.na(beta_last)) {
  private$.is_fitted <- FALSE
  warning("RollingWindowModel: last window parameters are NA. ...")
  return(invisible(self))
}
```
[VERIFIED: R/models_time_varying.R:91-96]

Note: Guard 1 uses `nrow(estimation_tbl)` not `sum(!is.na(...))`. This counts rows regardless of NA content. If estimation_tbl has 30 rows but 29 have NA firm_returns, the guard passes while the model is still degenerate. Should add n_valid check using `sum(!is.na(estimation_tbl$firm_returns) & !is.na(estimation_tbl$index_returns)) < self$min_obs`.

**What `abnormal_returns()` does:** lines 105–120 — checks `private$.is_fitted` and emits `warning("RollingWindowModel is not fitted. Returning NA.")`. No `.degenerate_handled` suppression.
[VERIFIED: R/models_time_varying.R:105-120]

**df counting:** `private$.statistics$degree_of_freedom <- ws - 2` at line 141. Uses the rolling window size, not a finite-residual count. This is correct for the rolling context (each window uses ws - 2 df for OLS with intercept + slope). KEEP AS-IS — do not apply the finite-df helper here.
[VERIFIED: R/models_time_varying.R:141]

**Zero-variance:** Inside the rolling loop (lines 70–82), `if (ss_xx > 0)` already handles the zero-variance case per-window by setting beta=NA. The last-window NA guard (Guard 3) catches this. No additional zero-variance guard needed at the top level.
[VERIFIED: R/models_time_varying.R:70-82]

**Phase 2 / Phase 3 boundary (CRITICAL):** Phase 2 adds contract guards on the pre-call conditions (Guards 1, 2, 3 above). The rolling OLS loop itself (lines 60–83) is pure R code — no external package. The `calculate_forecast_error_correction()` call at line 153 is internal. **No external-package wrapping distinction applies here** — the entire model is in-package. All three guards migrate to Phase 2.

**FEC:** Supported at `R/models_time_varying.R:152–157`. Uses `sigma_last` and last-window estimation returns.
[VERIFIED: R/models_time_varying.R:152-157]

**Required changes:**
1. Replace all three plain `warning()` calls with `.handle_degenerate()`.
2. Guard 1: also add n_valid check (finite obs, not just nrow).
3. Add `.degenerate_handled` middle branch to `abnormal_returns()`.
4. No df change.

---

### 1.10 GARCHModel

**File:** `R/models.R:844–965`
**Status:** Needs migration (pre-call guards only; convergence/failure tryCatch stays in Phase 3).

**Current state — no pre-call guards at all.** `fit()` (lines 856–905) goes directly to `rugarch::ugarchspec()` + `rugarch::ugarchfit()` after checking `requireNamespace("rugarch")`.
[VERIFIED: R/models.R:856-905]

**Phase 2 boundary:** Add BEFORE the `rugarch::ugarchspec()` call (currently line 865):
1. Insufficient-obs guard: count valid (firm_returns, index_returns) pairs in estimation window.
2. Zero-variance guard: `sd(estimation_tbl$index_returns, na.rm=TRUE) < .Machine$double.eps` — index_returns is the external regressor in the mean equation; zero variance makes the GARCH mean equation degenerate.

**Existing failure handling (LEAVE UNTOUCHED — Phase 3):**
- `purrr::safely(rugarch::ugarchfit)` at line 878 — stays.
- Convergence check at lines 887–896 — stays.
- Warning "GARCH model did not converge" at line 899 — stays.
- Warning "GARCH model fitting failed" at line 903 — stays.

**`abnormal_returns()` (lines 910–927):** checks `private$.is_fitted`. Emits `warning("GARCHModel is not fitted. Returning NA.")`. No `.degenerate_handled` suppression.
[VERIFIED: R/models.R:910-913]

**df counting:** `max(length(cond_sigma) - length(coefs), 1)` at line 947. This is GARCH-domain df (time series length minus parameters), not a count of finite residuals. KEEP AS-IS.
[VERIFIED: R/models.R:947]

**FEC:** Supported at lines 957–962. Uses `nrow(estimation_tbl)` (raw row count) as estimation_window_length. Should use `n_valid` (finite obs count) for correctness. This is MODELS-03/MODELS-04 territory — fix as part of migration.
[VERIFIED: R/models.R:957-962]

**requireNamespace guards:** Present at lines 857–860 for rugarch — correct. Leave untouched.
[VERIFIED: R/models.R:857-860]

**Required changes:**
1. Add insufficient-obs + zero-variance pre-call guards BEFORE `rugarch::ugarchspec()` at line 865, routed through `.handle_degenerate()`.
2. Add `.degenerate_handled` middle branch to `abnormal_returns()`.
3. Fix `nrow(estimation_tbl)` → `n_valid` in FEC call at line 959.

---

### 1.11 DCCGARCHModel

**File:** `R/models_time_varying.R:177–347`
**Status:** Needs migration (pre-call guards only).

**Current state:** No pre-call guards. `fit()` (lines 201–260) checks `requireNamespace("rmgarch")` and `requireNamespace("rugarch")`, then directly builds `returns_mat` and calls `rmgarch::dccfit()`.
[VERIFIED: R/models_time_varying.R:201-237]

**Special condition for DCC:** DCC-GARCH requires a bivariate series — both `firm_returns` and `index_returns`. The model needs at least GARCH(1,1) minimum obs (typically > 30, but contract minimum is 2) for the univariate sub-models to converge. The pre-call contract guard uses the same `n_valid < 2` threshold for consistency (the Phase 3 convergence wrapping will catch actual non-convergence).

**Phase 2 boundary:** Add BEFORE `returns_mat <- cbind(...)` at line 214:
1. Insufficient-obs guard on joint (firm_returns, index_returns) finite obs.
2. Zero-variance guard on BOTH series: if either `sd(estimation_tbl$firm_returns) < eps` or `sd(estimation_tbl$index_returns) < eps`, DCC-GARCH is degenerate (the univariate GARCH sub-model for that series is degenerate).

**Existing failure handling (LEAVE UNTOUCHED — Phase 3):**
- `purrr::safely(rmgarch::dccfit)` at line 236.
- `rcov(res$result)` convergence check at lines 244–247.
- Warning "DCC-GARCH model produced non-finite covariance" at line 253.
- Warning "DCC-GARCH fitting failed" at line 259.
[VERIFIED: R/models_time_varying.R:236-260]

**`abnormal_returns()` (lines 266–280):** checks `private$.is_fitted`. Emits `warning("DCCGARCHModel is not fitted. Returning NA.")`. No `.degenerate_handled` suppression.
[VERIFIED: R/models_time_varying.R:266-270]

**df counting:** `max(n_t - 4, 1)` at line 324 — GARCH domain df. KEEP AS-IS.
[VERIFIED: R/models_time_varying.R:324]

**FEC:** Supported at lines 337–344.
[VERIFIED: R/models_time_varying.R:337-344]

**requireNamespace guards:** Present at lines 202–209 for both rmgarch and rugarch. KEEP UNTOUCHED.
[VERIFIED: R/models_time_varying.R:202-209]

**Required changes:**
1. Add pre-call guards (insufficient-obs + zero-variance for BOTH series) BEFORE `returns_mat <- cbind(...)` at line 214, routed through `.handle_degenerate()`.
2. Add `.degenerate_handled` middle branch to `abnormal_returns()`.

---

## 2. MarketModel Exemplar Signature (exact template for replication)

The planner should specify "replicate this structure" for each model. The three-guard pattern from `R/models.R:176–236`:

```r
fit = function(data_tbl) {
  estimation_tbl <- data_tbl %>% dplyr::filter(estimation_window == 1)

  # 1. Resolve mode once per fit call
  mode <- .resolve_degenerate_mode(self$degenerate_mode)

  # 2. Insufficient-obs guard
  n_valid <- sum(!is.na(estimation_tbl$firm_returns) &
                  !is.na(estimation_tbl$index_returns))
  if (n_valid < 2) {
    .handle_degenerate(
      mode        = mode,
      condition   = paste0("insufficient estimation observations (", n_valid, " valid, need 2)"),
      component   = self$model_name,
      event_id    = self$event_id,
      firm_symbol = self$firm_symbol,
      private_env = private
    )
    private$.is_fitted <- FALSE        # explicit; required in lenient mode
    return(invisible(self))
  }

  # 3. Zero-variance guard
  if (stats::sd(estimation_tbl$index_returns, na.rm = TRUE) < .Machine$double.eps) {
    .handle_degenerate(
      mode        = mode,
      condition   = "zero or near-zero variance in index_returns",
      component   = self$model_name,
      event_id    = self$event_id,
      firm_symbol = self$firm_symbol,
      private_env = private
    )
    private$.is_fitted <- FALSE
    return(invisible(self))
  }

  # 4. Safe external/OLS call (optional, model-specific)
  safe_mm <- purrr::safely(.f = .estimate_mm_model)
  res <- safe_mm(self$formula, estimation_tbl)
  if (is.null(res$error)) {
    # success path
  } else {
    .handle_degenerate(
      mode        = mode,
      condition   = conditionMessage(res$error),
      component   = self$model_name,
      event_id    = self$event_id,
      firm_symbol = self$firm_symbol,
      private_env = private
    )
    private$.is_fitted <- FALSE
    private$.error <- res$error
  }
}
```
[VERIFIED: R/models.R:176-236]

**`.degenerate_handled` pattern in `abnormal_returns()`** — three-branch from `R/models.R:243–261`:
```r
abnormal_returns = function(data_tbl) {
  if (private$.is_fitted) {
    # normal computation
  } else if (private$.degenerate_handled) {
    # contract already emitted one warning; suppress redundant warning
    data_tbl %>% mutate(abnormal_returns = NA_real_)
  } else {
    # legitimate not-fitted (user called before fit, or non-contract failure)
    warning(self$model_name, " is not fitted. Returning NA abnormal returns.")
    data_tbl %>% mutate(abnormal_returns = NA_real_)
  }
}
```
[VERIFIED: R/models.R:243-261]

---

## 3. Finite-df Helper (MODELS-03)

**Current state:** MarketModel uses `mod$df.residual` (lm's own df — correct). LinearFactorModel uses `mod$df.residual` (correct). MarketAdjusted, ComparisonPeriodMean, and Volume already use `sum(!is.na(...))/sum(is.finite(...)) - 1` (correct). BHARModel uses `nrow(estimation_tbl) - 1` (incorrect — counts NA rows). RollingWindow uses `ws - 2` (correct for the rolling domain — do not change). GARCHModel and DCCGARCHModel use time-series domain df (correct — do not change). VolatilityModel uses `sum(is.finite(residuals)) - 1` (correct).

**Only BHARModel has the broken df:** `nrow(estimation_tbl) - 1` at line 1037.
[VERIFIED: R/models.R:1037]

**Recommendation for shared helper in `R/contract.R`:**
```r
#' @noRd
.finite_residual_df <- function(residuals, n_params = 1L) {
  # Returns n_finite_residuals - n_params, floored at 1
  max(sum(is.finite(residuals)) - as.integer(n_params), 1L)
}
```

- BHARModel: call `.finite_residual_df(residuals, n_params = 1L)` (one fitted parameter: the mean).
- MarketAdjusted and ComparisonPeriodMean already compute this inline correctly; can optionally adopt the helper for consistency.
- All lm-based models use `mod$df.residual` which is already correct.

---

## 4. Forecast-Error Correction (FEC) Support Map (MODELS-04)

| Model | FEC Supported | FEC Type | Notes |
|-------|--------------|----------|-------|
| MarketModel | YES | OLS-based FEC via `calculate_forecast_error_correction()` | Already correct; uses n_valid for estimation_window_length |
| MarketAdjustedModel | YES | Constant-mean FEC | Uses `nrow(estimation_tbl)` — minor gap, MODELS-03 level fix |
| ComparisonPeriodMeanAdjustedModel | YES | Constant-mean FEC | Uses `nrow(estimation_tbl)` — same minor gap |
| CustomModel | YES | Inherited from MarketModel | Free |
| LinearFactorModel | YES | Full multi-factor `(X'X)^{-1}` hat-value FEC | Already correct at R/models.R:650-682 |
| FF3/FF5/Carhart4 | YES | Inherited from LinearFactorModel | Free |
| BHARModel | YES | Constant-mean FEC | Uses `nrow(estimation_tbl)` — MODELS-03 fix needed |
| VolumeModel | YES | Constant-mean FEC | Uses `sum(is.finite(residuals))` — already correct |
| VolatilityModel | YES | Constant-mean FEC | Uses `sum(is.finite(residuals))` — already correct |
| RollingWindowModel | YES | OLS-based FEC via last window params | Uses `ws` (window size) — correct for rolling domain |
| GARCHModel | YES | OLS-style FEC via `calculate_forecast_error_correction()` | Uses `nrow(estimation_tbl)` — should use n_valid |
| DCCGARCHModel | YES | OLS-style FEC via `calculate_forecast_error_correction()` | Uses `nrow(estimation_tbl)` — same gap |

**Models with NO FEC:** None — all 12 models compute FEC.

**Conclusion:** Apply FEC to all models (all already have it). Fix the `nrow(estimation_tbl)` → `n_valid` gap in GARCHModel and DCCGARCHModel FEC calls as part of their migration.

---

## 5. Test Statistics Verification Scope

### 5.1 Multi-Event Stats — Event_id Join Verification (STATS-02)

All joins confirmed:

| Statistic | Join Key | Confirmed |
|-----------|----------|-----------|
| CSectTTest | event_id (via group_by(event_id) for sd_caar) | [VERIFIED: R/multi_event_test_statistics.R:43-46] |
| PatellZTest | event_id | [VERIFIED: R/multi_event_test_statistics.R:108-136] |
| BMPTest | event_id | [VERIFIED: R/multi_event_test_statistics.R:413-419] |
| KolariPynnonenTest | event_id | [VERIFIED: R/multi_event_test_statistics.R:570-574] |
| SignTest | event_id (group_by(event_id) for cum_sign) | [VERIFIED: R/multi_event_test_statistics.R:215-216] |
| GeneralizedSignTest | firm_symbol (p_hat estimation) then event_id for event window | Intentional: p_hat is estimated per firm, not per event; join for event-window stats uses group_by(relative_index) not a join on firm_symbol. No many-to-many risk. [VERIFIED: R/multi_event_test_statistics.R:257-263] |
| RankTest | firm_symbol for ranking within firm | Intentional: Corrado's rank test ranks within firm across the combined window; this is correct algorithm, not a many-to-many join bug. [VERIFIED: R/multi_event_test_statistics.R:342-348] |
| CalendarTimePortfolioTest | No join (group_by relative_index only) | [VERIFIED: R/multi_event_test_statistics.R:492-504] |

**Conclusion:** No join correctness issues remain. Phase 2 work is regression tests, not code rewrites.

### 5.2 NA-Safe Cumsum Chains (STATS-03)

`coalesce(x, 0)` pattern confirmed in all multi-event cumsum chains:

| Statistic | Location | Pattern |
|-----------|----------|---------|
| CSectTTest CAAR | R/multi_event_test_statistics.R:50 | `cumsum(dplyr::coalesce(aar, 0))` [VERIFIED] |
| CSectTTest per-event CAR | R/multi_event_test_statistics.R:44 | `cumsum(dplyr::coalesce(abnormal_returns, 0))` [VERIFIED] |
| PatellZTest per-event CSAR | R/multi_event_test_statistics.R:157 | `cumsum(dplyr::coalesce(standardized_abnormal_returns, 0))` [VERIFIED] |
| SignTest CAAR | R/multi_event_test_statistics.R:209 | `cumsum(dplyr::coalesce(aar, 0))` [VERIFIED] |
| SignTest per-event CAR | R/multi_event_test_statistics.R:217 | `cumsum(dplyr::coalesce(abnormal_returns, 0))` [VERIFIED] |
| BMPTest CSAR | R/multi_event_test_statistics.R:444 | `cumsum(dplyr::coalesce(sar, 0))` [VERIFIED] |
| BMPTest CAAR | R/multi_event_test_statistics.R:438 | `cumsum(dplyr::coalesce(aar, 0))` [VERIFIED] |
| KolariPynnonenTest CSAR | R/multi_event_test_statistics.R:598 | `cumsum(dplyr::coalesce(sar, 0))` [VERIFIED] |
| KolariPynnonenTest CAAR | R/multi_event_test_statistics.R:592 | `cumsum(dplyr::coalesce(aar, 0))` [VERIFIED] |
| CalendarTimePortfolioTest | R/multi_event_test_statistics.R:513 | `cumsum(dplyr::coalesce(aar, 0))` [VERIFIED] |

**Conclusion:** Pattern is uniformly applied. Work is regression tests only.

### 5.3 Denominator Guards — Single-Event Stats (STATS-01)

**ARTTest** (`R/single_event_test_statistics.R:64–76`):
```r
sigma = statistics$sigma %||% NA_real_
degree_of_freedom = max(statistics$degree_of_freedom %||% 1, 1)
...
ar_t = abnormal_returns / sigma
```
[VERIFIED: R/single_event_test_statistics.R:66-72]

**Problem:** If sigma=0 (not NA), `ar_t = AR / 0 = Inf`. The `%||% NA_real_` only handles NULL, not zero. Need guard: `if (is.na(sigma) || sigma < .Machine$double.eps) NA_real_ else abnormal_returns / sigma`.

**CARTTest** (`R/single_event_test_statistics.R:105–127`):
```r
sigma = statistics$sigma %||% NA_real_
...
car   = cumsum(abnormal_returns),
car_t = car / (sqrt(event_window_length) * sigma),
car_t_dist = distributional::dist_student_t(
  df    = degree_of_freedom,
  mu    = car,
  sigma = pmax(sqrt(event_window_length) * sigma, .Machine$double.eps)
)
```
[VERIFIED: R/single_event_test_statistics.R:107-122]

`car_t` denominator is `sqrt(event_window_length) * sigma`. If sigma=0, this is 0, yielding Inf. The `dist_student_t` sigma uses `pmax(..., .Machine$double.eps)` which prevents the distribution construction from crashing — but `car_t` itself is unguarded. Fix: wrap `car_t` in `ifelse(is.na(sigma) | sigma < .Machine$double.eps, NA_real_, ...)`.

Note: `cumsum(abnormal_returns)` without coalesce — if abnormal_returns contains NA (degenerate model), this propagates NA through all subsequent CARs. This is correct behavior (NA cascade), not a bug.

**BHARTTest** (`R/single_event_test_statistics.R:167–193`):
```r
sigma <- statistics$sigma %||% NA_real_
...
bhar_se <- sigma * sqrt(n)
bhar_t  <- bhar / bhar_se
```
[VERIFIED: R/single_event_test_statistics.R:169-191]

`bhar_se = sigma * sqrt(n)`. If sigma=NA, `bhar_se = NA`, `bhar_t = NA` — this is CORRECT (NA propagates). If sigma=0, `bhar_se = 0`, `bhar_t = Inf` — this is the bug. Guard: `ifelse(is.na(bhar_se) | bhar_se < .Machine$double.eps, NA_real_, bhar / bhar_se)`.

### 5.4 Denominator Guards — Multi-Event Stats (STATS-04)

**CSectTTest — n_events == 1:**
`aar_t` guard at `R/multi_event_test_statistics.R:33–36`:
```r
aar_t = {
  sd_ar <- sd(abnormal_returns, na.rm = TRUE)
  if (is.finite(sd_ar) && sd_ar > 0) sqrt(n_valid_events) * aar / sd_ar else NA_real_
}
```
[VERIFIED: R/multi_event_test_statistics.R:33-36]

When n_events==1: `sd_ar = NA` (sd of a single value), so `is.finite(NA)` → FALSE → returns NA_real_. **Already correct.**

`caar_t` guard at line 52:
```r
caar_t = ifelse(is.finite(sd_caar) & sd_caar > 0, ...)
```
[VERIFIED: R/multi_event_test_statistics.R:52]

When n_events==1: sd_caar is sd of a single CAR = NA → returns NA. **Already correct.**

**PatellZTest — n_events == 1:**
`Q_total = sqrt(sum(sd_asar$Q_i))` at `R/multi_event_test_statistics.R:140`.
[VERIFIED: R/multi_event_test_statistics.R:140]

When n_events==1: Q_i = `(m - k_param) / (m - k_param - 2)`. Q_total = sqrt(Q_i) > 0. Then `aar_z = sum_sar / Q_total`. This is mathematically defined (not Inf) — but it's a z-test with N=1, which is statistically invalid. However, it returns a finite number rather than crashing. The CONTEXT.md asks for NA when n_events==1. **Gap: need `if (nrow(sd_asar) == 1) return NA_real_` guard or `ifelse(n_valid_events <= 1, NA_real_, aar_z)` in the summarise.**

**BMPTest — n_events == 1:**
`bmp_t = ifelse(is.finite(sd_sar) & sd_sar > 0, sqrt(n_valid_events) * mean_sar / sd_sar, NA_real_)` at line 433.
[VERIFIED: R/multi_event_test_statistics.R:433-435]

When n_events==1: `sd_sar = NA` (sd of single value) → NA_real_. **Already correct.**

**SignTest — n_events == 1:**
`sign_z = ifelse(n_valid_events > 0, (n_pos - 0.5*n_valid_events) / (0.5 * sqrt(n_valid_events)), NA_real_)` at lines 206–208.
[VERIFIED: R/multi_event_test_statistics.R:206-208]

When n_events==1: `n_valid_events=1`, `sign_z = (n_pos - 0.5) / (0.5 * sqrt(1))`. This is defined (0.5/0.5=1 or −0.5/0.5=−1) but a sign test with N=1 is statistically invalid. Need guard for `n_valid_events < 2`.

**KolariPynnonenTest — n_events == 1:**
`r_bar` computation: `if (n_firms >= 2)` at line 631. When n_firms==1 (n_events==1): `r_bar = 0`. Then `kp_adj = sqrt((1-0)/(1+0)) = 1`. `kp_t = bmp_t * 1 = bmp_t`. But bmp_t is NA_real_ when n_events==1 (from the guard above). So KP returns NA when events==1. **Already correct.**

**Summary of STATS-04 gaps:**
- PatellZTest: `aar_z` / `caar_z` when n_events == 1 returns a (statistically invalid) finite number — needs `n_valid_events <= 1 → NA_real_` guard.
- SignTest: `sign_z` when n_events == 1 returns a finite number — needs `n_valid_events < 2 → NA_real_` guard.

---

## 6. External-Model Boundary

### GARCHModel

The rugarch call boundary is `R/models.R:865` (`rugarch::ugarchspec()`). Phase 2 guards insert BEFORE line 865. The `purrr::safely(rugarch::ugarchfit)` at line 878 and its result handling at lines 886–904 are Phase 3 territory — untouched.

**Exact insertion point:**
```r
# --- INSERT Phase 2 guards here (before ugarchspec) ---
# lines 857-864: requireNamespace check + estimation_tbl extraction
# line 865: estimation_tbl <- data_tbl %>% dplyr::filter(estimation_window == 1)
# NEW: n_valid check, then zero-variance check, then .handle_degenerate calls
# line 865+: spec <- rugarch::ugarchspec(...)
```
[VERIFIED: R/models.R:857-878]

### DCCGARCHModel

The rmgarch call boundary is `R/models_time_varying.R:236` (`rmgarch::dccfit()`). Phase 2 guards insert BEFORE the `returns_mat <- cbind(...)` at line 214. The `purrr::safely(rmgarch::dccfit)` at line 236 and result handling at lines 239–260 are Phase 3 territory.

**Exact insertion point:**
```r
# lines 202-212: requireNamespace checks + estimation_tbl extraction
# line 214: returns_mat <- cbind(estimation_tbl$firm_returns, estimation_tbl$index_returns)
# NEW: n_valid + zero-variance on both series + .handle_degenerate before returns_mat
# line 214+: returns_mat <- cbind(...)
```
[VERIFIED: R/models_time_varying.R:202-236]

---

## 7. Test Infrastructure and Baselines

### 7.1 Existing Factories in `helper-mock-data.R`

| Factory | Produces | Usable for |
|---------|----------|-----------|
| `create_mock_model_data(n_estimation, n_event)` | Standard firm_returns/index_returns data | All OLS-based models [VERIFIED: tests/testthat/helper-mock-data.R:138-152] |
| `create_degenerate_model_data_insufficient(n_valid, n_event)` | Estimation window with <2 valid obs | MarketAdjusted, ComparisonPeriodMean, LinearFactor, BHAR, GARCH [VERIFIED: tests/testthat/helper-mock-data.R:164-175] |
| `create_degenerate_model_data_zero_variance(n_event)` | Estimation window with constant index_returns | MarketAdjusted, LinearFactor, GARCH, DCCGARCHModel [VERIFIED: tests/testthat/helper-mock-data.R:185-191] |
| `create_mock_task_with_factors()` | Task with factor columns (smb, hml, mom, rmw, cma, risk_free_rate) | FF3/FF5/Carhart4 integration tests [VERIFIED: tests/testthat/helper-mock-data.R:103-126] |

### 7.2 New Factories Needed

| Factory | For | What it provides |
|---------|-----|-----------------|
| `create_degenerate_volume_model_data_insufficient(n_valid)` | VolumeModel | `firm_volume` column with <2 valid entries in estimation window |
| `create_degenerate_volume_model_data_zero_variance()` | VolumeModel | `firm_volume` all-identical in estimation window → sd=0 after log |
| `create_degenerate_volatility_model_data_zero_var()` | VolatilityModel | All `firm_returns` = constant in estimation window → var=0 |
| `create_mock_factor_model_data(n_estimation, n_event)` | LinearFactor/FF3/FF5/Carhart4 direct model tests | Flat tibble with required columns (excess_return, market_excess, smb, hml, mom, rmw, cma, estimation_window, event_window) |

### 7.3 Per-Model Valid-Input Baselines (CONTRACT-05 per model)

Phase 1 used `.rds` fixture approach — one file `tests/testthat/fixtures/contract05_baseline.rds`. Phase 2 should create per-model fixtures following the same naming: `tests/testthat/fixtures/contract05_<model>_baseline.rds`.

Models and suggested baselines:
| Fixture | Model | Key fields to snapshot |
|---------|-------|----------------------|
| `contract05_marketadjusted_baseline.rds` | MarketAdjustedModel | sigma, df, FEC[1:3], AR[1:5] |
| `contract05_comparisonperiod_baseline.rds` | ComparisonPeriodMeanAdjustedModel | sigma, df, FEC[1:3], AR[1:5] |
| `contract05_bhar_baseline.rds` | BHARModel | sigma, df, AR[1:5] (BHAR compound form) |
| `contract05_volume_baseline.rds` | VolumeModel | sigma, df, AR[1:5] |
| `contract05_volatility_baseline.rds` | VolatilityModel | sigma, df, AR[1:5] |
| `contract05_linearfactor_baseline.rds` | LinearFactorModel (FF3) | alpha, beta_smb, beta_hml, sigma, df, AR[1:5] |
| `contract05_rollingwindow_baseline.rds` | RollingWindowModel | alpha_last, beta_last, sigma_last, df, AR[1:5] |

GARCH and DCC-GARCH baselines should be marked as conditional on rugarch/rmgarch being available (skip if not installed).

---

## 8. Gotchas

### 8.1 VolatilityModel Guard Relocation (highest structural risk)

The zero-variance/NA-var guard currently lives inside `calculate_statistics()` (called after `private$.is_fitted <- TRUE`). Moving it into `fit()` BEFORE `private$.is_fitted <- TRUE` is semantically required by the contract but requires:
1. Computing `est_var <- var(estimation_tbl$firm_returns, na.rm=TRUE)` once in `fit()` before the is_fitted assignment.
2. Removing the guard from `calculate_statistics()`.
3. The move is safe because `calculate_statistics()` only runs when `fit()` falls through all guards.

**Risk:** Ensure `calculate_statistics()` is not called at all when `fit()` returns early. Current code: `fit()` calls `private$calculate_statistics(data_tbl)` at line 1172 — after is_fitted is set. If the guard is added before that call, the flow is: guard triggers → `.handle_degenerate()` → `return(invisible(self))` — `calculate_statistics()` never runs. Correct.
[VERIFIED: R/models.R:1165-1172]

### 8.2 CustomModel's `abnormal_returns()` Uses predict() on NULL

If MarketModel's `fit()` returns early (degenerate), `private$.fitted_model` remains NULL. CustomModel's `abnormal_returns()` calls `predict(mm_model, data_tbl)` unconditionally. `predict(NULL, ...)` in R produces an error, not NA. This is already covered by adding the `.degenerate_handled` guard — but the planner must ensure the guard is added BEFORE the `predict()` call.
[VERIFIED: R/models.R:489-496]

### 8.3 BHARModel's `abnormal_returns()` Returns "Wrong" Values When Not Fitted

BHARModel's `abnormal_returns()` (lines 1006–1017) uses `coalesce(firm_returns, 0)` and `coalesce(index_returns, 0)`, which silently computes a result (0 BHAR when all returns are 0-filled) even when is_fitted is FALSE. This is the most dangerous case: it returns *plausible-looking* wrong numbers rather than NA. The `.degenerate_handled` guard must be added first in `abnormal_returns()`.
[VERIFIED: R/models.R:1006-1017]

### 8.4 LinearFactorModel `fit()` Missing Column Stop() — Do Not Route Through `.handle_degenerate()`

The column-missing check at lines 537–541 uses a plain `stop()`. This is correct: missing required columns is a programming error, not a degenerate-input condition. Do NOT route it through `.handle_degenerate()`. Leave it as `stop()`.
[VERIFIED: R/models.R:537-541]

### 8.5 DCC-GARCH Requires 2+ Series — Both Can Be Degenerate

DCC-GARCH fails if EITHER firm_returns or index_returns has zero variance (the univariate GARCH for that series cannot converge). Both must be checked independently with separate `.handle_degenerate()` calls. The condition string should name which series triggered the guard.

### 8.6 Factor Model Subclasses Override `abnormal_returns()` — Each Needs the Middle Branch

FF3, FF5, and Carhart4 all override `abnormal_returns()` independently (the base class fix does NOT propagate to overrides). Each subclass `abnormal_returns()` must get the `.degenerate_handled` middle branch added. The subclass `fit()` methods do NOT override (they call `super$initialize()` but not `super$fit()`) — wait, verify:

Actually, FF3, FF5, Carhart4 each have their own `initialize()` but do NOT override `fit()`. Their `fit()` calls are inherited from LinearFactorModel. But `abnormal_returns()` IS overridden in all three (to use `excess_return` as the LHS column instead of `firm_returns`). So:
- `fit()` — inherited, one fix on LinearFactorModel base propagates to all three. [VERIFIED: R/models.R:722-731 (FF3 abnormal_returns overrides)]
- `abnormal_returns()` — overridden in all three; each needs its own patch.

### 8.7 GARCHModel FEC Uses `nrow(estimation_tbl)` — Degenerate Input Can Cause Inflated FEC

After adding the n_valid guard, if `n_valid < nrow(estimation_tbl)` (some rows have NA), the FEC call at line 959 still uses `nrow(estimation_tbl)` as `estimation_window_length`. Fix as part of migration: `n_valid` (computed in the guard) should be passed through to the FEC call.
[VERIFIED: R/models.R:957-962]

### 8.8 event_id Availability in Test Statistic Compute Methods

Test statistic `compute(data_tbl, model)` receives the unnested, flattened `data_tbl` (from `calculate_statistics()` in `execute.R`), which DOES contain `event_id` as a column (it was retained in the unnest at lines 125–134 of `execute.R`). This is confirmed by the existing `group_by(event_id)` calls in multi-event stats. No availability gap.
[VERIFIED: R/execute.R:125-134]

---

## 9. Migration Work Triaging (LOW / MEDIUM / HIGH effort)

| Model | Effort | Why |
|-------|--------|-----|
| MarketAdjustedModel | LOW | 1 guard, 1 return fix, 1 abnormal_returns patch |
| ComparisonPeriodMeanAdjustedModel | LOW | Same as MarketAdjusted |
| CustomModel | LOW | Only abnormal_returns guard needed; fit() is free |
| BHARModel | LOW-MEDIUM | 1 guard + df fix + critical abnormal_returns guard (dangerous false-output case) |
| VolumeModel | LOW-MEDIUM | 1 guard + abnormal_returns patch; new test factory needed |
| VolatilityModel | MEDIUM | Guard relocation from calculate_statistics() to fit() — structural change; new test factory |
| LinearFactorModel + 3 subclasses | MEDIUM | Base fix for fit(), 4× abnormal_returns patches (base + 3 subclasses), factor-data factory |
| RollingWindowModel | MEDIUM | 3 guard migrations + n_valid fix + abnormal_returns patch |
| GARCHModel | MEDIUM | Pre-call guards only, FEC n_valid fix, abnormal_returns patch; baseline conditional on rugarch |
| DCCGARCHModel | MEDIUM | Pre-call guards for 2 series, abnormal_returns patch; baseline conditional on rmgarch |

**Stats work effort:**
| Statistic | Effort | Why |
|-----------|--------|-----|
| ARTTest sigma==0 guard | LOW | 1 line ifelse change |
| CARTTest sigma==0 car_t guard | LOW | 1 line ifelse change |
| BHARTTest bhar_t guard | LOW | 1 line ifelse change |
| PatellZTest n_events==1 guard | LOW | 1 guard added to aar_z / caar_z mutate |
| SignTest n_events==1 guard | LOW | 1 guard in sign_z ifelse |
| STATS-02 regression tests (join correctness) | MEDIUM | Multiple test scenarios per statistic |
| STATS-03 regression test (mid-window drop) | LOW | 1 scenario per statistic using coalesce |

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mode dispatch | Custom if/else in each model | `.resolve_degenerate_mode()` + `.handle_degenerate()` from `R/contract.R` | Already built in Phase 1; consistent error messages |
| Warning deduplication | Second guard per model | `.degenerate_handled` flag already set by `.handle_degenerate()` | Flag is set inside `.handle_degenerate()` — no additional logic needed |
| df counting from lm | Custom sum(!is.na(...)) when lm is fitted | `mod$df.residual` | lm already tracks this exactly |
| FEC for OLS-based models | Custom formula | `private$calculate_forecast_error_correction()` from ModelBase | Already implemented for constant-mean and regression-based FEC |

---

## Common Pitfalls

### Pitfall 1: Setting `private$.is_fitted <- TRUE` Before Validating

**What goes wrong:** VolatilityModel sets `is_fitted = TRUE` in `fit()` before `calculate_statistics()` runs the guard. If `calculate_statistics()` then sets `is_fitted = FALSE`, the private flag is inconsistent and `.degenerate_handled` was never set — so `abnormal_returns()` falls through to the wrong warning branch.

**How to avoid:** All guards must precede `private$.is_fitted <- TRUE`. Add validation at the top of `fit()`.

### Pitfall 2: `return(invisible(NULL))` Instead of `return(invisible(self))`

**What goes wrong:** MarketAdjusted, ComparisonPeriodMean, BHAR, and Volume all return `invisible(NULL)` from the degenerate path. In an R6 method context, returning NULL means the result of `fit()` call is NULL (not the object). This is fine for the call site (execute.R calls `$fit()` for side effects), but it's inconsistent with the contract and the MarketModel exemplar.

**How to avoid:** Always `return(invisible(self))` from degenerate paths in R6 methods.

### Pitfall 3: Forgetting the Explicit `private$.is_fitted <- FALSE` After `.handle_degenerate()`

**What goes wrong:** `.handle_degenerate()` sets `private_env$.is_fitted <- FALSE` via the passed environment. But due to R's scoping, there is a subtle risk: if the caller's `private` environment differs from `private_env`. The Phase 1 decision was "defense in depth" — always set `private$.is_fitted <- FALSE` explicitly at the call site too.

**How to avoid:** Every `.handle_degenerate()` call site must be followed by `private$.is_fitted <- FALSE` and `return(invisible(self))` — even though `.handle_degenerate()` already sets it.

### Pitfall 4: Altering FEC Logic for External Models (Phase 3 Boundary Violation)

**What goes wrong:** Adding FEC fixes for GARCHModel/DCCGARCHModel might tempt modifying the `calculate_statistics()` private method, which also contains the convergence check and sigma extraction. Touching those parts is Phase 3 territory.

**How to avoid:** For GARCH/DCC-GARCH, ONLY change: (1) pre-call guards in `fit()` before the rugarch/rmgarch call, (2) the `estimation_window_length` argument in the FEC call, and (3) the `abnormal_returns()` degenerate_handled branch. Leave all `rugarch::*`/`rmgarch::*` calls and their tryCatch wrappers unchanged.

---

## Code Examples

### Replicated guard structure for a simple model (MarketAdjustedModel pattern)
```r
# R/models.R — MarketAdjustedModel$fit()
fit = function(data_tbl) {
  estimation_tbl <- data_tbl %>% dplyr::filter(estimation_window == 1)
  mode <- .resolve_degenerate_mode(self$degenerate_mode)

  n_valid <- sum(!is.na(estimation_tbl$firm_returns) &
                  !is.na(estimation_tbl$index_returns))
  if (n_valid < 2) {
    .handle_degenerate(
      mode        = mode,
      condition   = paste0("insufficient estimation observations (", n_valid, " valid, need 2)"),
      component   = self$model_name,
      event_id    = self$event_id,
      firm_symbol = self$firm_symbol,
      private_env = private
    )
    private$.is_fitted <- FALSE
    return(invisible(self))
  }

  # Zero-variance guard (firm - index residuals as proxy)
  if (sd(estimation_tbl$firm_returns - estimation_tbl$index_returns, na.rm = TRUE) < .Machine$double.eps) {
    .handle_degenerate(
      mode        = mode,
      condition   = "zero or near-zero variance in firm_returns - index_returns",
      component   = self$model_name,
      event_id    = self$event_id,
      firm_symbol = self$firm_symbol,
      private_env = private
    )
    private$.is_fitted <- FALSE
    return(invisible(self))
  }

  private$.is_fitted = TRUE
  private$calculate_statistics(data_tbl)
}
```

### Shared finite-df helper to add to `R/contract.R`
```r
#' @noRd
.finite_residual_df <- function(residuals, n_params = 1L) {
  max(sum(is.finite(residuals)) - as.integer(n_params), 1L)
}
```

---

## Environment Availability

Step 2.6: SKIPPED — Phase 2 is code-only changes within the existing R package stack. No new external tools, services, or runtimes are required beyond those already in the project (R 4.1.0+, devtools). rugarch and rmgarch are optional Suggests — code guards their use with `requireNamespace()` already in place.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | testthat 3.0.0+ |
| Config file | `tests/testthat.R` |
| Quick run command | `devtools::test(filter = "models")` |
| Full suite command | `devtools::test()` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| MODELS-01 | Each model routes degenerate conditions through `.handle_degenerate()` | unit | `devtools::test(filter = "models")` | New tests in `test_models.R` and `test_models_time_varying.R` |
| MODELS-02 | `.degenerate_handled` suppresses second warning in `abnormal_returns()` | unit | `devtools::test(filter = "models")` | Test: fit degenerate → call abnormal_returns → expect 0 additional warnings |
| MODELS-03 | Finite-df helper returns correct count for BHARModel | unit | `devtools::test(filter = "models")` | Compare with/without NA rows in estimation window |
| MODELS-04 | FEC fields populated for all models on valid input | unit | `devtools::test(filter = "models")` | Assert `!is.null(model$statistics$forecast_error_corrected_sigma)` |
| STATS-01 | sigma=0 → NA (not Inf) in ARTTest/CARTTest/BHARTTest | unit | `devtools::test(filter = "single_event")` | New test file or extend `test_single_event_statistics.R` |
| STATS-02 | Firm appearing in 2 events does not inflate BMP/KP/Patell denominators | regression | `devtools::test(filter = "multi_event")` | Extend `test_multi_event_statistics.R` |
| STATS-03 | NA gap mid-window → subsequent CARs correctly computed | regression | `devtools::test(filter = "multi_event")` | Extend `test_multi_event_statistics.R` |
| STATS-04 | n_events==1 yields NA in Patell aar_z / Sign sign_z | unit | `devtools::test(filter = "multi_event")` | New scenario in `test_multi_event_statistics.R` |

### Wave 0 Gaps
- New factories in `helper-mock-data.R`: `create_degenerate_volume_model_data_insufficient()`, `create_degenerate_volume_model_data_zero_variance()`, `create_degenerate_volatility_model_data_zero_var()`, `create_mock_factor_model_data()`
- Per-model baseline fixtures: `tests/testthat/fixtures/contract05_<model>_baseline.rds` (captured before migrating each model group)

---

## Security Domain

No new security-relevant code introduced in this phase. All changes are internal validation logic (guards, warnings, error messages). No new external calls, auth paths, file access, or network endpoints.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | LinearFactorModel$fit() is NOT overridden by FF3/FF5/Carhart4 (they only override initialize + abnormal_returns) | Per-model map §1.5 | If subclasses DO override fit(), fixing LinearFactorModel base won't propagate — each subclass needs its own guard |

Verification: The code confirms FF3/FF5/Carhart4 classes contain only `model_name`, `formula`, `required_columns`, `initialize`, and `abnormal_returns` in their `public` list — no `fit()` override. [VERIFIED: R/models.R:698-734, 746-782, 795-831]

**If this table is effectively empty after verification:** All other claims in this research were directly verified by reading the source files in this session.

---

## Open Questions

1. **Should zero-variance be added to ComparisonPeriodMean for `sd(firm_returns)` only (no index dependency)?**
   - What we know: ComparisonPeriodMean does not use index_returns in the AR formula; it subtracts the firm's own mean. Sigma=0 produces downstream Inf.
   - What's unclear: Is a zero-variance firm_returns a real scenario (e.g. price-controlled stocks)? The contract spec says "zero or near-zero variance" — it applies to any predictor that feeds into test statistics.
   - Recommendation: Add the guard. Condition string: "zero or near-zero variance in firm_returns (estimation window)".

2. **Should `GeneralizedSignTest` group-by-firm_symbol p_hat estimation change to event_id?**
   - What we know: `p_hat_by_firm` groups by `firm_symbol` at line 258. This is algorithm-correct: p_hat represents the firm's historical positivity rate, estimated from the firm's estimation window returns, regardless of how many events that firm participates in.
   - Recommendation: Leave as-is; document with a comment explaining the intentional firm_symbol grouping. Add a test verifying that a firm in 2 events produces a p_hat based on its estimation-window data, not a duplicated count.

3. **Should the valid-input baseline fixture for GARCHModel be conditional?**
   - What we know: Tests that require rugarch use `skip_if_not_installed("rugarch")`. Phase 1's `.rds` fixture approach doesn't need the package at load time.
   - Recommendation: Capture the GARCH baseline as code (not a pre-saved .rds) inside a `skip_if_not_installed("rugarch")` block; capture at test time and save, then compare on subsequent runs. This avoids checking in a binary .rds that requires rugarch to generate.

---

## Sources

### Primary (HIGH confidence)
All findings in this document are from direct `Read` tool calls in this session:
- `R/models.R` — complete read (1229 lines)
- `R/models_time_varying.R` — complete read (347 lines)
- `R/contract.R` — complete read (88 lines)
- `R/single_event_test_statistics.R` — complete read (196 lines)
- `R/multi_event_test_statistics.R` — complete read (668 lines)
- `R/execute.R` — complete read (186 lines)
- `tests/testthat/helper-mock-data.R` — complete read (192 lines)
- `.planning/phases/02-model-and-stats-sweep/02-CONTEXT.md`
- `.planning/phases/01-contract-foundation/01-01-SUMMARY.md`
- `.planning/codebase/CONCERNS.md`

### No web searches performed
All research findings are from direct codebase inspection.

---

## Metadata

**Confidence breakdown:**
- Per-model migration map: HIGH — all line numbers verified by direct read this session
- Test statistics scope: HIGH — all line numbers verified
- Architecture patterns: HIGH — Phase 1 summary + direct execute.R read

**Research date:** 2026-09-02
**Valid until:** Stable until any of the target files change. All citations include file:line so staleness is detectable by grep.
