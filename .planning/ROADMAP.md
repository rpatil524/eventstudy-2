# Roadmap: EventStudy — Grounded AI Advisor

## Milestones

- ✅ **v0.50.0 Robustness Hardening** — Phases 1-4 (shipped 2026-09-02)
- ✅ **v0.60.0 Grounded AI Advisor** — Phases 5-8 (shipped 2026-09-04)
- ✅ **v0.61.0 Advisor Vignette + Dieselgate Walkthrough** — Phases 9-10 (shipped 2026-09-04)
- 🚧 **v0.62.0 Documentation Site (pkgdown + CI/CD)** — Phases 11-12 (in progress)

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

<details>
<summary>✅ v0.61.0 Advisor Vignette + Dieselgate Walkthrough (Phases 9-10) — SHIPPED 2026-09-04</summary>

**Milestone Goal:** Ship a CRAN vignette that explains the AI advisor's idea and mechanics, anchored by a real Volkswagen dieselgate worked example, and align the package's other doc entry points around that story.

- [x] **Phase 9: Bundled Dieselgate Dataset + Provenance** — reproducible `data-raw/` fetch of VW + benchmark returns around the Sept 2015 EPA disclosure, frozen into `data/` with documented provenance and `.Rd`, proven to drive a valid end-to-end event study (completed 2026-09-04)
- [x] **Phase 10: Advisor Vignette + Offline-Safe Build + Docs + Release** — the two-layer advisor vignette (deterministic layer live, LLM layer static/labelled) on the bundled dieselgate data, offline-safe build, aligned README/pkgdown/NEWS, and a CRAN-clean 0.61.0 release (completed 2026-09-04)

Archive: `.planning/milestones/v0.61.0-ROADMAP.md`

</details>

### 🚧 v0.62.0 Documentation Site (pkgdown + CI/CD) (Phases 11-12)

**Milestone Goal:** Ship a curated, professionally-themed pkgdown documentation website for EventStudy — auto-built and deployed to GitHub Pages by CI on every push to `main` and on releases — and link it prominently from the repo, matching the `fdars-r` documentation pattern.

- [x] **Phase 11: Curated pkgdown Site + Custom Theme (local build)** — `_pkgdown.yml` with grouped reference index, organized Articles nav over the 18 vignettes, README homepage, custom Bootstrap-5 theme, verified with a clean local `build_site()` (completed 2026-09-04)
- [ ] **Phase 12: CI/CD Deploy + Repo Linkage + Release Integrity** — r-lib `pkgdown.yaml` workflow deploying to gh-pages, DESCRIPTION URL / README badge / `.Rbuildignore`, network-safe article build, green Actions run, and a CRAN-clean 0.62.0 release

## Phase Details

### Phase 11: Curated pkgdown Site + Custom Theme (local build)

**Goal**: A curated, professionally-themed pkgdown site builds cleanly on a developer's machine — every exported symbol is grouped, all 18 vignettes are reachable and organized, the homepage renders from the README, and the custom Bootstrap-5 theme reads as professional — before any CI is introduced.
**Depends on**: Phase 10 (v0.61.x exports + 18 vignettes exist)
**Requirements**: SITE-01, SITE-02, SITE-03, SITE-04, THEME-01, THEME-02, BUILD-01
**Success Criteria** (what must be TRUE):

  1. `pkgdown::build_site()` completes locally with zero errors and zero missing-topic/orphaned-reference warnings — every exported symbol appears in exactly one grouped Reference section (Pipeline & tasks, Return models, Test statistics, Panel/intraday/synthetic, AI advisor, Diagnostics, Cross-sectional & simulation, Export & reporting, Plotting, Data & datasets).
  2. A visitor to the built site sees a navbar with Get Started, Reference, an Articles dropdown, and News/Changelog, and can reach all 18 vignettes grouped meaningfully under Articles.
  3. The homepage renders the README as the landing page without build error, and `url:` is set to `https://sipemu.github.io/eventstudy/` so cross-references and canonical links resolve.
  4. The site applies a custom Bootstrap-5 theme (accent color + font pairing via `template.bootswatch`/bslib variables, no logo), and reference/article typography, code blocks, and syntax highlighting render cleanly with no contrast or layout regressions in the local build.

**Plans**: 1/1 plans executed

- [x] 11-01-PLAN.md — curated `_pkgdown.yml` (grouped reference + Articles + navbar) and custom Bootstrap-5 bslib theme, verified warning-clean via local `build_site()`

**UI hint**: yes

### Phase 12: CI/CD Deploy + Repo Linkage + Release Integrity

**Goal**: The site that builds locally in Phase 11 is now built and deployed to GitHub Pages by CI on every push to `main` and on releases, the repo links to the live site, network-touching vignettes build reproducibly in Actions, and the whole change ships as a CRAN-clean 0.62.0 release that leaves the source tarball unchanged.
**Depends on**: Phase 11 (a locally-building site config must exist before CI can deploy it)
**Requirements**: CI-01, CI-02, CI-03, LINK-01, LINK-02, LINK-03, BUILD-02, BUILD-03
**Success Criteria** (what must be TRUE):

  1. A push to `main` triggers the `.github/workflows/pkgdown.yaml` workflow (also on `release: [published]` and manual `workflow_dispatch`), which installs the package with its Suggests, builds articles, and completes green on GitHub Actions — verified by a successful run on the default branch.
  2. The workflow deploys the built site to the `gh-pages` branch with least-privilege `contents: write` permissions, and GitHub Pages serves the site at `https://sipemu.github.io/eventstudy/`.
  3. Network-touching vignettes (e.g. `data-download`) build reproducibly in CI — offline-safe, cached, or gated so a transient network failure does not break the docs build, with any non-evaluated content clearly labelled.
  4. DESCRIPTION `URL` includes the pkgdown site URL alongside the GitHub URL (BugReports retained), the README shows a documentation-site badge/link near the existing badge row, and `.Rbuildignore` excludes `_pkgdown.yml`, `docs/`, `pkgdown/`, and the workflow so the CRAN source tarball is unchanged.
  5. `R CMD check --as-cran` shows no new NOTEs/WARNINGs vs the v0.61.x baseline, the existing test suite stays green, and the package is bumped to `0.62.0` with a NEWS.md `v0.62.0` entry recording the documentation site.

**Plans**: TBD
**Operator step**: Setting the GitHub repo "About → Website" field to the live site URL is a manual GitHub UI action — CI cannot set it. This is an operator task to perform after the first successful deploy, not an automated requirement.
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
| 11. Curated pkgdown Site + Custom Theme (local build) | v0.62.0 | 1/1 | Complete    | 2026-09-04 |
| 12. CI/CD Deploy + Repo Linkage + Release Integrity | v0.62.0 | 0/? | Not started | - |
