# EventStudy — Grounded AI Advisor

## What This Is

EventStudy is a comprehensive R package (CRAN) for financial event study analysis. It provides a composable R6 pipeline — `prepare_event_study()` → `fit_model()` → `calculate_statistics()` — with 13+ return models (Market, Fama-French 3/5, Carhart 4, GARCH, DCC-GARCH, Rolling-Window, BHAR, Volume, Volatility, Comparison-Period-Mean, Custom), 8+ test statistics (AR/CAR t-tests, Patell Z, BMP, Sign, Kolari-Pynnönen, Calendar-Time Portfolio, Cross-Sectional t), and specialized task types (panel DiD, intraday, synthetic control), plus bootstrap inference, cross-sectional regression, diagnostics, power simulation, and CSV/Excel/LaTeX export.

The package is mature and CRAN-published. The v0.50.0 milestone made it **never silently wrong** on degenerate input (documented contract + regression net). This milestone builds the next layer up: an **LLM-agnostic AI advisor** that guides a user through an entire event study and interprets *only* package-computed numbers — never fabricating a result.

## Core Value

The package must never produce a silently incorrect statistical result — and now, the AI layer must never present an ungrounded one. On degenerate input the pipeline errors clearly or returns NA with one warning; the advisor cites only diagnostics the package actually computed, and refuses to invent numbers. Trustworthy numbers, trustworthy interpretation.

## Current Milestone: v0.60.0 Grounded AI Advisor

**Goal:** Add an LLM-agnostic AI advisor that guides users through an entire event study — grounded so it interprets only package-computed numbers and never fabricates results.

**Target features:**
- `es_diagnostics(task)` — deterministic offline diagnostics layer (zero new deps, works with no API key) harvesting fit stats, CAR/CAAR + p-values, cross-sectional dispersion, and v0.50.0 contract signals (`is_fitted`, NA/zero-variance/insufficient-obs flags)
- `es_advise(diagnostics, task=, provider=, model=)` — grounded `Advice` object (interpretation / recommendations / caveats) with a runtime grounding guard that rejects evidence absent from the diagnostics
- LLM-agnostic provider abstraction: OpenAI-compatible endpoint + native Anthropic + pluggable custom-provider hook; 3-tier precedence (arg → env var → default); `httr2`/`jsonlite` in Suggests only
- Grounding knowledge base: assumption→test mappings, when-to-use rules, academic citations (MacKinlay, Brown & Warner, Patell, BMP, Kolari-Pynnönen)
- Advice scope: interpret results, recommend test statistic, recommend model & windows, flag robustness issues, open design discussion, and report-writing help (feeds `generate_report()`)
- Claude Code Agent Skill (`SKILL.md` with references) orchestrating load→run→diagnose→advise→re-run→compare
- Commercial-tier waitlist surface advertising the future retrieval-grounded "Advisor Pro"

## Business Context

- **Customer**: Applied finance/econometrics researchers and quant practitioners running event studies in R
- **Revenue model**: Freemium — the bundled advisor (curated reference grounding) ships free/open-source; a future retrieval-grounded "Advisor Pro" (full literature corpus, RAG) is a paid tier
- **Success metric**: Advisor Pro waitlist signups — a demand signal gathered before the heavier RAG version is built
- **Strategy notes**: Advisor Pro does not exist yet; the waitlist validates commercial demand before investment. Nothing in this milestone commits to building it.

## Requirements

### Validated

<!-- Shipped and confirmed. Inferred capabilities + delivered milestones. -->

- ✓ Core pipeline: prepare → fit → calculate_statistics via `run_event_study()` — existing
- ✓ 13+ return models under a common `ModelBase` interface — existing
- ✓ Single-event (AR/CAR) and multi-event (AAR/CAAR, Patell, BMP, Sign, KP, CSect) test statistics — existing
- ✓ Panel DiD estimators (TWFE, Sun-Abraham, Callaway-Sant'Anna, BJS, de Chaisemartin-D'Haultfoeuille) — existing
- ✓ Intraday event studies (POSIXct, minute/second windows) — existing
- ✓ Synthetic control method — existing
- ✓ Bootstrap inference, cross-sectional regression, diagnostics, power simulation — existing
- ✓ CSV/Excel/LaTeX export, broom-compatible tidy(), RMarkdown `generate_report()` — existing
- ✓ testthat 3e suite (1378 tests) with mock-data helpers and `test_edge_cases.R` — existing
- ✓ **Degenerate-input contract** (`?degenerate-input-contract`, `R/contract.R`) with configurable strict/lenient handling across all 13 return models and 8+ test statistics — v0.50.0
- ✓ **Hardened prepare/window logic, export/tidy NA-safety, cross-sectional collinearity guards** — v0.50.0
- ✓ **Defensively wrapped external-package call sites** (did, DIDmultiplegt, didimputation, sandwich, rugarch, rmgarch, synthetic-control solve.QP) — v0.50.0
- ✓ **Durable regression net**: 25-component contract matrix, fix→test catalog, green `R CMD check` (0 new NOTEs/WARNINGs) — v0.50.0

### Active

<!-- This milestone (v0.60.0). Detailed, testable REQ-IDs live in REQUIREMENTS.md. -->

