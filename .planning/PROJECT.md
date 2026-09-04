# EventStudy — Grounded AI Advisor

## What This Is

EventStudy is a comprehensive R package (CRAN) for financial event study analysis. It provides a composable R6 pipeline — `prepare_event_study()` → `fit_model()` → `calculate_statistics()` — with 13+ return models (Market, Fama-French 3/5, Carhart 4, GARCH, DCC-GARCH, Rolling-Window, BHAR, Volume, Volatility, Comparison-Period-Mean, Custom), 8+ test statistics (AR/CAR t-tests, Patell Z, BMP, Sign, Kolari-Pynnönen, Calendar-Time Portfolio, Cross-Sectional t), and specialized task types (panel DiD, intraday, synthetic control), plus bootstrap inference, cross-sectional regression, diagnostics, power simulation, and CSV/Excel/LaTeX export.

The package is mature and CRAN-published. The v0.50.0 milestone made it **never silently wrong** on degenerate input (documented contract + regression net). This milestone builds the next layer up: an **LLM-agnostic AI advisor** that guides a user through an entire event study and interprets *only* package-computed numbers — never fabricating a result.

## Core Value

The package must never produce a silently incorrect statistical result — and now, the AI layer must never present an ungrounded one. On degenerate input the pipeline errors clearly or returns NA with one warning; the advisor cites only diagnostics the package actually computed, and refuses to invent numbers. Trustworthy numbers, trustworthy interpretation.

## Current Milestone: v0.62.0 Documentation Site (pkgdown + CI/CD)

**Goal:** Ship a curated, professionally-themed pkgdown documentation website for EventStudy — auto-built and deployed to GitHub Pages by CI on every push to `main` and on releases — and link it prominently from the repo, matching the `fdars-r` documentation pattern.

**Target features:**
- **Curated `_pkgdown.yml` site** (fdars-r style) — thematically grouped Reference index (Pipeline & tasks · Return models · Test statistics · Panel/intraday/synthetic · AI advisor · Diagnostics/export/plotting), an organized Articles menu over the 18 existing vignettes, custom homepage, News/Changelog
- **Custom Bootstrap-5 theme** — bootswatch/accent color + fonts (no logo), professional look without artwork
- **CI/CD deploy workflow** — r-lib standard `pkgdown.yaml` GitHub Action building the site and deploying to the `gh-pages` branch → GitHub Pages, triggered on push to `main` and on release
- **Repo linkage** — DESCRIPTION `URL` gains the pkgdown site URL, README gets a docs-site badge/link, `.Rbuildignore` keeps pkgdown scaffolding out of the CRAN tarball
- **CI-/offline-safe build** — the site builds cleanly in Actions; network-touching vignettes (e.g. `data-download`) handled for reproducibility; no new `R CMD check` NOTEs/WARNINGs, CRAN tarball unaffected

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
- ✓ **Offline diagnostics layer** — deterministic zero-dependency `es_diagnostics()` harvester — v0.60.0
- ✓ **Grounded advise layer** — `es_advise()` `Advice` object with runtime grounding guard, all six advice modes, `generate_report()` integration — v0.60.0
- ✓ **LLM-agnostic provider abstraction** — hand-rolled thin `httr2` client (OpenAI-compatible + Anthropic + custom hook), 3-tier precedence, Suggests-guarded — v0.60.0
- ✓ **Grounding knowledge base** — pure-R assumption→test KB with academic citations, rule-based offline advice engine — v0.60.0
- ✓ **Claude Code Agent Skill + Advisor Pro waitlist** — `SKILL.md` loop over existing exports; CRAN-safe opt-in waitlist surface — v0.60.0
- ✓ **Advisor vignette + bundled multi-automaker dieselgate dataset** — offline-safe CRAN vignette, CI bands + group CAAR comparison, `data-raw/` provenance — v0.61.0

### Active

<!-- This milestone (v0.62.0). Detailed, testable REQ-IDs live in REQUIREMENTS.md. -->

- [ ] **Curated pkgdown site** — `_pkgdown.yml` with thematically grouped Reference index, organized Articles menu over the 18 vignettes, custom homepage, News/Changelog (fdars-r style)
- [ ] **Custom Bootstrap-5 theme** — bootswatch/accent color + fonts, no logo
- [ ] **CI/CD docs deploy** — r-lib `pkgdown.yaml` GitHub Action building and deploying to `gh-pages` → GitHub Pages, on push to `main` and on release
- [ ] **Repo linkage** — DESCRIPTION `URL` + README docs badge/link + `.Rbuildignore` keeps pkgdown scaffolding out of the CRAN tarball
- [ ] **CI-/offline-safe build** — site builds cleanly in Actions; network-touching vignettes handled; no new `R CMD check` NOTEs/WARNINGs, CRAN tarball unaffected

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
| Curated pkgdown site (grouped reference, custom homepage) over auto-generated default | Matches the fdars-r reference; a flat index over 30+ exports and 18 vignettes is not discoverable | — Pending |
| Custom Bootstrap-5 theme, no logo | Professional look without needing artwork; logo can follow later | — Pending |
| CI deploy to gh-pages on push-to-main + releases (r-lib `pkgdown.yaml`) | Always-current docs; standard, well-supported r-lib workflow; keeps site out of the CRAN tarball | — Pending |

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
*Last updated: 2026-09-04 starting milestone v0.62.0 Documentation Site (pkgdown + CI/CD)*
