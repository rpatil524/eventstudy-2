# Requirements: EventStudy — Documentation Site (pkgdown + CI/CD)

**Defined:** 2026-09-04
**Milestone:** v0.62.0
**Core Value:** Trustworthy numbers, trustworthy interpretation — now made discoverable. A curated, professional documentation site (matching the `fdars-r` pattern) that CI keeps current, so the package's capabilities and the AI advisor story are legible to anyone arriving from CRAN or GitHub.

## v1 Requirements

Requirements for milestone v0.62.0. Each maps to exactly one roadmap phase.

### Site structure (SITE)

- [ ] **SITE-01**: A `_pkgdown.yml` at the package root configures a pkgdown 2.x (Bootstrap 5) site, with `url:` set to `https://sipemu.github.io/eventstudy/` so cross-references and canonical links resolve correctly.
- [ ] **SITE-02**: The Reference index is organized into thematic groups with titles/descriptions — Pipeline & tasks, Return models, Test statistics, Panel/intraday/synthetic control, AI advisor, Diagnostics, Cross-sectional & simulation, Export & reporting, Plotting, Data & datasets — with every exported symbol appearing in exactly one group (no ungrouped/missing-topic warnings).
- [ ] **SITE-03**: The navbar exposes Get Started, Reference, an Articles dropdown, and News/Changelog; all 18 existing vignettes are reachable and grouped meaningfully under Articles (e.g. Core workflow, Models, Inference & robustness, Specialized designs, AI advisor).
- [ ] **SITE-04**: The homepage renders the README as the landing page (or a dedicated intro), building without error from the existing content.

### Theme (THEME)

- [ ] **THEME-01**: A custom Bootstrap-5 theme is applied via `template.bootstrap: 5` and a `template.bootswatch` (or `template.theme`/`bslib` variables) choosing an accent color and font pairing that reads as professional; no package logo is required.
- [ ] **THEME-02**: Syntax highlighting, code blocks, and the reference/article typography render cleanly under the chosen theme with no contrast or layout regressions in a local `pkgdown::build_site()`.

### CI/CD deploy (CI)

- [ ] **CI-01**: A `.github/workflows/pkgdown.yaml` workflow (r-lib standard) builds the pkgdown site on push to `main` and on `release: [published]`, plus manual `workflow_dispatch`.
- [ ] **CI-02**: The workflow deploys the built site to the `gh-pages` branch via `JamesIves/github-pages-deploy-action` (or `r-lib/actions` deploy step) with least-privilege `contents: write` permissions, so GitHub Pages serves it.
- [ ] **CI-03**: The workflow installs the package with its Suggests and builds articles, completing green on GitHub Actions (verified by a successful run on the default branch).

### Repo linkage (LINK)

- [ ] **LINK-01**: DESCRIPTION `URL` includes the pkgdown site URL (`https://sipemu.github.io/eventstudy/`) alongside the existing GitHub URL, and `BugReports` is retained.
- [ ] **LINK-02**: README gains a documentation-site badge/link near the existing badge row pointing at the live site.
- [ ] **LINK-03**: `.Rbuildignore` excludes `_pkgdown.yml`, `docs/`, `pkgdown/`, and the pkgdown workflow so the CRAN source tarball is unchanged by the site scaffolding.

### Build integrity (BUILD)

- [ ] **BUILD-01**: `pkgdown::build_site()` completes locally with no errors and no missing-topic/orphaned-reference warnings against the current exports and vignettes.
- [ ] **BUILD-02**: Network-touching vignettes (e.g. `data-download`) build reproducibly in CI — either already offline-safe, cached, or gated so a transient network failure does not break the docs build; any non-evaluated content is clearly labelled.
- [ ] **BUILD-03**: `R CMD check --as-cran` shows no new NOTEs/WARNINGs relative to the v0.61.x baseline, the existing test suite stays green, and the package version is bumped to `0.62.0` with a NEWS.md `v0.62.0` entry recording the documentation site.

## Future Requirements

Deferred, tracked but not in this roadmap.

- **Package logo / hex sticker** — add branded artwork to the navbar and homepage once a design exists.
- **Custom homepage cards** — fdars-r-style illustrated topic cards on the landing page (beyond grouped reference), if desired later.
- **Versioned/multi-version docs** — `pkgdown` dev-mode versioning for released vs. dev docs.
- **Advisor Pro (PRO-01/02)** / **Surfaces (SURF-01/02)** — unchanged from prior deferrals.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Package logo creation | User chose "custom theme, no logo"; artwork is deferred |
| Rewriting or adding vignette content | This milestone organizes and publishes existing vignettes; content changes are separate |
| Changing package APIs or statistical behavior | Purely additive docs + infra milestone |
| Setting the GitHub repo "About → Website" field | Manual GitHub UI setting; CI cannot set it — flagged as an operator step |
| Bundling built `docs/` into the CRAN tarball | Site is CI-built and served from gh-pages; `.Rbuildignore` keeps it out |
| Custom illustrated homepage cards | Deferred to Future; grouped reference + custom theme is the v0.62.0 bar |

## Traceability

Mapped during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SITE-01 | Phase 11 | Pending |
| SITE-02 | Phase 11 | Pending |
| SITE-03 | Phase 11 | Pending |
| SITE-04 | Phase 11 | Pending |
| THEME-01 | Phase 11 | Pending |
| THEME-02 | Phase 11 | Pending |
| CI-01 | Phase 12 | Pending |
| CI-02 | Phase 12 | Pending |
| CI-03 | Phase 12 | Pending |
| LINK-01 | Phase 12 | Pending |
| LINK-02 | Phase 12 | Pending |
| LINK-03 | Phase 12 | Pending |
| BUILD-01 | Phase 11 | Pending |
| BUILD-02 | Phase 12 | Pending |
| BUILD-03 | Phase 12 | Pending |

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15 ✓
- Unmapped: 0 ✓

Phase distribution:
- Phase 11 (Curated pkgdown Site + Custom Theme): SITE-01..04, THEME-01, THEME-02, BUILD-01 (7)
- Phase 12 (CI/CD Deploy + Repo Linkage + Release Integrity): CI-01..03, LINK-01..03, BUILD-02, BUILD-03 (8)

---
*Requirements defined: 2026-09-04*
*Last updated: 2026-09-04 after roadmap creation — traceability mapped, 15/15 covered*
