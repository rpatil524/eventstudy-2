# Phase 3: Pipeline and External Hardening - Context

**Gathered:** 2026-09-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the preparation/windowing, export/tidy, cross-sectional regression, and external-package-bound areas degrade **predictably**: missing dates, empty windows, collinear regressors, and upstream package failures/absence all produce informative messages (warning or mode-honoring error) rather than uninformative crashes or silent wrong results.

In scope: `prepare_event_study()` missing-date / empty-window handling; `export_results()` / `tidy()` NA-safety; `cross_sectional_regression()` singular/collinear design; defensive wrapping of panel-DiD estimators (did, DIDmultiplegt, didimputation), the deferred rugarch/rmgarch **failure** wrapping from Phase 2, and synthetic-control numerical stability; uniform optional-package-absence policy.

Out of scope: the contract definition and model/statistic sweep (Phases 1-2, done); the regression-net + R CMD check acceptance gate (Phase 4). Native reimplementation of external estimators (v2). Performance/scaling (v2).

Depends on: Phase 2 — reuses `.resolve_degenerate_mode()` / `.handle_degenerate()` for event-identifiable pipeline degeneracies.
</domain>

<decisions>
## Implementation Decisions

### External-Package Failure & Absence Policy
- **Uniform missing-package policy:** an estimator-required optional package that is absent produces a **warning naming the lost capability and returns `NULL`** (NOT `stop()`). Currently `estimate_panel_*` for DIDmultiplegt (panel_event_study.R:456-459) and didimputation (549-552) `stop()` — change to warning + NULL. Capability-enhancing packages (e.g. `sandwich`) absent → **warning** (upgrade the current `message()` at panel_event_study.R:171 and cross_sectional.R:75) naming the lost capability + documented OLS/non-robust fallback (no silent degrade).
- **DIDmultiplegt segfault isolation (SC4/EXTERNAL-02):** wrap the `DIDmultiplegt::did_multiplegt` call (panel_event_study.R:462) in `tryCatch` → warning + `NULL` on error. Add a **subprocess availability probe via `callr` ONLY if `requireNamespace("callr")`** (no new hard dependency); otherwise tryCatch-only plus an opt-out option (e.g. `options(eventstudy.skip_didmultiplegt=)`) so a known-segfault platform can skip the call and warn rather than crash the session.
- **rugarch/rmgarch FAILURE wrapping (deferred from Phase 2, EXTERNAL-04):** wrap the external fit calls in `tryCatch`; convergence failure / non-finite result / error → `is_fitted = FALSE` + NA + a named warning. This is the failure-handling layer Phase 2 deliberately left untouched.
- **Synthetic-control numerical guards (EXTERNAL-04):** guard the numerical paths in `R/synthetic_control.R` — softmax max-subtraction (overflow), domain checks on `sqrt`/`log`, denominator epsilon guards.

### Pipeline Degradation Policy
- **Missing event date (SC1/PIPELINE-01):** honor the degenerate mode — strict → error naming the offending event; lenient → **warning naming the event + skip it** (NA/empty result for that event). Reuse `.resolve_degenerate_mode()` / `.handle_degenerate()`. Currently `prepare_event_study.R:110` unconditionally `stop()`s.
- **Empty estimation/event window:** same mode-honoring policy via the contract.
- **export/tidy NA-safety (SC2/PIPELINE-02):** guard every `if()` that can receive NA with NA-safe checks (`isTRUE()` / `%||%` / `coalesce()` before the `if`); render NA abnormal returns as NA/blank, never crash from `if()` on NA. Apply consistent `na.rm`.
- **cross_sectional collinear/singular (SC3/PIPELINE-03):** wrap `stats::lm()` (cross_sectional.R:56) and the vcov path in `tryCatch`; a rank-deficient / singular design returns **NA coefficients + a warning** rather than crashing.

### Scope, Contract Reuse & Testing
- **Contract reuse:** use `.handle_degenerate()` where an `event_id`/`firm_symbol` is identifiable (missing date, empty window). Use plain informative `warning()`s for package-availability issues (not event-specific).
- **Plan grouping (2 plans):**
  1. **Pipeline hardening** — prepare/window missing-date + empty-window; export/tidy NA-safety; cross_sectional singular design. (PIPELINE-01/02/03)
  2. **External-package wrapping** — panel-DiD estimators (did/DIDmultiplegt/didimputation) + rugarch/rmgarch failure wrapping + synthetic-control numerics + uniform absence policy. (EXTERNAL-01/02/03/04)
- **Testing external absence:** `skip_if_not_installed` for happy paths; simulate absence by mocking `requireNamespace` (e.g. `testthat::local_mocked_bindings` / `with_mocked_bindings`) so the warning+NULL degrade paths are exercised WITHOUT the optional packages installed.
- **Panel failure return convention:** `estimate_panel_*` returns `NULL` + warning uniformly on failure/absence (matches SC4).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/contract.R`: `.resolve_degenerate_mode()`, `.handle_degenerate()` — reuse for missing-date / empty-window (event-identifiable).
- Existing `requireNamespace(..., quietly = TRUE)` guards already present: sandwich (panel_event_study.R:167, cross_sectional.R:60), did (409), DIDmultiplegt (456), didimputation (549), openxlsx (export.R:160), knitr (export.R:191). These are the wrap points — several currently `stop()` or `message()` and must become warning + NULL / warning + documented fallback.

### Current State of Targets
- `prepare_event_study.R:95-110` — event-date match; `length(event_index) != 1` → `stop()` (change to mode-honoring warn+skip).
- `export.R:66,80,92,105,127,138` — `if()` branches on `has_ar`/`has_aar`/`has_model` and stat presence; audit for NA-on-if crashes.
- `cross_sectional.R:56` — bare `stats::lm()` then `sandwich::vcovHC`; no singular guard.
- `panel_event_study.R` — did (att_gt 415), DIDmultiplegt (462), didimputation (555) calls; sandwich vcovCL (168). Wrap the calls, not just the availability check.
- `R/models.R` / `R/models_time_varying.R` — GARCH (rugarch) and DCC-GARCH (rmgarch) fit calls: add the failure `tryCatch` layer Phase 2 left in place-but-untouched.
- `R/synthetic_control.R` — numerical stability paths (per CONCERNS.md).

### Established Patterns
- `warning(...)` / `stop(..., call. = FALSE)`; `requireNamespace(pkg, quietly = TRUE)`; testthat 3e with `helper-mock-data.R`; contract helpers are `@noRd`.

</code_context>

<specifics>
## Specific Ideas

- Missing-date warning/error message must NAME the offending event (event_id and/or the date), mirroring the contract's message format.
- Optional-package warnings must NAME the capability lost (e.g. "cluster-robust SEs unavailable — falling back to OLS SEs; install 'sandwich'").
- The DIDmultiplegt opt-out option and the tryCatch must ensure the R SESSION never dies — returning NULL + warning is the floor.
- rugarch/rmgarch: the pre-call degenerate guards from Phase 2 stay; this phase adds the post-call failure tryCatch.
</specifics>

<deferred>
## Deferred Ideas

- Native reimplementation of did / DIDmultiplegt / rugarch estimators → v2 (INDEP-01..03).
- Data-download retry/cache → out of scope (peripheral).
- The contract test matrix across all components in both modes + green R CMD check → Phase 4.
</deferred>
