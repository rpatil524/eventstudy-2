# Requirements: EventStudy — v0.60.0 Grounded AI Advisor

**Defined:** 2026-09-02
**Core Value:** Trustworthy numbers, trustworthy interpretation — the pipeline is never silently wrong, and the AI advisor cites only package-computed diagnostics, never fabricating a result.

## v0.60.0 Requirements

Requirements for this milestone. Each maps to a roadmap phase (see Traceability).

### Offline Diagnostics (DIAG)

Deterministic, zero-dependency feature extraction. Always works with no API key.

- [x] **DIAG-01**: `es_diagnostics(task)` returns a serializable named list (class `es_diagnostics`) using only base R + existing package internals — zero new dependencies
- [x] **DIAG-02**: Diagnostics include estimation-window fit signals (R², Durbin-Watson, Ljung-Box p, Shapiro-Wilk p, ACF1) sourced from `R/diagnostics.R`
- [x] **DIAG-03**: Diagnostics include event-window results (AR/CAR, AAR/CAAR, per-test-statistic values and p-values)
- [x] **DIAG-04**: Diagnostics include cross-sectional signals (n_events, n_valid_events, CAR dispersion/IQR, event-window overlap count)
- [x] **DIAG-05**: Diagnostics surface v0.50.0 contract state per event (`is_fitted`, NA counts, zero-variance / insufficient-obs flags)
- [x] **DIAG-06**: Diagnostics payload is size-capped (row cap on per-event tables) to bound LLM token cost
- [x] **DIAG-07**: `es_diagnostics()` runs without error on tasks containing degenerate/NA events and with no API key present

### Provider Abstraction (PROV)

LLM-agnostic layer. All HTTP/LLM dependencies optional.

- [ ] **PROV-01**: An `AdvisorProvider` R6 base defines a uniform request/response contract (consistent with `ModelBase`/`TestStatisticBase`)
- [ ] **PROV-02**: Native Anthropic Messages provider using tool-use structured output (`input_schema`)
- [ ] **PROV-03**: OpenAI-compatible provider using `response_format` json_schema, usable against any compatible base URL (incl. local Ollama / LM Studio)
- [ ] **PROV-04**: `CustomProvider` accepting a user function `(prompt, schema) -> list` — plug any provider with no package change
- [ ] **PROV-05**: Provider + model resolved by 3-tier precedence: explicit arg → env var (`EVENTSTUDY_ADVISOR_PROVIDER` / `_MODEL` / `_BASE_URL`) → default
- [ ] **PROV-06**: API keys read only from the environment; never logged, bundled, committed, or written to fixtures; redacted from all errors
- [ ] **PROV-07**: Provider failures (network/timeout/API/parse) degrade gracefully → warning + NULL, never crashing the session
- [ ] **PROV-08**: All LLM/HTTP dependencies live in Suggests, `requireNamespace()`-guarded

### Grounded Advise Layer (ADV)

The `Advice` object and the grounding guarantee.

- [ ] **ADV-01**: `es_advise(diagnostics, task_type=, provider=, model=)` returns an `Advice` S3 object (`interpretation`, `recommendations[]`, `caveats`) with a `print` method
- [ ] **ADV-02**: Each recommendation carries structured fields: `action`, `kind`, `rationale`, `expected_effect`, `evidence[]`
- [ ] **ADV-03**: Each `evidence` entry is structured `{diagnostic_key, value, threshold, direction}` referencing the diagnostics
- [ ] **ADV-04**: A runtime grounding guard rejects any recommendation whose evidence cites a key absent from the diagnostics, or a value mismatching within tolerance (the invariant — enforced in R, not just the prompt)
- [ ] **ADV-05**: `es_advise()` supports task types: `interpret`, `recommend_stat`, `recommend_model`, `flag_robustness`, `design_discussion`, `report_writing`
- [ ] **ADV-06**: `es_advise()` errors clearly when no provider/key is available — never a silent or fabricated result
- [ ] **ADV-07**: `report_writing` drafts grounded narrative consumable by `generate_report()` (add `advice = NULL` param + guarded template section; render path unchanged)
- [ ] **ADV-08**: Non-LLM rule-based fallback for `recommend_stat` / `flag_robustness` driven by the KB decision table (works with no provider)

### Grounding Knowledge Base (KB)

Encoded event-study methodology with citations.

- [x] **KB-01**: Assumption→test-statistic mapping encoded as a testable decision table: Shapiro-Wilk normality → Patell vs BMP; event-induced variance → BMP; cross-sectional correlation/clustering → Kolari-Pynnönen; non-normal → Sign/Corrado
- [x] **KB-02**: KB entries carry academic citations (MacKinlay 1997, Brown & Warner 1985, Patell 1976, BMP 1991, Kolari-Pynnönen 2010)
- [x] **KB-03**: KB is a pure-R data structure with unit tests asserting each rule fires on the correct diagnostic condition
- [x] **KB-04**: The system prompt injects KB context to ground the LLM's methodological reasoning

### Claude Code Agent Skill (SKILL)

