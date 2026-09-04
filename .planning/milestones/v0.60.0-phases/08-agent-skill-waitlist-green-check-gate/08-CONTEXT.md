# Phase 8: Agent Skill + Waitlist + Green Check Gate - Context

**Gathered:** 2026-09-04
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the user-facing surface and ship gate for the v0.60.0 Grounded
AI Advisor milestone — with NO new package R code beyond docs/config:

1. **Agent Skill** (`.claude/skills/es-advisor/SKILL.md` + reference files) that drives
   the full advisor loop (load → run → diagnose → advise → re-run → compare) using only
   already-exported package functions, and degrades to offline diagnostics when no API
   key is present.
2. **Advisor Pro waitlist** — passive documentation pointer to a future retrieval-grounded
   paid tier, with a static URL and an opt-in printed footer, initiating zero runtime
   network/telemetry not requested by the user (CRAN no-phone-home).
3. **Green-check gate** — the whole milestone ships CRAN-clean: `R CMD check --as-cran`
   with no new NOTEs/WARNINGs and the existing test suite green.

Out of scope: any new statistical/advisor R functionality (that shipped in Phases 5–7);
the RAG corpus / managed hosting of Advisor Pro itself (deferred, waitlist-gated).

</domain>

<decisions>
## Implementation Decisions

### Agent Skill Shape
- **Layout:** `.claude/skills/es-advisor/SKILL.md` as the index + a `reference/` subdirectory
  with focused files (e.g. workflow steps, function map, interpreting-diagnostics). Keeps
  SKILL.md scannable and pushes detail into references (SKILL-02 ships reference files).
- **How it drives R:** the skill instructs the Claude Code user's R session / Rscript
  one-liners — it references existing exported functions only, adds NO new R code (SKILL-02).
- **Degrade path (SKILL-03):** the skill checks provider resolution (arg → env → default);
  when no API key is present it falls back to the always-available offline path —
  `es_diagnostics()` + offline `es_advise()` (source=offline_kb) — never erroring for lack
  of a key, never fabricating.
- **Loop coverage:** documents the full load → run → diagnose → advise → re-run → compare
  loop using only exported functions (`prepare_event_study`/`run_event_study`, `fit_model`,
  `calculate_statistics`, `es_diagnostics`, `es_advise`, `recommend_stat`, `flag_robustness`,
  `provider`, `generate_report`, plotting/export).

### Advisor Pro Waitlist
- **URL placement:** a README section + a dedicated `?advisor_pro` R help topic (man page).
  DESCRIPTION URL/BugReports stay as-is.
- **Printed footer = opt-in, default OFF:** printed only when the user sets
  `options(eventstudy.advisor_pro_footer = TRUE)`. Guarantees zero unsolicited output and
  satisfies CRAN no-phone-home (BIZ-02). The pointer is a *static URL* — no live endpoint,
  no request is ever made by the package.
- **Static URL target:** a GitHub-hosted static page under the existing repo
  (README anchor / GitHub Pages); no third-party form, no telemetry.
- **Footer print site:** appended to the `Advice` / `es_advise` print method when the
  option is enabled — NOT `.onAttach`/startup, keeping attach silent.

### Green-Check Gate
- **Version bump:** DESCRIPTION `0.50.0 → 0.60.0` to match the milestone.
- **NEWS.md:** add v0.60.0 entries summarizing the advisor feature set (Phases 5–8).
- **Check level:** `R CMD check --as-cran` — no new NOTEs/WARNINGs vs the current baseline;
  full testthat suite must stay green (CRAN-04). The roadmap's "1378 tests" is the
  roadmap-time count; the operative criterion is *existing tests stay green* (current suite
  is larger — do not hardcode a count).
- **Build hygiene:** add `.claude`, `.planning`, `.gsd` (and any other dev-only top-level
  dirs) to `.Rbuildignore` so the skill/planning artifacts ship in the repo but never enter
  the CRAN tarball (avoids a non-standard-top-level-file NOTE).

### Claude's Discretion
- Exact reference-file split and filenames under `reference/`; SKILL.md frontmatter/trigger
  wording; exact README/man wording and the concrete static URL anchor; NEWS.md phrasing;
  option name spelling if a better-established convention exists; whether the footer is one
  helper or inlined in the print method. Guided by codebase conventions (snake_case public,
  leading-dot `@noRd` internal, roxygen2 docs, testthat 3e) and CRAN policy.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Exported advisor API already shipped (Phases 5–7): `es_diagnostics`, `es_advise`, `es_kb`,
  `recommend_stat`, `flag_robustness`, `model_diagnostics`, `plot_diagnostics`, `provider`,
  and providers `ProviderBase`/`OpenAICompatProvider`/`AnthropicProvider`/`CustomProvider`.
- Core pipeline: `prepare_event_study` → `fit_model` → `calculate_statistics` /
  `run_event_study`; `generate_report(advice = NULL)` already accepts a grounded Advice.
- Advisor R files: `R/advise.R`, `R/advise_offline.R`, `R/es_diagnostics.R`, `R/diagnostics.R`,
  `R/provider.R`.

### Established Patterns
- `Advice` S3 object shares `source`/`is_deterministic` fields with offline `es_advice` and
  `es_provider_response`; print methods use `cat()`.
- Optional deps (httr2/jsonlite) are Suggests, `requireNamespace()`-guarded; offline path is
  pure base R with zero hard deps.
- Grounding guard (`.validate_grounding()`) enforces the no-fabrication invariant at runtime.

### Integration Points
- Footer hooks into the existing `Advice`/`es_advise` print method (guarded by the new option).
- `?advisor_pro` becomes a new roxygen `@name`/`@docType` doc block (docs-only, no exported fn
  required — can be a package-doc-style `.Rd` via roxygen).
- `.Rbuildignore`, `DESCRIPTION` (Version), `NEWS.md`, `README` are the config/doc surfaces.

</code_context>

<specifics>
## Specific Ideas

- SKILL directory path is fixed by SKILL-01: `.claude/skills/es-advisor/SKILL.md`.
- Waitlist must be *passive*: static URL only, printed footer opt-in and default off — no
  network/telemetry the user did not initiate (BIZ-02, CRAN no-phone-home).
- Green gate re-runs the full `R CMD check` that Phase 6's deferred CRAN-02 note asked to
  confirm clean.

</specifics>

<deferred>
## Deferred Ideas

- The actual Advisor Pro RAG corpus + managed hosting (PRO-01..02) — future, waitlist-gated.
- MCP server surface (SURF-01) — deferred to a future milestone.

</deferred>
