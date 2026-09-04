# Requirements: EventStudy — Advisor Vignette + Dieselgate Walkthrough

**Defined:** 2026-09-04
**Milestone:** v0.61.0
**Core Value:** Trustworthy numbers, trustworthy interpretation — the pipeline is never silently wrong, and the AI advisor cites only package-computed diagnostics. This milestone makes that story *legible* through a worked, real-world example.

## v1 Requirements

Requirements for milestone v0.61.0. Each maps to exactly one roadmap phase.

### Dataset (DATA)

- [ ] **DATA-01**: A reproducible `data-raw/dieselgate.R` script fetches Volkswagen + a benchmark index's returns spanning an estimation window and event window around the 2015-09-18 EPA disclosure, using the package's own `download_stock_data()`, and records source, tickers, date range, and access date as comments.
- [ ] **DATA-02**: The fetched prices/returns are frozen as package data under `data/` (e.g. `dieselgate`), loadable via `data(dieselgate)` with no network access.
- [ ] **DATA-03**: The dataset has a documented roxygen `.Rd` describing its columns, the firm and index, the event date, the window layout, and its provenance/licensing note.
- [ ] **DATA-04**: The bundled dataset drives a valid event study end-to-end (`prepare_event_study()` → `fit_model()` → `calculate_statistics()`) producing a non-degenerate, interpretable result suitable for the vignette narrative.

### Vignette (VIG)

- [ ] **VIG-01**: A vignette (`vignettes/ai-advisor.Rmd` or similar) explains *why* the AI advisor exists and *how* it works, describing the two-layer architecture — deterministic offline grounding vs. LLM interpretation — and the grounding invariant (never fabricates a number).
- [ ] **VIG-02**: The vignette runs the dieselgate example live through `prepare_event_study()` → `fit_model()` → `calculate_statistics()` on the bundled data, showing the abnormal-return / CAR result.
- [ ] **VIG-03**: The vignette runs the deterministic offline advisor layer live with no API key — `es_diagnostics()`, `recommend_stat()`, and `flag_robustness()` — and shows their output.
- [ ] **VIG-04**: The vignette presents the LLM layer (`es_advise()`) as a static, clearly-labelled captured response, with an explicit note explaining why it is not evaluated at build time (offline CRAN build + no API key).
- [ ] **VIG-05**: The two layers are visually and narratively separated so a reader can tell which output is deterministic/live and which is the captured LLM interpretation.

### Offline-safe build (BUILD)

- [ ] **BUILD-01**: The vignette compiles with zero network and zero LLM API calls — LLM chunks use `eval=FALSE` and/or precomputed static output; deterministic chunks evaluate live against bundled data.
- [ ] **BUILD-02**: `R CMD build` produces the vignette without needing a network connection, API key, or optional AI Suggests (`httr2`/`jsonlite`) to be present.

### Docs alignment (DOCS)

- [ ] **DOCS-01**: README references the advisor vignette and the dieselgate example as the entry point for understanding the advisor.
- [ ] **DOCS-02**: pkgdown configuration lists the new vignette (and, if applicable, the bundled dataset) under appropriate sections.
- [ ] **DOCS-03**: NEWS.md records the vignette and dataset addition under a new `v0.61.0` heading.

### Release quality (REL)

- [ ] **REL-01**: DESCRIPTION registers the vignette builder (`VignetteBuilder: knitr`), declares any newly-required Suggests, and bumps the package version to `0.61.0`.
- [ ] **REL-02**: `R CMD check --as-cran` passes with no new NOTEs/WARNINGs relative to the v0.60.0 baseline, and the existing test suite stays green.

## Future Requirements

Deferred, tracked but not in this roadmap.

- **Advisor Pro (PRO-01/02)**: RAG-corpus advisor + managed hosting — waitlist-gated.
- **Surfaces (SURF-01/02)**: MCP server + panel/intraday/synthetic diagnostics.
- **Additional vignettes**: model-selection guide, panel-DiD walkthrough — after the advisor vignette lands.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Live LLM calls during vignette build | CRAN builds run offline with no API key; the LLM layer must be shown statically |
| Downloading data at build time | CRAN vignettes cannot hit the network; data is frozen into `data/` |
| Changing advisor behavior/APIs | This is a documentation milestone; `es_diagnostics()`/`es_advise()` behavior is unchanged |
| New advisor features or providers | Out of scope; the vignette documents what already shipped in v0.60.0 |
| Bundling a large market-data corpus | Only the minimal VW + index window needed for one worked example |

## Traceability

Mapped during roadmap creation (2026-09-04).

| Requirement | Phase | Status |
|-------------|-------|--------|
| DATA-01 | Phase 9 | Complete |
| DATA-02 | Phase 9 | Complete |
| DATA-03 | Phase 9 | Complete |
| DATA-04 | Phase 9 | Complete |
| VIG-01 | Phase 10 | Pending |
| VIG-02 | Phase 10 | Pending |
| VIG-03 | Phase 10 | Pending |
| VIG-04 | Phase 10 | Pending |
| VIG-05 | Phase 10 | Pending |
| BUILD-01 | Phase 10 | Pending |
| BUILD-02 | Phase 10 | Pending |
| DOCS-01 | Phase 10 | Pending |
| DOCS-02 | Phase 10 | Pending |
| DOCS-03 | Phase 10 | Pending |
| REL-01 | Phase 10 | Pending |
| REL-02 | Phase 10 | Pending |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16 ✓
- Unmapped: 0

---
*Requirements defined: 2026-09-04*
*Last updated: 2026-09-04 after roadmap creation (Phases 9-10 mapped)*
