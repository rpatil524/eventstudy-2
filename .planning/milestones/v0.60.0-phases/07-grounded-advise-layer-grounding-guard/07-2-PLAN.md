---
phase: 07-grounded-advise-layer-grounding-guard
plan: 2
type: execute
wave: 2
depends_on: [07-1]
files_modified:
  - R/report.R
  - inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd
  - tests/testthat/test_report_advice.R
  - man/generate_report.Rd
autonomous: true
requirements: [ADV-07]
estimate:
  tokens: 34000
  raw_tokens: 18000
  tasks: 2
  confidence: high
must_haves:
  truths:
    - "generate_report(advice = NULL) (the default) renders the byte-identical existing path — no new section, existing params untouched (ADV-07)"
    - "generate_report(task, advice = <grounded Advice>) renders a NEW guarded 'AI Advisor Interpretation' section from the Advice object (ADV-07)"
    - "generate_report(task, advice = <non-Advice>) skips the section + emits exactly one warning, never breaks the report (graceful degrade)"
    - "The existing report test suite stays green; the advice param is trailing (before ...) so positional/named callers are unaffected"
  artifacts:
    - tests/testthat/test_report_advice.R
  key_links:
    - "generate_report advice param -> rmarkdown::render params$advice -> skeleton.Rmd guarded eval= chunk"
    - "The chunk eval= is FALSE when advice is NULL, guaranteeing the unchanged render path"
---

<objective>
Wire `report_writing` output into `generate_report()` via one trailing optional `advice = NULL` param and one guarded rmarkdown chunk in skeleton.Rmd — the existing render path stays byte-identical, a supplied grounded `Advice` renders a new section, and invalid advice degrades gracefully.

Purpose: Close ADV-07 — the report-writing task type's grounded narrative becomes consumable by the report generator without touching any existing param or section.
Output: surgical `R/report.R` change, one new skeleton.Rmd chunk, dedicated backward-compat + render tests.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/07-grounded-advise-layer-grounding-guard/07-RESEARCH.md
@R/report.R
@R/advise.R
@./.claude/CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add advice = NULL param to generate_report + guarded skeleton.Rmd section</name>
  <files>R/report.R, inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd</files>
  <read_first>
    - R/report.R:23-108 (full generate_report signature + the params list at 91-99 + rmarkdown::render call)
    - inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd:11-18 (params block) and :187 (appendix-section chunk — the advice chunk goes BEFORE appendix)
    - 07-RESEARCH.md Finding 5 (verbatim advice param, params-list addition, validation block, skeleton.Rmd chunk)
    - R/advise.R (Advice field shape: source, is_deterministic, interpretation, recommendations[] with action/rationale/expected_effect, caveats)
  </read_first>
  <action>
    1. R/report.R: add `advice = NULL` as a trailing param BEFORE `...` (after `interactive = TRUE`). Add the roxygen `@param advice` line documenting it accepts a grounded `Advice` object from `es_advise(task_type="report_writing")`; NULL (default) renders the unchanged report.

    2. Before the `rmarkdown::render` call, add the validation block from 07-RESEARCH.md Finding 5: `if (!is.null(advice) && !inherits(advice, "Advice")) { warning("generate_report(): 'advice' is not an Advice object — advice section will be skipped.", call.=FALSE); advice <- NULL }`.

    3. Add `advice = advice` as a new entry in the `params = list(...)` passed to `rmarkdown::render` (after `interactive = interactive`).

    4. skeleton.Rmd: add `advice: NULL` to the `params:` block (line 11-18 area). Add a new chunk `advice-section` BEFORE the `appendix-section` chunk (line 187) with `results='asis', eval=!is.null(params$advice) && inherits(params$advice, "Advice")` rendering the section per 07-RESEARCH.md Finding 5 (heading "## AI Advisor Interpretation", source/deterministic line, Interpretation subsection when non-empty, Recommendations loop over action/rationale/expected_effect, Caveats loop). Because eval= is FALSE when advice is NULL, the existing render path is byte-identical.

    Run devtools::document() to refresh man/generate_report.Rd. Confirm the params list still passes `sections` and every pre-existing key unchanged.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); f <- formals(generate_report); stopifnot("advice" %in% names(f), is.null(f$advice)); cat("advice trailing param OK\n")'</automated>
    <fails_when>non-zero exit, advice not present in formals, or advice default is not NULL</fails_when>
  </verify>
  <done>generate_report gains a trailing advice=NULL param and passes it into render params; skeleton.Rmd has a guarded advice-section chunk before appendix; NULL default leaves the render path byte-identical; committed.</done>
