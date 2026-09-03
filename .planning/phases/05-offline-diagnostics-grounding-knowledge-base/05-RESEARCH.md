# Phase 5: Offline Diagnostics + Grounding Knowledge Base - Research

**Researched:** 2026-09-03
**Domain:** R package extension — S3 diagnostics extraction, pure-R knowledge base, rule-based advice
**Confidence:** HIGH (all claims derive from direct codebase reads this session)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Return type:** S3-classed named list with class `es_diagnostics` (gives a `print`/`format` hook; matches success-criterion wording).
- **Serialization:** JSON-ready base-R list — structure stays lists/atomic vectors so it round-trips through `jsonlite` later, but the offline layer itself adds **no `jsonlite` dependency**.
- **Per-event payload cap:** keep the top-N most-anomalous events in full + an aggregate summary for the remainder (bounds token cost while preserving the events that matter for advice).
- **Cap default:** `max_events = 20`, overridable via argument.
- **KB storage:** in-package pure-R data structure (list of rule records) built at load — zero deps, fully unit-testable.
- **Rule record fields:** `id`, condition predicate (function of diagnostics), recommendation text, citation, severity.
- **Citation format:** structured (`author`, `year`, `key`) so the Phase 7 LLM layer can cite cleanly.
- **Multiple rules firing:** return all matched rules, severity-ranked (not first-match).
- **Function surface:** two exports — `recommend_stat()` and `flag_robustness()` (matches success criteria).
- **Return shape:** the same `Advice`-shaped object the LLM layer will reuse in Phase 7 (consistency across offline/online).
- **Accepted input:** either a fitted task or a precomputed `es_diagnostics` object.
- **No-provider behavior:** return grounded rule-based advice, flagged as deterministic/offline (never error just because no provider is configured).

### Claude's Discretion

- Exact internal anomaly-ranking metric for the top-N event cap, field naming within the diagnostics list, and the `Advice` object's internal field layout are at Claude's discretion, guided by codebase conventions and the Phase 7 consumption needs.

### Deferred Ideas (OUT OF SCOPE)

- LLM provider abstraction and `es_advise()` grounded interpretation → Phase 6 / Phase 7.
- Full retrieval-corpus ("Advisor Pro") grounding → future waitlist-gated milestone.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DIAG-01 | `es_diagnostics(task)` returns serializable named list (class `es_diagnostics`), zero new deps | S3 pattern from `es_simulation`/`es_cross_sectional`; base-R list suffices |
| DIAG-02 | Estimation-window fit signals (R², DW, Ljung-Box p, Shapiro-Wilk p, ACF1) from `R/diagnostics.R` | `model_diagnostics()` already computes all five; harvest via `purrr::pmap` over `task$data_tbl` |
| DIAG-03 | Event-window results (AR/CAR, AAR/CAAR, per-statistic values and p-values) | Per-event: `task$data_tbl$<StatName>` columns (tibbles); multi-event: `task$aar_caar_tbl$<StatName>` tibbles |
| DIAG-04 | Cross-sectional signals (n_events, n_valid_events, CAR dispersion/IQR, event-window overlap count) | All computable from existing data; overlap requires calendar-date interval check (see section below) |
| DIAG-05 | v0.50.0 contract state per event (is_fitted, NA counts, zero-variance/insufficient-obs flags) | `model$is_fitted` field; NA counts from `abnormal_returns` column; flag from `private$.degenerate_handled` — but degenerate_handled is private; derive from `!model$is_fitted` |
| DIAG-06 | Payload size-capped: top-N anomalous full + aggregate summary for remainder | Ranking by `abs(CAR at final event window day)` from per-event CART tibble; fallback to `abs(mean(AR))` when CAR unavailable |
| DIAG-07 | Runs without error on degenerate/NA events, no API key | All accessors already guard with `%||% NA_real_`; `tryCatch` wrappers needed around external calls |
| KB-01 | Assumption→test-statistic mapping as testable decision table | Literature-grounded table provided in this research |
| KB-02 | KB entries carry academic citations (MacKinlay 1997, BW 1985, Patell 1976, BMP 1991, KP 2010) | Citations verified against package description and existing code references |
| KB-03 | KB is pure-R data structure with unit tests asserting each rule fires on the correct diagnostic condition | Pattern: named list of rule records; tests use `recommend_stat(diag_fixture)` and check rule IDs |
| KB-04 | KB-04 deferred to Phase 7 (system prompt injection) | Out of scope for Phase 5 |
| ADV-08 | Non-LLM rule-based fallback for `recommend_stat` / `flag_robustness` driven by the KB decision table | `recommend_stat()` and `flag_robustness()` run the KB rule predicates and return all matches |
| CRAN-01 | Offline diagnostics add zero hard dependencies | Confirmed: all needed functions are base R or already in `Imports` |
| CRAN-05 | Existing pipeline behavior on valid input is unchanged (advisor is purely additive) | New functions are additive exports; no changes to existing functions |
</phase_requirements>

---

## Summary

Phase 5 adds a purely additive extraction and advice layer on top of the existing fitted `EventStudyTask`. The core work is threefold: (1) a single new function `es_diagnostics(task, max_events=20)` that harvests already-computed values from the task's nested tibbles and model statistics objects into a flat, serializable S3 list; (2) an in-package knowledge base (`EVENTSTUDY_KB`) as a named list of rule records mapping diagnostic conditions to grounded methodological recommendations with academic citations; and (3) two new exported functions `recommend_stat()` and `flag_robustness()` that run the KB predicates and return a structured `Advice` object.

