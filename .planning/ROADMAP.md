# Roadmap: EventStudy — Grounded AI Advisor

## Milestones

- ✅ **v0.50.0 Robustness Hardening** — Phases 1-4 (shipped 2026-09-02)
- ✅ **v0.60.0 Grounded AI Advisor** — Phases 5-8 (shipped 2026-09-04)
- 🚧 **v0.61.0 Advisor Vignette + Dieselgate Walkthrough** — Phases 9-10 (in progress)

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Numbering is continuous across milestones. Full per-phase detail for shipped
milestones lives in `.planning/milestones/v{X.Y}-ROADMAP.md`.

<details>
<summary>✅ v0.50.0 Robustness Hardening (Phases 1-4) — SHIPPED 2026-09-02</summary>

- [x] **Phase 1: Contract Foundation** — degenerate-input contract + strict/lenient mode (completed 2026-09-02)
- [x] **Phase 2: Model and Stats Sweep** — contract applied across all 13 models + all test statistics (completed 2026-09-02)
- [x] **Phase 3: Pipeline and External Hardening** — hardened prepare/export + wrapped external-package areas (completed 2026-09-02)
- [x] **Phase 4: Regression Net and Check Gate** — per-fix regression tests + contract matrix + green R CMD check (completed 2026-09-02)

Archive: `.planning/milestones/v0.50.0-ROADMAP.md`

</details>

<details>
<summary>✅ v0.60.0 Grounded AI Advisor (Phases 5-8) — SHIPPED 2026-09-04</summary>

**Milestone Goal:** Add an LLM-agnostic AI advisor that guides users through an entire event study — grounded so it interprets only package-computed numbers and never fabricates results.

- [x] **Phase 5: Offline Diagnostics + Grounding Knowledge Base** — deterministic zero-dependency `es_diagnostics()`, pure-R assumption→test KB, non-LLM rule-based advice fallback (completed 2026-09-03)
- [x] **Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness** — LLM-agnostic `AdvisorProvider` R6 hierarchy (Anthropic, OpenAI-compatible, custom), 3-tier precedence, graceful degradation, offline-tested (completed 2026-09-04)
- [x] **Phase 7: Grounded Advise Layer + Grounding Guard** — `es_advise()` `Advice` object with runtime grounding guard, all six advice modes, `generate_report()` integration (completed 2026-09-04)
- [x] **Phase 8: Agent Skill + Waitlist + Green Check Gate** — Claude Code Agent Skill, "Advisor Pro" waitlist surface, green `R CMD check --as-cran` with suite green (completed 2026-09-04)

Archive: `.planning/milestones/v0.60.0-ROADMAP.md` · Audit: `.planning/milestones/v0.60.0-MILESTONE-AUDIT.md`

</details>

### 🚧 v0.61.0 Advisor Vignette + Dieselgate Walkthrough (Phases 9-10)

**Milestone Goal:** Ship a CRAN vignette that explains the AI advisor's idea and mechanics, anchored by a real Volkswagen dieselgate worked example, and align the package's other doc entry points around that story.

- [x] **Phase 9: Bundled Dieselgate Dataset + Provenance** — reproducible `data-raw/` fetch of VW + benchmark returns around the Sept 2015 EPA disclosure, frozen into `data/` with documented provenance and `.Rd`, proven to drive a valid end-to-end event study
- [x] **Phase 10: Advisor Vignette + Offline-Safe Build + Docs + Release** — the two-layer advisor vignette (deterministic layer live, LLM layer static/labelled) on the bundled dieselgate data, offline-safe build, aligned README/pkgdown/NEWS, and a CRAN-clean 0.61.0 release (completed 2026-09-04)

## Phase Details

