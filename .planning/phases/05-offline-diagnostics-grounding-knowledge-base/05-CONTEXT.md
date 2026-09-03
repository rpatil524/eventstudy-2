# Phase 5: Offline Diagnostics + Grounding Knowledge Base - Context

**Gathered:** 2026-09-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous)

<domain>
## Phase Boundary

This phase delivers the **always-available, deterministic grounding foundation** for the AI advisor: a serializable `es_diagnostics()` feature-extraction layer and a rule-based knowledge base that produces grounded statistic/robustness advice with **no API key, no network, and zero new hard dependencies**. It is purely additive — existing valid-input pipeline behavior must stay byte-identical. The LLM interpretation layer (Phases 6–7) consumes what this phase computes; nothing here calls a provider.

Delivers: `es_diagnostics(task)` returning an S3 `es_diagnostics` object (estimation-window fit signals, event-window AR/CAR + AAR/CAAR + per-statistic values/p-values, cross-sectional signals, per-event v0.50.0 contract state); a pure-R KB decision table with academic citations; and offline `recommend_stat()` / `flag_robustness()` advice driven purely by the KB.

</domain>

<decisions>
## Implementation Decisions

### Diagnostics Object Shape & Size Cap
- Return type: **S3-classed named list** with class `es_diagnostics` (gives a `print`/`format` hook; matches success-criterion wording).
- Serialization: **JSON-ready base-R list** — structure stays lists/atomic vectors so it round-trips through `jsonlite` later, but the offline layer itself adds **no `jsonlite` dependency**.
- Per-event payload cap: **keep the top-N most-anomalous events in full + an aggregate summary for the remainder** (bounds token cost while preserving the events that matter for advice).
- Cap default: **`max_events = 20`**, overridable via argument.

### KB Decision Table
- Storage: **in-package pure-R data structure** (list of rule records) built at load — zero deps, fully unit-testable.
- Rule record fields: **`id`, condition predicate (function of diagnostics), recommendation text, citation, severity**.
- Citation format: **structured** (`author`, `year`, `key`) so the Phase 7 LLM layer can cite cleanly.
- Multiple rules firing: **return all matched rules, severity-ranked** (not first-match).

### Offline Advice API Surface
- Function surface: **two exports — `recommend_stat()` and `flag_robustness()`** (matches success criteria).
- Return shape: **the same `Advice`-shaped object the LLM layer will reuse in Phase 7** (consistency across offline/online).
- Accepted input: **either a fitted task or a precomputed `es_diagnostics` object**.
- No-provider behavior: **return grounded rule-based advice, flagged as deterministic/offline** (never error just because no provider is configured).

### Claude's Discretion
- Exact internal anomaly-ranking metric for the top-N event cap, field naming within the diagnostics list, and the `Advice` object's internal field layout are at Claude's discretion, guided by codebase conventions and the Phase 7 consumption needs.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/diagnostics.R` — exported `diagnostics(task, event_id=)` (Shapiro-Wilk, Durbin-Watson, Ljung-Box, model fit) and `pretrend_test()`. Harvest these rather than recomputing.
- `R/contract.R` — v0.50.0 degenerate-input contract: `is_fitted` flag, NA discipline, zero-variance / insufficient-obs signals (`.handle_degenerate`, `.finite_residual_df`, `.resolve_degenerate_mode`). These become structured diagnostic inputs — the advisor flags robustness directly from contract state.
- Test statistics layer (AR/CAR t, Patell Z, BMP, Sign, Kolari-Pynnönen, Cross-Sectional t) already emit values + p-values to reuse in the event-window payload.
- `R/report.R` `generate_report()` — future report-writing help target (Phase 7); no change here.

### Established Patterns
- R6 pipeline `prepare_event_study()` → `fit_model()` → `calculate_statistics()`; nested tibbles keyed by (event_id, group, firm_symbol).
- Optional deps live in `Suggests`, guarded by `requireNamespace()` (v0.50.0 discipline). Offline layer must stay pure base R.
- Public functions snake_case + `@export` roxygen; internal helpers leading-dot `@noRd`; testthat 3e with `helper-*.R` mock data.

### Integration Points
- New `es_diagnostics()` reads a fitted `EventStudyTask` (post `calculate_statistics()`), pulling from diagnostics.R, contract state, and the statistics set.
- KB decision table + `recommend_stat()` / `flag_robustness()` are new exports; NAMESPACE regenerated via roxygen2.

</code_context>

<specifics>
## Specific Ideas

- Rides the pyfda/fdars pattern: deterministic offline `build_diagnostics` + grounded `advise` over a uniform protocol, with the hard invariant that later LLM layers interpret only computed diagnostics.
- **KB correctness is load-bearing:** cross-check every assumption→test mapping and citation against the primary literature — MacKinlay (1997), Brown & Warner (1985), Patell (1976), Boehmer-Musumeci-Poulsen / BMP (1991), Kolari-Pynnönen (2010). Each rule carries its citation and a unit test asserting it fires on the correct diagnostic condition (e.g., Shapiro-Wilk rejection → non-parametric tests; event-window overlap → Kolari-Pynnönen).

</specifics>

<deferred>
## Deferred Ideas

- LLM provider abstraction and `es_advise()` grounded interpretation → Phase 6 / Phase 7.
- Full retrieval-corpus ("Advisor Pro") grounding → future waitlist-gated milestone.

</deferred>