- [ ] **SKILL-01**: A Claude Code Agent Skill (`.claude/skills/es-advisor/SKILL.md`) orchestrates load→run→diagnose→advise→re-run→compare
- [ ] **SKILL-02**: The skill references package functions and ships reference files (no new R code required)
- [ ] **SKILL-03**: The skill degrades to offline diagnostics when no API key is present

### Commercial-Tier Waitlist (BIZ)

- [ ] **BIZ-01**: Docs advertise a future retrieval-grounded "Advisor Pro" as a paid tier
- [ ] **BIZ-02**: A passive waitlist pointer (static URL in docs + optional printed footer) with zero runtime network/telemetry not initiated by the user (CRAN no-phone-home)

### CRAN Safety & Quality Gate (CRAN)

- [x] **CRAN-01**: Offline diagnostics add zero hard dependencies; all advisor deps stay in Suggests
- [ ] **CRAN-02**: No network in examples/tests/vignettes by default (`@examplesIf` / `skip_on_cran()` / vignette eval guards)
- [ ] **CRAN-03**: Provider layer tested offline (httptest2 mocks / static fixtures); the grounding guard has dedicated deterministic regression tests
- [ ] **CRAN-04**: Green `R CMD check` — no new NOTEs/WARNINGs; existing 1378 tests stay green
- [x] **CRAN-05**: Existing pipeline behavior on valid input is unchanged (advisor is purely additive)

## Future Requirements

Deferred beyond this milestone. Tracked, not in the current roadmap.

### Advisor Pro (PRO)

- **PRO-01**: Retrieval-grounded (RAG) advisor over a full event-study literature corpus — the commercial tier the waitlist validates
- **PRO-02**: Managed hosting / API-key-less usage for Pro subscribers

### Additional Surfaces (SURF)

- **SURF-01**: MCP server exposing run/diagnose/compare tools for external agentic use
- **SURF-02**: Diagnostics extraction for `PanelEventStudyTask` / intraday / synthetic-control tasks

## Out of Scope

| Feature | Reason |
|---------|--------|
| RAG / retrieval corpus advisor | This is the commercial "Advisor Pro"; validated via waitlist before building |
| MCP server surface | Agent Skill delivers the full loop with less surface area; defer until agentic demand appears |
| Native per-provider SDK dependencies | Explodes dep surface, defeats "agnostic", CRAN-fragile — one OpenAI-compatible path + Anthropic (or ellmer) instead |
| Model fine-tuning / bespoke models | Advisor orchestrates existing hosted/local LLMs; no training |
| Panel / intraday / synthetic-control diagnostics | Different internal structure; deferred to a later surface milestone (SURF-02) |
| Streaming responses | Non-deterministic, hard to mock/test; non-streaming only |
| Changing statistical intent of existing methods | Valid-input behavior must stay unchanged |
| Native reimplementation of external estimators | Separate independence milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DIAG-01 | Phase 5 | Complete |
| DIAG-02 | Phase 5 | Complete |
| DIAG-03 | Phase 5 | Complete |
| DIAG-04 | Phase 5 | Complete |
| DIAG-05 | Phase 5 | Complete |
| DIAG-06 | Phase 5 | Complete |
| DIAG-07 | Phase 5 | Complete |
| KB-01 | Phase 5 | Complete |
| KB-02 | Phase 5 | Complete |
| KB-03 | Phase 5 | Complete |
| KB-04 | Phase 5 | Complete |
| ADV-08 | Phase 5 | Pending |
| CRAN-01 | Phase 5 | Complete |
| CRAN-05 | Phase 5 | Complete |
| PROV-01 | Phase 6 | Pending |
| PROV-02 | Phase 6 | Pending |
| PROV-03 | Phase 6 | Pending |
| PROV-04 | Phase 6 | Pending |
| PROV-05 | Phase 6 | Pending |
| PROV-06 | Phase 6 | Pending |
| PROV-07 | Phase 6 | Pending |
| PROV-08 | Phase 6 | Pending |
| CRAN-02 | Phase 6 | Pending |
| CRAN-03 | Phase 6 | Pending |
| ADV-01 | Phase 7 | Pending |
| ADV-02 | Phase 7 | Pending |
| ADV-03 | Phase 7 | Pending |
| ADV-04 | Phase 7 | Pending |
| ADV-05 | Phase 7 | Pending |
| ADV-06 | Phase 7 | Pending |
| ADV-07 | Phase 7 | Pending |
| SKILL-01 | Phase 8 | Pending |
| SKILL-02 | Phase 8 | Pending |
| SKILL-03 | Phase 8 | Pending |
| BIZ-01 | Phase 8 | Pending |
| BIZ-02 | Phase 8 | Pending |
| CRAN-04 | Phase 8 | Pending |

**Coverage:**

- v0.60.0 requirements: 37 total (DIAG 7, PROV 8, ADV 8, KB 4, SKILL 3, BIZ 2, CRAN 5)
- Mapped to phases: 37 (Phase 5: 14, Phase 6: 10, Phase 7: 7, Phase 8: 6)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-02*
*Last updated: 2026-09-02 after roadmap creation (v0.60.0, Phases 5-8)*