</task>

<task type="auto">
  <name>Task 2: Backward-compat + render-integration + degrade tests; full-suite gate</name>
  <files>tests/testthat/test_report_advice.R</files>
  <read_first>
    - R/report.R (Task 1 output — the validation block + params addition)
    - 07-RESEARCH.md Finding 5 (backward-compat guarantee) and Finding 6 (.make_test_diag / Advice fixture; reuse helper-advice-fixtures.R from 07-1)
    - tests/testthat/test_advise.R (how an Advice object is produced via CustomProvider for a render fixture)
  </read_first>
  <action>
    Create tests/testthat/test_report_advice.R:

    1. Backward-compat: assert `advice` is a trailing formal defaulting NULL and that the existing `params` list keys (task,title,author,sections,cross_sectional,confidence_level,interactive) are all still present — verify via `body(generate_report)` inspection or by asserting formals order (advice after interactive). No behavior change on the NULL path.

    2. Degrade: `expect_warning(generate_report(<any placeholder>, advice = list(not="advice")), "not an Advice object")` — assert the validation coerces advice to NULL and warns exactly once. Skip the actual render (guard rmarkdown/knitr with `skip_if_not_installed`) so the test targets the validation branch, not a full render.

    3. Render integration (guarded `skip_if_not_installed("rmarkdown"); skip_if_not_installed("knitr"); skip_on_cran()`): build a small grounded `Advice` (reuse the CustomProvider canned-JSON path from 07-1's helper) and render a minimal report to a tempfile; assert the output file exists and contains "AI Advisor Interpretation". If constructing a fully-fitted task fixture is heavy, assert instead that the skeleton chunk's eval condition string is present in skeleton.Rmd and that a NULL-advice render omits the section — keep the deterministic assertion, defer heavy rendering behind skip guards.

    4. Run the full suite; confirm 1793 baseline stays green (report change is additive on the NULL path).
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_report_advice.R")' && Rscript -e 'devtools::test()'</automated>
    <fails_when>non-zero exit, any FAIL line, the degrade case does not warn exactly once, or the full-suite pass count regresses below 1793</fails_when>
  </verify>
  <done>NULL-advice render path proven unchanged; invalid advice degrades with one warning; a supplied grounded Advice renders the new section (behind CRAN/skip guards); full suite green; committed.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| caller -> generate_report(advice=) | a caller may pass a non-Advice object as advice |
| Advice -> skeleton.Rmd chunk | advice fields rendered as markdown via cat() |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-07-05 | Tampering | non-Advice object passed as advice breaks the render | medium | mitigate | `inherits(advice,"Advice")` validation coerces to NULL + one warning; the chunk eval= also re-checks inherits, double-guarding |
| T-07-06 | Denial of Service | malformed Advice fields crash the Rmd chunk | low | mitigate | chunk uses `%||%` fallbacks and length()/nzchar() guards on every field; empty lists render nothing, no crash |
</threat_model>

<verification>
- `formals(generate_report)` includes trailing `advice` defaulting NULL.
- NULL-advice render path is byte-identical (chunk eval=FALSE); existing report tests green.
- Non-Advice input -> one "not an Advice object" warning + section skipped.
- Grounded Advice -> "AI Advisor Interpretation" section rendered (behind skip guards).
- `devtools::test()` stays at 1793 pass / 0 fail.
</verification>

<success_criteria>
- ADV-07 satisfied: report_writing output consumable by generate_report via a trailing advice=NULL param and a guarded template section; existing render path unchanged; invalid advice degrades gracefully.
</success_criteria>

<output>
Create `.planning/phases/07-grounded-advise-layer-grounding-guard/07-02-SUMMARY.md` when done.
</output>
