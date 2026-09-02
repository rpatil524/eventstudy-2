# Phase 2: Model and Stats Sweep - Context

**Gathered:** 2026-09-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the Phase 1 degenerate-input contract **uniformly** across every return model and every test statistic, so no component silently emits Inf/NaN or crashes on degenerate input. This is the horizontal sweep that follows Phase 1's vertical exemplar (MarketModel).

In scope: migrating the remaining ~12 return models onto `.handle_degenerate()` (adding missing zero-variance / insufficient-obs / finite-df guards); the pre-call contract guards for GARCH/DCC-GARCH/RollingWindow; verifying + locking the multi-event test-statistic correctness (event_id joins, NA-safe CAR chains) with regression tests; and uniform single-event / denominator / Inf-NaN guards across the test statistics.

Out of scope: the external-package **failure** wrapping (rugarch/rmgarch tryCatch, convergence, non-finite covariance handling) → Phase 3 (EXTERNAL-03/04); prepare/window/export hardening → Phase 3; the check-gate/regression-matrix acceptance → Phase 4.

Depends on: Phase 1 — reuses `.resolve_degenerate_mode()`, `.handle_degenerate()`, the ModelBase `degenerate_mode`/`event_id`/`firm_symbol` fields, and the execute.R threading. See the mode-threading pattern established in Phase 1.
</domain>

<decisions>
## Implementation Decisions

### External-Package Model Boundary (Phase 2 vs Phase 3)
- GARCH, DCC-GARCH, and RollingWindow **do** get the degenerate-input contract guards in Phase 2: apply the *pre-call* guards (insufficient obs, zero/near-zero variance, finite df) via `.handle_degenerate()` before the rugarch/rmgarch call and route existing window-level degeneracies (RollingWindow's insufficient-obs / effective-window / NA-params) through the contract.
- The rugarch/rmgarch **failure** wrapping (tryCatch around the external fit, convergence failure, non-finite covariance) stays in **Phase 3** (EXTERNAL-03/04). Phase 2 leaves those existing failure warnings as-is and only adds the contract's degenerate-input guards.

### Test-Statistic Correctness Scope
- **STATS-02 (many-to-many):** already fixed — the multi-event stats (BMP/Patell/KP/CSect) join on `event_id`, not `firm_symbol` (GH #7, commit 63d67a1). Phase 2 **verifies and locks** this with regression tests (a firm appearing in >1 event must not inflate denominators/counts); it does NOT rewrite the joins.
- **STATS-03 (NA-safe CAR/CAAR):** `cumsum(dplyr::coalesce(..., 0))` is already present. Verify + add a firm-drops-mid-window regression test proving the NA gap doesn't corrupt subsequent cumulative values.
- **STATS-04 (single-event / firms-in-multiple-events denominators):** add uniform guards so `n_events == 1` (and zero-variance cross-sectional dispersion) yields NA rather than Inf / divide-by-zero, across Patell/BMP/KP/CSect/Sign; add tests.
- **STATS-01 (Inf/NaN leakage):** guard denominators (`sd < .Machine$double.eps` → NA) consistently in single-event statistics (AR t, CAR t, BHAR).

### Model Rollout & df Counting
- Group the model migration into **~4 plans by structural similarity**:
  1. Simple/adjusted models: MarketAdjusted, ComparisonPeriodMean, Custom + BHAR, Volume, Volatility
  2. Factor models: LinearFactorModel (base) → FamaFrench3/5, Carhart4 (inherit)
  3. Time-varying / external: RollingWindow, GARCH, DCC-GARCH (pre-call guards only)
  4. Test statistics: single- and multi-event verification + guards + regression tests
  (Planner may adjust exact grouping, but keep structurally-similar models together and stats separate.)
- **MODELS-03 (finite-only df):** extract/reuse a shared finite-residual df helper in `R/contract.R` and apply it to every model so df reflects only finite residuals, not total row count.
- **MODELS-04 (FEC):** apply forecast-error correction where the model supports it (as MarketModel does); leave models that don't support it unchanged.
- **Valid-input invariance:** capture per-model valid-input baselines (coefficients/sigma/df/a few ARs) BEFORE migrating each model group and assert byte/near-identical (within ~1e-8) after — the same CONTRACT-05 discipline as Phase 1, per model.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 1)
- `R/contract.R`: `.resolve_degenerate_mode()`, `.handle_degenerate(mode, component, event_id, firm_symbol, condition/reason, private_env)`; the `.degenerate_handled` private flag for one-warning suppression in `abnormal_returns()`.
- `ModelBase` carries `degenerate_mode`/`event_id`/`firm_symbol` fields (inherited by all models); `execute.R`'s `.initialize_and_fit_model()` injects them per event via `purrr::map(seq_len(nrow(task$data_tbl)), ...)`.
- MarketModel (`R/models.R:139`) is the fully-migrated exemplar — copy its guard structure (lines ~183-226): insufficient-obs guard, `sd(index_returns) < .Machine$double.eps` zero-variance guard, each routed through `.handle_degenerate()` then `private$.is_fitted <- FALSE`.

### Current State of Targets
- **Models still ad-hoc** (plain `warning()` + `private$.is_fitted <- FALSE`, ignore strict mode + injected keys): MarketAdjusted (`models.R:362`), ComparisonPeriodMean (`435`), BHAR (`994`), Volume (`1092`), Volatility (`1197`), LinearFactorModel/FF3/FF5/Carhart (`509`+), RollingWindow (`models_time_varying.R:38`), GARCH (`844`), DCC-GARCH (`models_time_varying.R:253`). All need migration.
- **Multi-event stats** (`R/multi_event_test_statistics.R`): BMP joins on `event_id` with an explicit comment about avoiding the many-to-many inflation (`:413-419`); cumsum chains use `coalesce` already (CSect `:44`, Patell `:157-164`, Sign, GeneralizedSign, Rank, BMP). Work is verification + denominator/single-event guards + regression tests, not rewrite.
- `ModelBase$calculate_forecast_error_correction()` (`models.R:91`) has the `ss_market < .Machine$double.eps` FEC fallback — do NOT treat as a degeneracy signal (Phase 1 rule carries forward).

### Established Patterns
- Guard → `.handle_degenerate(...)` → `private$.is_fitted <- FALSE` → `return(invisible(self))`.
- Error style `stop(..., call. = FALSE)`; internal helpers leading-dot `@noRd`; testthat 3e with `helper-mock-data.R` factories (including the new `create_degenerate_model_data_*()` from Phase 1).

</code_context>

<specifics>
## Specific Ideas

- Every migrated model, in strict mode, must raise an error naming its component name + event_id + firm_symbol (the keys are already injected by execute.R) — mirror MarketModel exactly.
- Reuse Phase 1's degenerate data factories (`create_degenerate_model_data_insufficient()`, `create_degenerate_model_data_zero_variance()`) and extend for factor/time-varying/volume/volatility shapes as needed.
- Factor models: fix the guard once on `LinearFactorModel` so FF3/FF5/Carhart4 inherit it.
- The one-warning-per-(event_id,firm_symbol) invariant must hold for every migrated model in the pipeline (extend the WR-02 `.degenerate_handled` suppression to each model's `abnormal_returns()`).
</specifics>

<deferred>
## Deferred Ideas

- rugarch/rmgarch/did external-**failure** wrapping (tryCatch, convergence, non-finite, availability guards, subprocess isolation) → Phase 3.
- prepare/window/export/tidy and cross-sectional-regression collinearity hardening → Phase 3.
- Full contract test matrix across all components in both modes + green R CMD check → Phase 4.
</deferred>