All required diagnostic signals already exist in the fitted task — this phase does not recompute anything. Estimation-window signals come from `model$statistics` (sigma, r2, degree_of_freedom, residuals, first_order_auto_correlation) and the existing `model_diagnostics()` function in `R/diagnostics.R`. Event-window AR/CAR values live in `task$data_tbl$ART` and `task$data_tbl$CART` (tibbles stored in columns named after each test statistic's `$name` field). Multi-event AAR/CAAR results live in `task$aar_caar_tbl$CSectT` (and other stat-name columns). Contract state is read from `model$is_fitted` and NA counts from the `abnormal_returns` column in each nested `data` tibble.

**Primary recommendation:** Build `es_diagnostics()` as a thin, defensive harvester (all in `tryCatch`), then build the KB as a pure-R list loaded at package-load time, and keep `recommend_stat()` / `flag_robustness()` as simple predicate-evaluation loops. Zero new dependencies; no changes to any existing function.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Diagnostic extraction | New `R/es_diagnostics.R` | Reads `R/diagnostics.R` + task internals | Pure harvester; all computation already done |
| Knowledge base storage | New `R/kb.R` (package-level list) | — | Built at load; no runtime dep |
| Offline advice | New `R/advice.R` (`recommend_stat`, `flag_robustness`) | Consumes `es_diagnostics` object or task | Purely functional; no provider needed |
| Serialization (later) | Phase 7 LLM layer | `jsonlite` (Suggests) | Phase 5 only ensures the list is serializable |
| Test coverage | `tests/testthat/test_es_diagnostics.R`, `test_kb.R` | `helper-mock-data.R` (existing) | Testthat 3e; no new test infra |

---

## Accessor Paths — How to Reach Each Diagnostic Signal

### 1. Estimation-Window Fit Signals (DIAG-02)

The existing `model_diagnostics()` in `R/diagnostics.R` already computes all five signals. Do not reimplement — call it or replicate its access pattern:

**Direct model access path** (avoids re-running tests):
```r
# For each row i in task$data_tbl:
model  <- task$data_tbl$model[[i]]        # R6 ModelBase subclass
stats  <- model$statistics                 # private$.statistics accessed via active binding

stats$sigma                                # estimation residual std dev [VERIFIED: R/models.R:279]
stats$r2                                   # R-squared from summary(lm) [VERIFIED: R/models.R:280]
stats$degree_of_freedom                    # lm df.residual [VERIFIED: R/models.R:284]
stats$residuals                            # estimation window residuals [VERIFIED: R/models.R:311]
stats$first_order_auto_correlation         # ACF1, set by private$first_order_autocorrelation() [VERIFIED: R/models.R:113-118]
model$is_fitted                            # TRUE/FALSE (active binding on private$.is_fitted) [VERIFIED: R/models.R:57-63]
```

**Diagnostic test results** (Shapiro-Wilk, DW, Ljung-Box) come from `model$statistics$residuals` — `model_diagnostics()` computes them inline using base-R `shapiro.test()`, the custom DW formula, and `stats::Box.test()`. These are NOT stored in `model$statistics` — they must be (re)computed from the residuals vector.

The `model_diagnostics()` function iterates with `purrr::pmap` over `list(rows$event_id, rows$firm_symbol, rows$model, rows$data)` — see `R/diagnostics.R:24-26`. [VERIFIED: R/diagnostics.R:24-26]

**ACF1 field name:** `stats$first_order_auto_correlation` (not `acf1`). In `model_diagnostics()` it is exposed as column `acf1` via `stats$first_order_auto_correlation %||% NA_real_`. [VERIFIED: R/diagnostics.R:82, R/models.R:113]

**R² field name:** `stats$r2` (not `r_squared`). Set as `private$.statistics$r2 = modell_summary$r.squared`. [VERIFIED: R/models.R:280]

### 2. Event-Window Results (DIAG-03)

**Single-event AR/CAR** — stored as named tibble columns in `task$data_tbl` after `calculate_statistics()`:

```r
# After calculate_statistics(), task$data_tbl has columns named after each test's $name field.
# Default SingleEventStatisticsSet has: ARTTest (name='ART') and CARTTest (name='CART').
# Each column holds a tibble with per-event-window-day rows.

task$data_tbl$ART[[i]]   # tibble: relative_index, abnormal_returns, ar_t, ar_t_dist
task$data_tbl$CART[[i]]  # tibble: relative_index, abnormal_returns, event_window_length,
                          #         car_window, car, corrected_car, car_t, car_t_dist
```

Column `ART` and `CART` are created by the transpose step in `calculate_statistics()` (execute.R:99-112). [VERIFIED: R/execute.R:99-112]

**p-value access from distributional objects:** `ar_t_dist` and `car_t_dist` are `distributional::dist_student_t` objects. To extract a two-sided p-value use:
```r
# p-value for ar_t using the dist object:
2 * distributional::cdf(ar_t_dist, -abs(ar_t))   # or use stats::pt() with degree_of_freedom
```
Since `distributional` is in `Imports`, this is safe. Alternatively, use `stats::pt(abs(ar_t), df=degree_of_freedom, lower.tail=FALSE)*2`. [VERIFIED: DESCRIPTION:32-44]

**Summary CAR per event** (for ranking and dispersion): the final row of `task$data_tbl$CART[[i]]` gives the full-window CAR (last element of `car` column after filtering `event_window == 1`).

### 3. Multi-Event AAR/CAAR Results (DIAG-03, DIAG-04)

```r
# task$aar_caar_tbl is a tibble with columns: group, data, model, <StatName>...
# Default MultiEventStatisticsSet has: CSectTTest (name='CSectT').

task$aar_caar_tbl$CSectT[[g]]  # tibble per group g
# Columns: relative_index, aar, n_events, n_valid_events, n_pos, n_neg,
#           aar_t, caar, caar_t, car_window
```
[VERIFIED: R/multi_event_test_statistics.R:26-59]

For PatellZ: columns are `aar`, `n_events`, `n_valid_events`, `n_pos`, `n_neg`, `aar_z`, `caar`, `caar_z`, `car_window`. [VERIFIED: R/multi_event_test_statistics.R:152-186]

For BMP: columns are `aar`, `n_events`, `n_valid_events`, `n_pos`, `n_neg`, `mean_sar`, `sd_sar`, `bmp_t`, `caar`, `cbmp_t`, `car_window`. [VERIFIED: R/multi_event_test_statistics.R:449-487]

For KP: columns are `aar`, `n_events`, `n_valid_events`, `n_pos`, `n_neg`, `bmp_t`, `caar`, `cbmp_t`, `kp_t`, `ckp_t`, `car_window`. [VERIFIED: R/multi_event_test_statistics.R:603-691]

### 4. Cross-Sectional Signals (DIAG-04)

**n_events and n_valid_events:** available in every multi-event stat tibble at each `relative_index` row (e.g., `CSectT$n_events`, `CSectT$n_valid_events`). For the overall count: `nrow(task$data_tbl)` and count rows where `model$is_fitted == TRUE`. [VERIFIED: R/multi_event_test_statistics.R:28-31]

**CAR dispersion (IQR):** compute from the full-window CAR extracted from each per-event CART tibble:
```r
cars <- purrr::map_dbl(task$data_tbl$CART, function(t) {
  if (is.null(t) || !"car" %in% names(t)) return(NA_real_)
  tail(t$car, 1)  # last row = full-window CAR
})
car_iqr <- stats::IQR(cars, na.rm = TRUE)
car_sd  <- stats::sd(cars, na.rm = TRUE)
```

**Event-window overlap** (for Kolari-Pynnönen steering rule): two events overlap if their calendar-date event windows intersect. The event window for event i spans `[event_date_i + event_window_start_i, event_date_i + event_window_end_i]` in calendar days (relative indices are trading days, but dates in the nested `data` tibble are strings — filter `event_window == 1` and take `min(date)` / `max(date)` from the data tibble).

Practical approach — all calendar dates already exist in `task$data_tbl$data[[i]]` after `prepare_event_study()`:
```r
# Get actual event-window date ranges from the nested data
event_ranges <- purrr::imap_dfr(task$data_tbl$data, function(d, i) {
  ew <- d[d$event_window == 1, ]
  if (nrow(ew) == 0) return(tibble::tibble(idx=i, min_date=NA, max_date=NA))
  tibble::tibble(idx=i, min_date=min(ew$date), max_date=max(ew$date))
})
# Count overlapping pairs
n_overlap_pairs <- 0L
n <- nrow(event_ranges)
for (a in seq_len(n - 1)) {
  for (b in seq(a + 1, n)) {
    if (is.na(event_ranges$min_date[a]) || is.na(event_ranges$min_date[b])) next
    overlaps <- event_ranges$min_date[a] <= event_ranges$max_date[b] &&
                event_ranges$min_date[b] <= event_ranges$max_date[a]
    if (overlaps) n_overlap_pairs <- n_overlap_pairs + 1L
  }
}
```
Note: `date` in the nested data tibble is a **character string** in `"dd.mm.yyyy"` format (the format passed to `EventStudyTask$new()`). Convert with `as.Date(date, "%d.%m.%Y")` before comparison. [VERIFIED: R/task.R:64 (date column stored as-is); helper-mock-data.R:24 `format(dates, "%d.%m.%Y")`]

**Overlap summary signal:** a single integer `n_overlap_pairs` plus a boolean `any_overlap` (= `n_overlap_pairs > 0`).

### 5. Per-Event Contract State (DIAG-05)

```r
# For each row i in task$data_tbl:
model  <- task$data_tbl$model[[i]]
ev_data <- task$data_tbl$data[[i]]

is_fitted    <- model$is_fitted           # TRUE/FALSE [VERIFIED: R/models.R:57-63]
na_ar_count  <- sum(is.na(                # NA count in event window
  ev_data$abnormal_returns[ev_data$event_window == 1]
))
total_ar_obs <- sum(ev_data$event_window == 1)
```

**Zero-variance / insufficient-obs flags:** these are not directly stored as flags — they are the cause of `is_fitted == FALSE`. The specific cause is in the warning message text (emitted by `.handle_degenerate()`), not as a structured field. Therefore, `es_diagnostics()` can only expose the observable consequences:

- `is_fitted`: whether the model fitted successfully
- `na_ar_count` in event window: number of NA abnormal returns
- `na_est_count`: number of NA observations in estimation window

The specific degeneracy type (insufficient obs vs. zero variance) cannot be recovered from the fitted task without re-examining the data. The degenerate cause text IS captured in the warning, but warnings are not stored on the model object. **Recommendation:** derive `degenerate_type` from the data directly at `es_diagnostics()` time:

```r
# Check estimation window for degenerate conditions
est_data <- ev_data[ev_data$estimation_window == 1, ]
n_valid_est <- sum(!is.na(est_data$firm_returns) & !is.na(est_data$index_returns))
zero_var_index <- if (n_valid_est >= 2) {
  stats::sd(est_data$index_returns, na.rm = TRUE) < .Machine$double.eps
} else FALSE
insufficient_obs <- n_valid_est < 2
```
[VERIFIED: R/models.R:184-213 — these are the exact two guards in MarketModel$fit()]

---

## Standard Stack

### Core (no new packages)
| Component | Source | Location | Status |
|-----------|--------|----------|--------|
| `base` R lists / S3 class | R built-in | — | In `Imports` (base R) |
| `stats::shapiro.test`, `stats::Box.test`, `stats::sd`, `stats::IQR` | R stats package | — | In `Imports` |
| `purrr::map`, `purrr::pmap_dfr` | Already imported | `DESCRIPTION:36` | [VERIFIED: DESCRIPTION:36] |
| `dplyr::filter`, `dplyr::mutate`, `dplyr::summarise` | Already imported | `DESCRIPTION:34` | [VERIFIED: DESCRIPTION:34] |
| `tibble::tibble` | Already imported | `DESCRIPTION:33` | [VERIFIED: DESCRIPTION:33] |
| `rlang::%||%` | Already imported | `DESCRIPTION:40` | [VERIFIED: DESCRIPTION:40] |
| `distributional` (for p-value extraction from dist objects) | Already in `Imports` | `DESCRIPTION:32` | [VERIFIED: DESCRIPTION:32] |

**Installation:** No new `install.packages()` calls needed. Zero new hard dependencies.

### New Files to Create
| File | Purpose |
|------|---------|
| `R/es_diagnostics.R` | `es_diagnostics()` + `print.es_diagnostics()` exports |
| `R/kb.R` | `EVENTSTUDY_KB` list constant + `recommend_stat()` + `flag_robustness()` |
| `tests/testthat/test_es_diagnostics.R` | Testthat 3e tests for DIAG-* requirements |
| `tests/testthat/test_kb.R` | Testthat 3e tests for KB rule firing conditions |

### Package Legitimacy Audit

No external packages are being installed. All capabilities use existing `Imports`. This section is not applicable.

---

## Architecture Patterns

### System Architecture Diagram

```
Fitted EventStudyTask
        |
        v
  es_diagnostics(task, max_events=20)
        |
        |-- task$data_tbl$model[[i]]$statistics  --> estimation_window_signals
        |-- model_diagnostics() internals         --> shapiro_p, dw_stat, ljung_box_p, acf1
        |-- task$data_tbl$ART[[i]], CART[[i]]    --> per_event_results
        |-- task$aar_caar_tbl$CSectT[[g]], ...   --> cross_sectional_signals
        |-- data[event_window==1] date ranges     --> overlap_count
        |-- model$is_fitted, na counts            --> contract_state
        |
        +--> [rank by anomaly score] --------+
        |     top max_events get full detail  |
        |     remainder → aggregate summary   |
        v                                     v
  es_diagnostics S3 list (JSON-ready)    [dropped to aggregate]
        |
        v
  recommend_stat(diag) / flag_robustness(diag)
        |
        v
  [iterate EVENTSTUDY_KB rules]
  [evaluate condition(diag) for each rule]
  [collect matching rules, severity-rank]
        |
        v
  Advice S3 list {
    source: "offline_kb",
    rules_matched: [ {id, recommendation, citation, severity}, ... ],
    is_deterministic: TRUE
  }
```

### Recommended Project Structure (additions only)

```
R/
├── es_diagnostics.R     # es_diagnostics() + print.es_diagnostics() + .rank_events()
├── kb.R                 # EVENTSTUDY_KB list + recommend_stat() + flag_robustness()
tests/testthat/
├── test_es_diagnostics.R
└── test_kb.R
```

### Pattern 1: S3-Classed Named List (existing package convention)

The package already uses this exact pattern for `es_simulation` and `es_cross_sectional`:

```r
# From R/simulation.R:125-141 [VERIFIED: R/simulation.R:125-141]
result <- list(
  power = power,
  params = list(...)
)
class(result) <- "es_simulation"

# Print method [VERIFIED: R/simulation.R:146-157]
#' @export
print.es_simulation <- function(x, ...) {
  cat("Event Study Simulation\n")
  cat("  Power (day 0):  ", round(x$power, 4), "\n")
  invisible(x)
}
```

Apply the same pattern for `es_diagnostics`:
```r
result <- list(
  meta           = list(n_events_total=..., n_events_shown=..., n_events_summarized=...),
  estimation_window = list(...),    # per-event, top-N only
  event_window      = list(...),    # per-event, top-N only
  cross_sectional   = list(...),    # aggregate across all events
  contract_state    = list(...),    # per-event, top-N only
  aggregate_summary = list(...)     # summary for remainder events beyond top-N
)
class(result) <- "es_diagnostics"
```

### Pattern 2: KB Rule Record Structure

```r
# In R/kb.R — built at package load time, not lazily
EVENTSTUDY_KB <- list(
  list(
    id = "KB-NORM-PATELL",
    condition = function(diag) {
      # Shapiro-Wilk p > 0.05 in most events → normality holds → Patell is valid
      sw_vals <- diag$estimation_window$shapiro_p
      mean(sw_vals > 0.05, na.rm = TRUE) >= 0.7
    },
    recommendation = "Estimation-window residuals appear approximately normal. Patell Z is appropriate.",
    citation = list(author = "Patell", year = 1976, key = "Patell1976"),
    severity = "info"
  ),
  list(
    id = "KB-NONNORM-NONPAR",
    condition = function(diag) {
      sw_vals <- diag$estimation_window$shapiro_p
      mean(sw_vals < 0.05, na.rm = TRUE) >= 0.5
    },
    recommendation = "Non-normality detected in estimation-window residuals for the majority of events. Consider Sign Test or Rank Test (Corrado 1989) as non-parametric alternatives.",
    citation = list(author = "Brown & Warner", year = 1985, key = "BrownWarner1985"),
    severity = "warning"
  )
  # ... additional rules
)
```

### Pattern 3: Advice Object Shape (Phase 7 compatible)

```r
# Advice S3 object — the same shape Phase 7 LLM layer will produce
advice <- list(
  source         = "offline_kb",    # or "llm_<provider>" in Phase 7
  is_deterministic = TRUE,
  rules_matched  = list(            # list of matched rule records
    list(
      id             = "KB-OVERLAP-KP",
      recommendation = "...",
      citation       = list(author="Kolari & Pynnönen", year=2010, key="KolariPynnonen2010"),
      severity       = "warning"
    )
  ),
  diagnostics_ref = diag            # or NULL if the caller passes raw task
)
class(advice) <- "es_advice"
```

### Anti-Patterns to Avoid

- **Recomputing anything:** `es_diagnostics()` is a harvester, not a calculator. All signals already exist. Recomputing (e.g., refitting the model) defeats the "no provider, no network" guarantee and risks side effects.
- **Storing distributional objects in the diagnostics list:** `ar_t_dist` objects are R environments — they are not JSON-serializable. Extract scalar p-values using `stats::pt()` with the stored `degree_of_freedom`.
- **Using `jsonlite` in the offline layer:** not in `Imports` (only `Suggests` will be added in Phase 6). The offline layer must produce a list that would survive `jsonlite::toJSON()` but must not call it.
- **First-match KB evaluation:** the locked decision says return all matched rules, severity-ranked. Do not `break` after first match.
- **Accessing `private$.degenerate_handled`:** this is a private field of R6 classes and cannot be read from outside. Derive degenerate state from `model$is_fitted` and re-examining the data.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Shapiro-Wilk test | Custom normality test | `stats::shapiro.test()` | Already in base R; `model_diagnostics()` already uses it |
| Durbin-Watson stat | Custom AC formula | Inline formula in `model_diagnostics()` (copy it) | Already implemented and tested; no `lmtest` dep needed |
| Ljung-Box test | Custom portmanteau | `stats::Box.test(..., type="Ljung-Box")` | Already in `model_diagnostics()` |
| ACF1 | Manual lag-1 correlation | `stats::acf(resid, lag.max=1, plot=FALSE)[[1]][,,1][2]` | Already in `ModelBase$private$first_order_autocorrelation()` |
| IQR of CARs | Manual percentile difference | `stats::IQR(cars, na.rm=TRUE)` | One-liner in base R |
| Event window overlap detection | Geospatial interval library | Base R interval comparison (see accessor section) | Simple nested loop; N events is small (≤ hundreds) |

**Key insight:** Everything needed to build the diagnostics object already exists in computed state. The implementation challenge is knowing exactly which field on which object holds which value — not the statistical computations themselves.

---

## Literature-Grounded KB Decision Table

This table maps each diagnostic condition to the test it steers toward, with the primary citation. Every mapping below is drawn from the cited papers' core claims.

| Rule ID | Diagnostic Condition | Steers Toward | Citation | Confidence |
|---------|---------------------|---------------|----------|------------|
| KB-NORM-PATELL | Shapiro-Wilk p > 0.05 in ≥ 70% of events (normality not rejected) | Patell Z is valid | Patell (1976) | [ASSUMED] threshold choice; direction [CITED: MacKinlay 1997 §4] |
| KB-NONNORM-NONPAR | Shapiro-Wilk p < 0.05 in ≥ 50% of events (normality rejected) | Sign Test or Rank Test (Corrado 1989) preferred | Brown & Warner (1985) §3; MacKinlay (1997) §4.4 | [ASSUMED] threshold; direction widely agreed |
| KB-VAR-INCREASE-BMP | Event-induced variance increase detected: `sd_sar` in event window >> 1 (expected=1 under H0) OR BMP t-stat notably > Patell z (divergence) | BMP over Patell Z | Boehmer, Musumeci & Poulsen (1991) — BMP is designed specifically for this case | [CITED: BMP 1991] |
| KB-OVERLAP-KP | `n_overlap_pairs > 0` (calendar-time event-window overlap detected) | Kolari-Pynnönen adjusted BMP | Kolari & Pynnönen (2010) — KP corrects for cross-sectional correlation from clustering | [CITED: KolariPynnonen2010, referenced in package KolariPynnonenTest roxygen] |
| KB-AC-WARN | DW statistic < 1.5 or > 2.5 (serial autocorrelation) | Use HAC standard errors (MarketModel use_hac=TRUE) or note caveat | Brown & Warner (1985) §2; MacKinlay (1997) §3.3 | [ASSUMED] thresholds |
| KB-LOWFIT-WARN | R² < 0.05 in the majority of events | Market model fit is poor; consider multi-factor or Market-Adjusted model | MacKinlay (1997) §3.1 — low R² inflates standard error | [ASSUMED] threshold; direction [CITED: MacKinlay 1997] |
| KB-DEGEN-EVENTS | `n_valid_events / n_events < 0.8` (many events not fitted) | Flag study reliability; degenerate events NA-propagated | Contract documentation in `R/contract.R` | [VERIFIED: R/contract.R:1-47] |
| KB-PRETREND | Pre-event AAR pattern shows systematic non-zero values (from `pretrend_test()`) | Model misspecification suspected; interpret CARs cautiously | MacKinlay (1997) §5 | [ASSUMED] operationalization |
| KB-SMALL-N | `n_valid_events < 10` at event date | Cross-sectional t loses power; non-parametric tests preferred | Brown & Warner (1985) — parametric tests require reasonable N | [ASSUMED] threshold |

**Citation provenance notes:**
- The package `DESCRIPTION` cites MacKinlay (1997) in its Description field. [VERIFIED: DESCRIPTION:13-14]
- The `KolariPynnonenTest` roxygen references "Kolari, J. W. and Pynnönen, S. (2010)". [VERIFIED: R/multi_event_test_statistics.R:569-572]
- The package description references Patell (1976) via "Standardized Residual Test". [ASSUMED — package description text not directly quoting Patell]
- BMP (Boehmer, Musumeci, Poulsen 1991) is documented in `BMPTest` class. [VERIFIED: R/multi_event_test_statistics.R:412-418]
- Specific p-value thresholds (0.05 for Shapiro-Wilk, proportions 0.5/0.7, DW bounds 1.5/2.5) are [ASSUMED] reasonable defaults for the KB. They must be documented as adjustable and confirmed with domain expert if needed.

---

## Anomaly Ranking for Top-N Event Cap (DIAG-06, Claude's Discretion)

**Recommended metric:** `abs(final_car)` where `final_car` is the CAR at the last day of the event window (last row of `task$data_tbl$CART[[i]]$car`). This directly measures the magnitude of the cumulative abnormal effect — the most relevant quantity for post-hoc inspection.

**Fallback when CART not computed:** use `abs(mean(task$data_tbl$data[[i]]$abnormal_returns, na.rm=TRUE))` for events where abnormal returns exist but no CART was run.

**Degenerate events** (`is_fitted == FALSE`): assign anomaly score = `Inf` so they always appear in the top-N (they are the most important to inspect). Break ties by original event_id order.

**Algorithm:**
```r
.rank_events <- function(task) {
  purrr::imap_dfr(seq_len(nrow(task$data_tbl)), function(i, ...) {
    model <- task$data_tbl$model[[i]]
    score <- if (!model$is_fitted) {
      Inf
    } else if ("CART" %in% names(task$data_tbl) && !is.null(task$data_tbl$CART[[i]])) {
      cart <- task$data_tbl$CART[[i]]
      abs(tail(cart$car, 1))
    } else {
      d <- task$data_tbl$data[[i]]
      abs(mean(d$abnormal_returns[d$event_window == 1], na.rm = TRUE))
    }
    tibble::tibble(row_idx = i, anomaly_score = score %||% 0)
  })
}
```

---

## S3 Print Method — Package Convention

The package convention from `es_simulation` and `es_cross_sectional`:
- Use `cat()` for formatted output (not `print()`).
- Summarize the key scalar signals at the top level.
- Use `invisible(x)` as final return.
- Export with `#' @export`.
- Function signature: `print.es_diagnostics <- function(x, ...)`.

Example skeleton:
```r
#' @export
print.es_diagnostics <- function(x, ...) {
  cat("Event Study Diagnostics\n")
  cat("=======================\n")
  cat("Events total:   ", x$meta$n_events_total, "\n")
  cat("Events shown:   ", x$meta$n_events_shown, "(full detail)\n")
  cat("Events valid:   ", x$cross_sectional$n_valid_events, "\n")
  cat("\nEstimation window (medians across shown events):\n")
  cat("  R-squared:    ", round(median(x$estimation_window$r2, na.rm=TRUE), 4), "\n")
  cat("  Shapiro-Wilk p:", round(median(x$estimation_window$shapiro_p, na.rm=TRUE), 4), "\n")
  cat("  DW statistic: ", round(median(x$estimation_window$dw_stat, na.rm=TRUE), 4), "\n")
  cat("\nEvent window (cross-sectional):\n")
  cat("  CAR IQR:       ", round(x$cross_sectional$car_iqr, 6), "\n")
  cat("  Overlap pairs: ", x$cross_sectional$n_overlap_pairs, "\n")
  invisible(x)
}
```

---

## Common Pitfalls

### Pitfall 1: Non-Serializable Objects in the Diagnostics List
**What goes wrong:** If `ar_t_dist` (a `distributional::dist_student_t` object, which is an S3 list backed by an R environment) is included in the `es_diagnostics` list, `jsonlite::toJSON()` in Phase 7 will fail or produce garbage.
**Why it happens:** `distributional` dist objects are environment-backed; they do not round-trip through JSON.
**How to avoid:** Extract scalar p-values using `stats::pt()` at `es_diagnostics()` time. Never store dist objects in the output list.
**Warning signs:** `jsonlite::toJSON(diag)` in a test throws an error like "cannot coerce class dist_student_t".

### Pitfall 2: NA Cascade When task$aar_caar_tbl is NULL
**What goes wrong:** `es_diagnostics()` crashes with "$ applied to non-existent field" if `calculate_statistics()` was not called (or was called with `multi_event_statistics=NULL`).
**Why it happens:** `task$aar_caar_tbl` is `NULL` unless `calculate_statistics()` populates it. [VERIFIED: R/task.R:16 `aar_caar_tbl = NULL`]
**How to avoid:** Guard with `if (!is.null(task$aar_caar_tbl))` before accessing it. The cross-sectional section of `es_diagnostics` should return `NA`s gracefully when multi-event stats were not computed.

### Pitfall 3: Stat Column Names Depend on the ParameterSet
**What goes wrong:** `task$data_tbl$ART` does not exist if the user passed `single_event_statistics=NULL` or used a custom `SingleEventStatisticsSet` with different test names.
**Why it happens:** Column names come from `test_statistic$name` — if the user substituted a custom test with a different name, the column will have that name. [VERIFIED: R/execute.R:158-163]
**How to avoid:** Check `"ART" %in% names(task$data_tbl)` (and similarly for other expected stat names) before accessing. Build a defensive accessor that checks available stat columns and harvests what it can.

### Pitfall 4: Date Format in Nested Data Tibble
**What goes wrong:** Calendar-date overlap computation fails with `NA` comparisons if dates are not converted before interval comparison.
**Why it happens:** `date` column in nested data tibble is a character string `"dd.mm.yyyy"`. Direct `<` / `>` comparison on strings gives lexicographic order (wrong for this format). [VERIFIED: helper-mock-data.R:24]
**How to avoid:** Always convert with `as.Date(date, "%d.%m.%Y")` before interval arithmetic.

### Pitfall 5: `model$statistics` Returns NULL Fields Before fit()
**What goes wrong:** `model$statistics$sigma` is `NULL` (not `NA_real_`) if the model was not fitted. Using `NULL` in arithmetic produces length-0 results silently.
**Why it happens:** `private$.statistics` is initialized with `list(sigma=NULL, ...)`. [VERIFIED: R/models.R:75-80]
**How to avoid:** Always apply `%||% NA_real_` when extracting any statistics field, exactly as done in `ARTTest$compute()`. [VERIFIED: R/single_event_test_statistics.R:66]

### Pitfall 6: Single-Event Task Has No aar_caar_tbl Stat Columns
**What goes wrong:** With only 1 event, `CSectTTest` is still run but produces a single-row tibble. `n_valid_events == 1` causes `aar_t = NA` (by design, STATS-04 guard). The KB must not treat `NA` stat values as evidence of a problem.
**Why it happens:** The STATS-04 guard in `CSectTTest` intentionally returns `NA_real_` for `n_valid_events <= 1`. [VERIFIED: R/multi_event_test_statistics.R:163-166]
**How to avoid:** In KB conditions, treat `NA` stat values as "insufficient data to evaluate" — do not fire robustness warnings based on NA values.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | testthat 3e |
| Config file | `Config/testthat/edition: 3` in DESCRIPTION |
| Quick run command | `testthat::test_file("tests/testthat/test_es_diagnostics.R")` |
| Full suite command | `devtools::test()` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DIAG-01 | `es_diagnostics()` returns S3-classed list | unit | `testthat::test_file("tests/testthat/test_es_diagnostics.R")` | No — Wave 0 |
| DIAG-02 | Estimation-window signals present and correct | unit | same | No — Wave 0 |
| DIAG-03 | Event-window AR/CAR values harvested correctly | unit | same | No — Wave 0 |
| DIAG-04 | Cross-sectional signals (n_events, IQR, overlap) | unit | same | No — Wave 0 |
| DIAG-05 | Contract state (is_fitted, NA counts, degenerate flags) | unit | same | No — Wave 0 |
| DIAG-06 | Cap at max_events=20, most-anomalous first | unit | same | No — Wave 0 |
| DIAG-07 | No error on degenerate/NA task | unit | same | No — Wave 0 |
| KB-01 | Decision table maps conditions to stats | unit | `testthat::test_file("tests/testthat/test_kb.R")` | No — Wave 0 |
| KB-02 | Each KB rule has valid citation fields | unit | same | No — Wave 0 |
| KB-03 | Each rule fires on correct diagnostic condition | unit | same | No — Wave 0 |
| ADV-08 | `recommend_stat()` / `flag_robustness()` return Advice without provider | unit | same | No — Wave 0 |
| CRAN-01 | `R CMD check` shows no new hard deps | integration | `devtools::check()` | N/A |
| CRAN-05 | Existing tests still green | regression | `devtools::test()` | Yes (1378 existing tests) |

### Sampling Rate
- **Per task commit:** `devtools::test(filter="es_diagnostics|kb")` (~new tests only)
- **Per wave merge:** `devtools::test()` (full suite)
- **Phase gate:** `devtools::check()` with zero new NOTEs/WARNINGs before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `tests/testthat/test_es_diagnostics.R` — covers DIAG-01 through DIAG-07
- [ ] `tests/testthat/test_kb.R` — covers KB-01 through KB-03 and ADV-08
- [ ] No new framework install needed (testthat 3e already configured)

---

## Environment Availability

Step 2.6: All capabilities are within the existing R package. No external tools, services, or CLIs needed beyond the standard R development workflow.

| Dependency | Required By | Available | Fallback |
|------------|------------|-----------|----------|
| R 4.1.0+ | All | Assumed (per DESCRIPTION) | — |
| devtools | Development | Assumed (development dependency) | — |
| testthat 3e | Testing | Yes (in Suggests, edition=3 configured) | — |
| roxygen2 7.3.3 | NAMESPACE | Yes (RoxygenNote in DESCRIPTION) | — |

---

## Security Domain

This phase introduces no network calls, no user-supplied data execution, and no secrets. Security considerations:

| ASVS Category | Applies | Note |
|---------------|---------|------|
| V5 Input Validation | Minimal | `es_diagnostics()` accepts `task` — type-check with `inherits(task, "EventStudyTask")`. Same pattern as `model_diagnostics()`. |
| V2, V3, V4, V6 | No | No authentication, sessions, access control, or cryptography |

---

## Code Examples

### Example: es_diagnostics() skeleton
```r
# Source: derived from R/diagnostics.R:24-88 and R/models.R:264-330 [VERIFIED]

#' @export
es_diagnostics <- function(task, max_events = 20L) {
  if (!inherits(task, "EventStudyTask")) {
    stop("task must be an EventStudyTask.", call. = FALSE)
  }
  if (!"model" %in% names(task$data_tbl)) {
    stop("Models have not been fitted. Run fit_model() first.", call. = FALSE)
  }

  n_total <- nrow(task$data_tbl)

  # Step 1: rank events by anomaly score
  ranking <- .rank_events_for_cap(task)
  top_idx <- ranking$row_idx[seq_len(min(max_events, n_total))]
  rest_idx <- ranking$row_idx[seq(min(max_events, n_total) + 1L, n_total)]

  # Step 2: extract per-event signals for top events
  est_signals <- .extract_estimation_signals(task, top_idx)
  ew_signals  <- .extract_event_window_signals(task, top_idx)
  contract    <- .extract_contract_state(task, top_idx)

  # Step 3: cross-sectional signals across ALL events
  cs_signals  <- .extract_cross_sectional_signals(task)

  # Step 4: aggregate summary for remainder
  agg_summary <- if (length(rest_idx) > 0) .aggregate_remainder(task, rest_idx) else NULL

  result <- list(
    meta = list(
      n_events_total     = n_total,
      n_events_shown     = length(top_idx),
      n_events_summarized = length(rest_idx),
      event_ids_shown    = task$data_tbl$event_id[top_idx]
    ),
    estimation_window   = est_signals,
    event_window        = ew_signals,
    cross_sectional     = cs_signals,
    contract_state      = contract,
    aggregate_summary   = agg_summary
  )
  class(result) <- "es_diagnostics"
  result
}
```

### Example: KB rule record structure
```r
# Source: locked decision from CONTEXT.md — pure-R list of rule records

EVENTSTUDY_KB <- list(
  list(
    id             = "KB-OVERLAP-KP",
    condition      = function(diag) {
      isTRUE(diag$cross_sectional$n_overlap_pairs > 0)
    },
    recommendation = paste0(
      "Event windows overlap in calendar time (", 
      "cross-sectional correlation of abnormal returns is likely). ",
      "Use the Kolari-Pynnönen adjusted BMP test rather than standard BMP or Patell Z."
    ),
    citation       = list(
      author = "Kolari, J.W. and Pynnönen, S.",
      year   = 2010L,
      key    = "KolariPynnonen2010",
      venue  = "Review of Financial Studies, 23(11), 3996-4025"
    ),
    severity       = "warning"
  ),
  list(
    id             = "KB-DEGEN-EVENTS",
    condition      = function(diag) {
      n_total <- diag$meta$n_events_total
      n_fitted <- diag$cross_sectional$n_valid_events
      isTRUE(n_total > 0 && (n_fitted / n_total) < 0.8)
    },
    recommendation = paste0(
      "More than 20% of events have degenerate estimation windows (insufficient data or ",
      "zero variance). Results may be unreliable. Inspect contract_state for details."
    ),
    citation       = list(
      author = "EventStudy package",
      year   = 2026L,
      key    = "DegenerateInputContract",
      venue  = "R/contract.R — degenerate-input-contract documentation"
    ),
    severity       = "error"
  )
  # ... additional rules
)
```

### Example: recommend_stat() skeleton
```r
#' @export
recommend_stat <- function(x, ...) UseMethod("recommend_stat")

#' @export
recommend_stat.EventStudyTask <- function(x, ...) {
  diag <- es_diagnostics(x, ...)
  recommend_stat.es_diagnostics(diag, ...)
}

#' @export
recommend_stat.es_diagnostics <- function(x, ...) {
  matched <- Filter(function(rule) {
    isTRUE(tryCatch(rule$condition(x), error = function(e) FALSE))
  }, EVENTSTUDY_KB)

  # Severity order: error > warning > info
  sev_order <- c(error=1L, warning=2L, info=3L)
  matched <- matched[order(sev_order[vapply(matched, `[[`, "", "severity")])]

  advice <- list(
    source           = "offline_kb",
    is_deterministic = TRUE,
    rules_matched    = matched
  )
  class(advice) <- "es_advice"
  advice
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Manual `model_diagnostics()` call + visual inspection | `es_diagnostics()` produces structured list for programmatic use | Enables KB evaluation and LLM consumption |
| No grounded recommendation layer | KB decision table with citations | Prevents LLM hallucination of methodology advice |
| Advice only available with LLM provider | Offline rule-based fallback | Works with no API key; consistent behavior |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Shapiro-Wilk threshold 0.05 is appropriate for KB normality rule | KB Decision Table | Rule fires in wrong conditions; easily adjusted at KB build time |
| A2 | Proportion thresholds (70% for "normality holds", 50% for "normality rejected") for KB firing | KB Decision Table | KB recommendation may be conservative or aggressive; tune based on user feedback |
| A3 | DW bounds 1.5/2.5 for autocorrelation warning | KB Decision Table | May over/under-warn; well-established heuristic in time series literature |
| A4 | R² < 0.05 threshold for low-fit warning | KB Decision Table | Threshold is arbitrary; document as adjustable |
| A5 | n_valid_events < 10 threshold for small-N warning | KB Decision Table | May suppress legitimate small-N studies; document as adjustable |
| A6 | `abs(final_car)` is the best anomaly-ranking metric for top-N cap | Anomaly Ranking | Alternative: smallest p-value; either is reasonable; this choice is at Claude's discretion |
| A7 | date column in nested data tibble is `"dd.mm.yyyy"` format for all cases | Overlap computation | If user passes dates in different format, `as.Date()` conversion will produce NA; needs defensive tryCatch |
| A8 | KB-04 (system prompt injection) is Phase 5 scope | Requirements table | Based on REQUIREMENTS.md Traceability — KB-04 is listed as Phase 5; but the CONTEXT.md does not mention it, and it requires the LLM layer. Planner should verify if KB-04's prompt-injection aspect belongs in Phase 5 or Phase 7 |

**If this table is empty:** it is not — eight assumptions need attention, particularly A8 (KB-04 scope).

---

## Open Questions

1. **KB-04 scope clarification**
   - What we know: REQUIREMENTS.md lists KB-04 ("The system prompt injects KB context to ground the LLM's methodological reasoning") as Phase 5.
   - What's unclear: Phase 5 has no LLM layer. KB-04 requires the provider abstraction (Phase 6) or the grounded advise layer (Phase 7) to be callable.
   - Recommendation: The KB data structure itself (KB-01 through KB-03) is definitely Phase 5. KB-04's injection behavior should be implemented in Phase 7 where `es_advise()` builds the system prompt. Planner should note this as a Phase 5 deliverable limited to "KB structure exists and is exported" — not "system prompt injection works."

2. **`recommend_stat` vs `flag_robustness` split**
   - What we know: Both are required exports. Both accept task or `es_diagnostics`.
   - What's unclear: The KB rules do not have an obvious `recommend_stat` vs `flag_robustness` partition. One natural split: `recommend_stat()` evaluates KB rules tagged as "methodology" (which stat to use); `flag_robustness()` evaluates rules tagged as "robustness" (data quality, overlap, degenerate events, autocorrelation).
   - Recommendation: Add a `category` field to each KB rule record (`"stat_choice"` vs `"robustness"`) and let each function filter by category. This is within Claude's discretion per CONTEXT.md.

3. **Degenerate events in top-N vs. aggregate summary**
   - What we know: degenerate events (`is_fitted==FALSE`) always rank first (anomaly_score=Inf).
   - What's unclear: If there are more than `max_events` degenerate events, some degenerate events will end up in the aggregate summary. Should all degenerate events always be shown in full?
   - Recommendation: Document this edge case in the function; the default `max_events=20` is generous enough for most real studies. Mention in `print.es_diagnostics` if any degenerate events were truncated.

---

## Sources

### Primary (HIGH confidence — verified by direct file reads this session)
- `R/diagnostics.R:1-88` — `model_diagnostics()` implementation: all five estimation-window signal computations [VERIFIED]
- `R/contract.R:1-97` — degenerate-input contract: conditions, signals, `.handle_degenerate()` [VERIFIED]
- `R/models.R:1-332` — `ModelBase` private statistics fields; `MarketModel$fit()` and `private$calculate_statistics()` [VERIFIED]
- `R/single_event_test_statistics.R:1-213` — `ARTTest`, `CARTTest` output column names [VERIFIED]
- `R/multi_event_test_statistics.R:1-694` — all multi-event test output columns; `KolariPynnonenTest` reference [VERIFIED]
- `R/test_statistics_set.R:1-84` — default test sets and their `$name` fields [VERIFIED]
- `R/task.R:1-336` — `EventStudyTask` structure: `data_tbl`, `.keys`, `aar_caar_tbl`, S3 class pattern [VERIFIED]
- `R/execute.R:1-185` — `calculate_statistics()` column naming via transpose [VERIFIED]
- `R/simulation.R:125-157` — S3 class + `print.es_simulation` pattern [VERIFIED]
- `R/cross_sectional.R:130-191` — S3 class + `print.es_cross_sectional` pattern [VERIFIED]
- `R/parameter_set.R:1-103` — `ParameterSet` structure [VERIFIED]
- `R/prepare_event_study.R:100-161` — date column format and window construction [VERIFIED]
- `DESCRIPTION:1-65` — current `Imports`/`Suggests`; version; MacKinlay citation [VERIFIED]
- `tests/testthat/helper-mock-data.R:1-305` — test helper factories; date format [VERIFIED]
- `tests/testthat/test_diagnostics.R:1-87` — existing diagnostic test conventions [VERIFIED]

### Secondary (MEDIUM confidence)
- None for this phase — all claims derive directly from the codebase.

### Tertiary (LOW confidence / ASSUMED)
- KB threshold values (SW p=0.05, proportion 0.5/0.7, DW 1.5/2.5, R²<0.05, N<10) — reasonable literature-informed defaults, not verified against the original papers in this session.
- Specific claim that abs(final_car) is optimal anomaly ranking — reasonable, within Claude's discretion.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies verified against DESCRIPTION Imports
- Accessor paths: HIGH — every field name verified by direct file read with line citation
- Architecture patterns: HIGH — all patterns drawn from existing package code
- KB literature mappings: MEDIUM — citations verified in code/DESCRIPTION but threshold values assumed
- Pitfalls: HIGH — each pitfall derived from actual code behavior observed in this session

**Research date:** 2026-09-03
**Valid until:** 2026-10-03 (stable codebase; KB threshold choices may be refined after user feedback)