- [ ] **Offline diagnostics layer** — `es_diagnostics()` deterministic, zero-dependency, serializable feature extraction reusing `diagnostics.R` and v0.50.0 contract signals
- [ ] **Grounded advise layer** — `es_advise()` with structured `Advice` schema and a runtime grounding guard (no fabricated numbers)
- [ ] **LLM-agnostic provider abstraction** — OpenAI-compatible + native Anthropic + custom-provider hook; 3-tier config precedence; AI deps in Suggests
- [ ] **Grounding knowledge base** — curated methodology references and academic citations injected as grounded context
- [ ] **Advice coverage** — interpret / recommend-statistic / recommend-model+windows / flag-robustness / design-discussion / report-writing
- [ ] **Claude Code Agent Skill** — `SKILL.md` with references orchestrating the full advise loop
- [ ] **Commercial-tier waitlist** — lightweight waitlist pointer + docs for the future "Advisor Pro"
- [ ] **CRAN-clean** — offline layer pure base R; LLM layer optional/Suggests-guarded; green `R CMD check`

### Out of Scope

- **MCP server surface** — deferred; the Agent Skill delivers the full loop with less surface area. MCP can follow if agentic multi-tool demand appears.
- **Full retrieval-corpus (RAG) advisor** — this *is* the commercial "Advisor Pro"; not built this milestone, validated via waitlist first.
- **Native provider SDK dependencies** — HTTP-only via `httr2`; no heavy per-provider SDKs, to keep the dependency surface small and CRAN-clean.
- **Model fine-tuning / bespoke models** — the advisor orchestrates existing hosted/local LLMs; no training.
- **Native reimplementation of external estimators** (did, DIDmultiplegt, rugarch) — separate independence milestone.
- **Performance/scaling work** (streaming, data.table backend, sparse FE) — orthogonal; deferred.
- **Changing the statistical intent of any existing method** — behavior on valid input stays unchanged.

## Context

- **Mature brownfield CRAN package.** Codebase map complete in `.planning/codebase/`. R 4.1.0+, R6 OOP, tidyverse pipeline. `cran-comments.md`, `NEWS.md` present.
- **The advisor rides the pyfda/fdars pattern** (github.com/sipemu/pyfda): a deterministic offline `build_diagnostics` layer + a grounded `advise` layer over a uniform provider protocol, with the hard invariant that the LLM interprets only computed diagnostics. EventStudy adapts this: `es_diagnostics()` + `es_advise()`, provider precedence arg→env→default, and a grounding runtime guard.
- **v0.50.0 is the foundation.** The degenerate-input contract's `is_fitted` flags, NA discipline, and zero-variance/insufficient-obs signals become structured diagnostic inputs — the advisor can *flag robustness issues* directly from contract state.
- **Existing diagnostics to reuse:** `R/diagnostics.R` (Shapiro-Wilk, Durbin-Watson, Ljung-Box, pre-trend). Existing report path: `R/report.R` `generate_report()` — report-writing help drafts grounded narrative into it.
- **CRAN dependency discipline is non-negotiable.** The pattern from v0.50.0 (optional packages in Suggests, `requireNamespace()`-guarded) applies to every AI dependency; the offline layer must add zero hard deps.

## Constraints

- **Tech stack**: R 4.1.0+, R6, testthat 3e — no new language or framework; the advisor stays within the existing stack (+ `httr2`/`jsonlite` as Suggests)
- **Compatibility**: Behavior on existing valid inputs must not change — the advisor is additive; existing 1378 tests stay green
- **CRAN**: No new `R CMD check` NOTEs/WARNINGs; AI/HTTP dependencies stay in Suggests, guarded by `requireNamespace()`; offline diagnostics add no dependency
- **Grounding**: The LLM must never present a number absent from the diagnostics; enforced by schema + system prompt + a runtime guard, and covered by regression tests
- **Provider-agnostic**: No hard-coding to one vendor; provider selection is the single configuration seam (arg → env var → default)
- **No secrets in the package**: API keys come only from the user's environment; never bundled, logged, or committed

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Configurable strict vs lenient degenerate-input handling | Serves fail-fast interactive use and NA-tolerant batch runs | ✓ v0.50.0 |
| Zero-variance guard scoped to variance-dependent models only | Arithmetic models produce valid abnormal returns on constant input; degenerate handling for them lives at the test-statistic layer | ✓ v0.50.0 |
| Harden external-package areas defensively (wrap, don't reimplement) | Full coverage without taking on upstream maintenance | ✓ v0.50.0 |
| Acceptance bar = regression test per fix + contract matrix + green R CMD check | Converts recurring audit churn into a durable net | ✓ v0.50.0 |
| Two-layer advisor: deterministic offline diagnostics + grounded LLM advise (pyfda/fdars pattern) | Offline layer is always available and testable; LLM only interprets computed numbers — a direct extension of "never silently wrong" | — Pending |
| Grounding invariant enforced by a runtime guard | Schema + prompt alone can't guarantee no fabrication; the guard rejects any evidence citing values absent from the diagnostics | — Pending |
| LLM layer optional (Suggests: `httr2`/`jsonlite`, `requireNamespace()`-guarded); offline layer pure base R | Preserves CRAN cleanliness and no-API-key usability | — Pending |
| Provider abstraction = OpenAI-compatible + Anthropic + custom hook (not four native SDKs) | Fewest code paths to test; Ollama/gateways covered by the OpenAI-compatible endpoint | — Pending |
| Freemium: bundled advisor free, retrieval-corpus "Advisor Pro" as a future paid tier gated by a waitlist | Validate commercial demand before building the heavier RAG version | — Pending |
| Agent Skill surface now, MCP server deferred | The Skill delivers the full loop with less surface area; MCP can follow if agent demand appears | — Pending |
| Defer performance/scaling and native reimplementation | Real but orthogonal to this milestone | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Business Context check — customer, revenue model, success metric still accurate?
4. Audit Out of Scope — reasons still valid?
5. Update Context with current state

---
*Last updated: 2026-09-02 starting milestone v0.60.0 Grounded AI Advisor*
