# Roadmap: EventStudy — Grounded AI Advisor

## Milestones

- ✅ **v0.50.0 Robustness Hardening** - Phases 1-4 (shipped 2026-09-02)
- 🚧 **v0.60.0 Grounded AI Advisor** - Phases 5-8 (in progress)

## Overview

v0.60.0 adds an LLM-agnostic AI advisor on top of the hardened pipeline. It ships in four coarse phases ordered by a strict dependency chain: an offline, zero-dependency `es_diagnostics()` layer plus a pure-R grounding knowledge base and rule-based fallback (independently shippable, no API key); an LLM-agnostic provider abstraction with a CRAN-safe offline HTTP test harness; the grounded `es_advise()` layer with a runtime grounding guard and all advice modes (including report-writing and design-discussion); and finally the Claude Code Agent Skill, the commercial waitlist surface, and the green `R CMD check` gate. CRAN-safety is woven into every phase; the offline layer never adds a hard dependency and the advisor is purely additive.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order. Numbering is continuous across milestones — v0.60.0 continues from Phase 4 and starts at Phase 5.

<details>
<summary>✅ v0.50.0 Robustness Hardening (Phases 1-4) — SHIPPED 2026-09-02</summary>

- [x] **Phase 1: Contract Foundation** - Define the degenerate-input contract and configurable strict/lenient mode; prove it on a reference model (completed 2026-09-02)
- [x] **Phase 2: Model and Stats Sweep** - Apply the contract uniformly across all 13 return models and all test statistics (completed 2026-09-02)
- [x] **Phase 3: Pipeline and External Hardening** - Harden prepare/export paths and defensively wrap all external-package-bound areas (completed 2026-09-02)
- [x] **Phase 4: Regression Net and Check Gate** - Write regression tests per fix, contract test matrix, verify R CMD check clean (completed 2026-09-02)

</details>

### 🚧 v0.60.0 Grounded AI Advisor (In Progress)

**Milestone Goal:** Add an LLM-agnostic AI advisor that guides users through an entire event study — grounded so it interprets only package-computed numbers and never fabricates results.

- [ ] **Phase 5: Offline Diagnostics + Grounding Knowledge Base** - Deterministic zero-dependency `es_diagnostics()`, the pure-R assumption→test knowledge base, and a non-LLM rule-based advice fallback — all independently shippable with no API key
- [ ] **Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness** - LLM-agnostic `AdvisorProvider` R6 hierarchy (Anthropic, OpenAI-compatible, custom hook), 3-tier config precedence, graceful degradation, tested entirely offline with mocked HTTP
- [ ] **Phase 7: Grounded Advise Layer + Grounding Guard** - `es_advise()` returning a structured `Advice` object with a runtime grounding guard, all six advice modes, and report-writing integration into `generate_report()`
- [ ] **Phase 8: Agent Skill + Waitlist + Green Check Gate** - Claude Code Agent Skill orchestrating the full advise loop, the commercial "Advisor Pro" waitlist surface, and a green `R CMD check` with the 1378-test suite still green

## Phase Details

### Phase 5: Offline Diagnostics + Grounding Knowledge Base

**Goal**: A user can extract a complete, serializable diagnostics object from any fitted task and get rule-based statistic/robustness advice with no API key, no network, and no new package dependency — the always-available grounding foundation the LLM layer will later interpret
**Depends on**: Phase 4 (hardened pipeline + v0.50.0 contract signals)
**Requirements**: DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05, DIAG-06, DIAG-07, KB-01, KB-02, KB-03, KB-04, ADV-08, CRAN-01, CRAN-05
**Success Criteria** (what must be TRUE):

  1. Calling `es_diagnostics(task)` on a fitted task returns a serializable `es_diagnostics` named list carrying estimation-window fit signals (R², Durbin-Watson, Ljung-Box, Shapiro-Wilk, ACF1), event-window results (AR/CAR, AAR/CAAR, per-statistic values and p-values), cross-sectional signals (n_events, n_valid, CAR dispersion, overlap), and per-event v0.50.0 contract state (`is_fitted`, NA counts, zero-variance/insufficient-obs flags)
  2. `es_diagnostics()` runs without error on a task containing degenerate/NA events and with no API key present, and its per-event payload is size-capped to bound token cost
  3. Requesting rule-based advice (`recommend_stat` / `flag_robustness`) with no provider returns a grounded recommendation driven purely by the KB decision table (e.g., Shapiro-Wilk rejection steers toward non-parametric tests, event-window overlap steers toward Kolari-Pynnönen)
  4. Each KB decision-table rule is a pure-R data structure carrying its academic citation (MacKinlay, Brown & Warner, Patell, BMP, Kolari-Pynnönen) and has a unit test asserting it fires on the correct diagnostic condition
  5. `R CMD check` shows zero new hard dependencies from this phase and existing valid-input pipeline behavior is byte-identical (advisor is purely additive)

**Plans**: 2/3 plans executed

- [x] 05-1-PLAN.md — es_diagnostics() serializable harvester + S3 print + payload cap (Wave 1)
- [x] 05-2-PLAN.md — EVENTSTUDY_KB pure-R decision table with citations + per-rule firing tests (Wave 2)
- [ ] 05-3-PLAN.md — offline recommend_stat()/flag_robustness() + Advice shape driven by the KB (Wave 3)

### Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness

**Goal**: A user can select any LLM backend — native Anthropic, any OpenAI-compatible endpoint (including local Ollama/LM Studio), or a custom function — through one uniform seam that never leaks keys, never crashes the session on failure, and is fully tested offline without a real API call
**Depends on**: Phase 5
**Requirements**: PROV-01, PROV-02, PROV-03, PROV-04, PROV-05, PROV-06, PROV-07, PROV-08, CRAN-02, CRAN-03
**Success Criteria** (what must be TRUE):

  1. An `AdvisorProvider` R6 base defines a uniform request/response contract, with `AnthropicProvider` (Messages tool-use structured output), `OpenAICompatibleProvider` (`response_format` json_schema against any base URL), and `CustomProvider` (user `(prompt, schema) -> list` hook) all implementing it
  2. Provider and model resolve by 3-tier precedence (explicit arg → `EVENTSTUDY_ADVISOR_PROVIDER`/`_MODEL`/`_BASE_URL` env vars → default); API keys are read only from the environment and are redacted from every error, never logged, bundled, committed, or written to fixtures
  3. A simulated network/timeout/API/parse failure degrades to a warning plus NULL and never crashes the R session
  4. All LLM/HTTP dependencies live in Suggests and are `requireNamespace()`-guarded; the package loads and the offline layer works with them absent
  5. The provider layer is tested entirely offline (httptest2 mocks / static fixtures) with no network in examples, tests, or vignettes by default (`@examplesIf` / `skip_on_cran()` / vignette eval guards)

**Plans**: TBD
**UI hint**: no

> **Planning-time decision (do not resolve in the roadmap):** the provider-implementation fork — Posit `ellmer` for the two built-in providers versus a hand-rolled thin `httr2` layer. Both keep the offline layer dependency-free and expose identical R6 seams. Settle this via a short spike at the start of Phase 6 planning.

### Phase 7: Grounded Advise Layer + Grounding Guard

**Goal**: A user can ask the advisor to interpret results, recommend a statistic or model, flag robustness issues, open a design discussion, or draft report narrative — and every claim the advisor returns is provably tied to a diagnostic the package actually computed, with no fabricated number ever reaching the user
**Depends on**: Phase 6
**Requirements**: ADV-01, ADV-02, ADV-03, ADV-04, ADV-05, ADV-06, ADV-07
**Success Criteria** (what must be TRUE):

  1. `es_advise(diagnostics, task_type=, provider=, model=)` returns an `Advice` S3 object (`interpretation`, `recommendations[]`, `caveats`) with a `print` method, where each recommendation carries `action`/`kind`/`rationale`/`expected_effect`/`evidence[]` and each evidence entry is structured `{diagnostic_key, value, threshold, direction}`
  2. The runtime grounding guard rejects any recommendation whose evidence cites a key absent from the diagnostics or a value mismatching beyond tolerance — enforced in R, covered by deterministic regression tests, and independent of the prompt
  3. `es_advise()` supports all six task types (`interpret`, `recommend_stat`, `recommend_model`, `flag_robustness`, `design_discussion`, `report_writing`) and errors clearly when no provider/key is available rather than returning a silent or fabricated result
  4. `report_writing` produces grounded narrative that `generate_report()` accepts via a new optional `advice = NULL` param and renders through a guarded template section, with the existing render path unchanged

**Plans**: TBD
**UI hint**: no

### Phase 8: Agent Skill + Waitlist + Green Check Gate

**Goal**: A Claude Code user can drive the entire load→run→diagnose→advise→re-run→compare loop through a documented Agent Skill, discover the future paid "Advisor Pro" tier via a passive waitlist, and trust that the whole milestone ships CRAN-clean with the existing test suite green
**Depends on**: Phase 7
**Requirements**: SKILL-01, SKILL-02, SKILL-03, BIZ-01, BIZ-02, CRAN-04
**Success Criteria** (what must be TRUE):

  1. A Claude Code Agent Skill (`.claude/skills/es-advisor/SKILL.md`) with reference files orchestrates the full load→run→diagnose→advise→re-run→compare loop using only existing package functions (no new R code) and degrades to offline diagnostics when no API key is present
  2. Package docs advertise a future retrieval-grounded "Advisor Pro" paid tier with a passive waitlist pointer (static URL + optional printed footer) that initiates zero runtime network/telemetry not requested by the user
  3. `R CMD check` is green with no new NOTEs or WARNINGs and all 1378 existing tests stay green

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 5 → 6 → 7 → 8

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Contract Foundation | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 2. Model and Stats Sweep | v0.50.0 | 4/4 | Complete | 2026-09-02 |
| 3. Pipeline and External Hardening | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 4. Regression Net and Check Gate | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 5. Offline Diagnostics + Grounding KB | v0.60.0 | 2/3 | In Progress|  |
| 6. Provider Abstraction + HTTP Harness | v0.60.0 | 0/TBD | Not started | - |
| 7. Grounded Advise Layer + Guard | v0.60.0 | 0/TBD | Not started | - |
| 8. Agent Skill + Waitlist + Check Gate | v0.60.0 | 0/TBD | Not started | - |