### Phase 9: Bundled Dieselgate Dataset + Provenance
**Goal**: A real Volkswagen dieselgate dataset ships with the package — reproducibly fetched, frozen, documented — and demonstrably drives a valid, non-degenerate event study end-to-end that the vignette can narrate.
**Depends on**: Phase 8 (v0.60.0 advisor exports exist)
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04
**Open question (phase resolves)**: Exact ticker (VOW.DE vs VOW3.DE), benchmark index choice, and data-source licensing check — resolved during phase research, not a blocker.
**Success Criteria** (what must be TRUE):
  1. A maintainer can run `data-raw/dieselgate.R` and reproduce the bundled data via the package's own `download_stock_data()`, with source, tickers, date range, and access date recorded in the script.
  2. A user can `data(dieselgate)` with no network connection and get VW + benchmark index returns spanning an estimation window and event window around 2015-09-18.
  3. A user can open `?dieselgate` and read documented columns, the firm/index identities, the event date, the window layout, and a provenance/licensing note.
  4. Running `prepare_event_study()` → `fit_model()` → `calculate_statistics()` on the bundled data yields a non-degenerate, interpretable AR/CAR result (no all-NA, no zero-variance collapse).
**Plans**: TBD

### Phase 10: Advisor Vignette + Offline-Safe Build + Docs + Release
**Goal**: A CRAN vignette explains why the advisor exists and how its two layers work, walks through the dieselgate example with the deterministic layer live and the LLM layer shown statically, builds fully offline, and ships as a CRAN-clean 0.61.0 release with aligned docs.
**Depends on**: Phase 9 (bundled dataset drives the walkthrough)
**Requirements**: VIG-01, VIG-02, VIG-03, VIG-04, VIG-05, BUILD-01, BUILD-02, DOCS-01, DOCS-02, DOCS-03, REL-01, REL-02
**Success Criteria** (what must be TRUE):
  1. A reader of the vignette understands why the advisor exists and its two-layer architecture (deterministic offline grounding vs. LLM interpretation) plus the grounding invariant that it never fabricates a number.
  2. The vignette runs the dieselgate pipeline and the deterministic advisor layer (`es_diagnostics()`, `recommend_stat()`, `flag_robustness()`) LIVE with no API key, showing real output, while `es_advise()` appears as a static, clearly-labelled captured block with an explicit note on why it is not evaluated at build; the two layers are visually and narratively separated.
  3. `R CMD build` produces the vignette with zero network access, no API key, and without the optional AI Suggests (`httr2`/`jsonlite`) installed — LLM chunks are `eval=FALSE`/precomputed, deterministic chunks evaluate live.
  4. README, pkgdown config, and NEWS.md all reference the advisor vignette and dieselgate example coherently, with a `v0.61.0` NEWS heading.
  5. DESCRIPTION registers `VignetteBuilder: knitr`, declares any new Suggests, and bumps to `0.61.0`; `R CMD check --as-cran` passes with no new NOTEs/WARNINGs vs the v0.60.0 baseline and the existing test suite stays green.
**Plans**: TBD
**UI hint**: no

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Contract Foundation | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 2. Model and Stats Sweep | v0.50.0 | 4/4 | Complete | 2026-09-02 |
| 3. Pipeline and External Hardening | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 4. Regression Net and Check Gate | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 5. Offline Diagnostics + Grounding KB | v0.60.0 | 3/3 | Complete | 2026-09-03 |
| 6. Provider Abstraction + HTTP Harness | v0.60.0 | 3/3 | Complete | 2026-09-04 |
| 7. Grounded Advise Layer + Guard | v0.60.0 | 2/2 | Complete | 2026-09-04 |
| 8. Agent Skill + Waitlist + Check Gate | v0.60.0 | 2/2 | Complete | 2026-09-04 |
| 9. Bundled Dieselgate Dataset + Provenance | v0.61.0 | 1/1 | Complete | 2026-09-04 |
| 10. Advisor Vignette + Offline-Safe Build + Docs + Release | v0.61.0 | 1/1 | Complete | 2026-09-04 |
