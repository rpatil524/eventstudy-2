---
phase: 05-offline-diagnostics-grounding-knowledge-base
plan: 03
type: execute
wave: 3
depends_on: ["05-01", "05-02"]
files_modified:
  - R/advise_offline.R
  - tests/testthat/test_advise_offline.R
  - NAMESPACE
autonomous: true
requirements: [ADV-08, CRAN-01, CRAN-05]
estimate:
  tokens: 60000
  raw_tokens: 32000
  tasks: 2
  confidence: med
must_haves:
  truths:
    - "Requesting rule-based advice (recommend_stat / flag_robustness) with no provider returns a grounded recommendation driven purely by the KB decision table — e.g. Shapiro-Wilk rejection steers toward non-parametric tests, event-window overlap steers toward Kolari-Pynnonen — and NEVER errors just because no provider is configured [ADV-08]"
    - "Both functions accept EITHER a fitted task OR a precomputed es_diagnostics object and return the same Advice-shaped S3 object the Phase 7 LLM layer will reuse, flagged deterministic/offline [ADV-08]"
    - "Zero new hard dependencies; existing valid-input pipeline behavior byte-identical [CRAN-01, CRAN-05]"
  artifacts:
    - "R/advise_offline.R — recommend_stat()/flag_robustness() S3 generics + .EventStudyTask/.es_diagnostics methods + .build_offline_advice() + print.es_advice()"
    - "tests/testthat/test_advise_offline.R — task-input, diagnostics-input, no-provider, and severity-ranking coverage"
    - "NAMESPACE — exports recommend_stat, flag_robustness generics+methods, print.es_advice"
  key_links:
    - "recommend_stat filters EVENTSTUDY_KB by category=='stat_choice'; flag_robustness by category=='robustness' — both run the same .build_offline_advice() over the filtered rules"
    - "the es_advice object shape (source, is_deterministic, rules_matched[], diagnostics_ref) is the Phase 7-compatible Advice contract"
---

<objective>
Deliver the offline, non-LLM advice surface: two exported functions `recommend_stat()` and `flag_robustness()` that evaluate the KB decision table (Plan 05-2) against a diagnostics object (Plan 05-1) and return a grounded, severity-ranked `es_advice` S3 object — the same `Advice`-shaped contract the Phase 7 LLM layer will reuse. Both accept either a fitted task or a precomputed `es_diagnostics`, and neither ever errors merely because no LLM provider is configured.

Purpose: This is the always-available rule-based fallback (ADV-08). It closes the offline grounding loop: fitted task → diagnostics → KB rules → grounded advice with citations, no API key, no network, no new dependency.
Output: `R/advise_offline.R`, `tests/testthat/test_advise_offline.R`, regenerated NAMESPACE.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-CONTEXT.md
@.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-RESEARCH.md
@./.claude/CLAUDE.md
@R/es_diagnostics.R
@R/knowledge_base.R
</context>

<artifacts_this_phase_produces>
This plan (05-3) produces:
- `recommend_stat(x, ...)` — exported S3 generic + `.EventStudyTask` and `.es_diagnostics` methods; evaluates category=="stat_choice" KB rules
- `flag_robustness(x, ...)` — exported S3 generic + `.EventStudyTask` and `.es_diagnostics` methods; evaluates category=="robustness" KB rules
- `.build_offline_advice(diag, rules)` — `@noRd` engine: filters/evaluates rules, severity-ranks matches, assembles the es_advice object
- `print.es_advice(x, ...)` — exported S3 print method (cat-based)
- The `es_advice` object shape (the Phase 7-compatible Advice contract): list(source, is_deterministic, rules_matched[], diagnostics_ref)
- New file `R/advise_offline.R`
- New test file `tests/testthat/test_advise_offline.R`
</artifacts_this_phase_produces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: recommend_stat/flag_robustness generics + methods + es_advice object + print</name>
  <files>R/advise_offline.R, tests/testthat/test_advise_offline.R, NAMESPACE</files>
  <read_first>
    - 05-RESEARCH.md "Pattern 3: Advice Object Shape" and "Example: recommend_stat() skeleton" (generic + .EventStudyTask/.es_diagnostics dispatch; Filter over KB; severity ordering error>warning>info; es_advice class)
    - R/es_diagnostics.R (es_diagnostics() signature — the task-input method calls it then dispatches to the diagnostics method; @return shape read by conditions)
    - R/knowledge_base.R (es_kb()/EVENTSTUDY_KB and the category field for filtering; rule fields available to surface in advice)
    - R/simulation.R:145-157 and R/cross_sectional.R:130-191 (print.es_* cat convention + invisible(x) to COPY)
    - 05-RESEARCH.md "Common Pitfalls" 6 (NA stat values → no fire) and 05-CONTEXT.md "No-provider behavior" locked decision
  </read_first>
  <behavior>
    - Test: recommend_stat(create_fitted_mock_task()) returns an object with inherits(x, "es_advice") TRUE, x$source == "offline_kb", x$is_deterministic == TRUE, and x$rules_matched a list.
    - Test: recommend_stat.es_diagnostics(es_diagnostics(task)) returns the SAME shape (task-input path and diagnostics-input path agree on structure).
    - Test: flag_robustness(task) returns an es_advice whose matched rules are all category=="robustness"; recommend_stat(task) matched rules are all category=="stat_choice".
    - Test: with a provider argument passed but unset/NULL, recommend_stat and flag_robustness still return offline advice and do NOT error (no-provider guarantee).
    - Test: capture.output(print(advice)) is non-empty and lists each matched rule's id + severity + citation key.
  </behavior>
  <action>
    Create R/advise_offline.R. Define recommend_stat() and flag_robustness() as S3 generics (UseMethod), each with a .EventStudyTask method that calls es_diagnostics(x, ...) then delegates to the .es_diagnostics method, and a .es_diagnostics method that calls the shared engine .build_offline_advice(x, rules) with rules = Filter(category matches) over es_kb(). recommend_stat filters category=="stat_choice"; flag_robustness filters category=="robustness". .build_offline_advice evaluates each rule$condition inside tryCatch(..., error=function(e) FALSE) (so a bad predicate never aborts), keeps all matches (not first-match — locked decision), severity-ranks them error>warning>info, and returns list(source="offline_kb", is_deterministic=TRUE, rules_matched=<ranked matched records with id/recommendation/citation/severity/category>, diagnostics_ref=<the diag list>) classed "es_advice". Accept but ignore a provider=NULL argument in the signature so the Phase 7 call shape is forward-compatible and no-provider never errors. Add exported print.es_advice using cat(), printing source, deterministic flag, and each matched rule (id, severity, citation$key, recommendation) with invisible(x). Roxygen @export on both generics, both method sets, and print.es_advice; @return documents the es_advice contract. Regenerate NAMESPACE. Add NO package to Imports/Suggests. Create tests/testthat/test_advise_offline.R with the five behavior tests.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise_offline.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. no-provider call errors, task and diagnostics input paths diverge in shape, category filtering leaks a wrong-category rule, or es_advice not classed/printed.</fails_when>
  </verify>
  <acceptance_criteria>
    - recommend_stat and flag_robustness are exported generics with .EventStudyTask and .es_diagnostics methods (NAMESPACE has the exports + S3method(print,es_advice)).
    - Both accept a fitted task OR an es_diagnostics object and return an es_advice object of identical shape.
    - With no provider configured, neither function errors — both return offline KB advice flagged is_deterministic=TRUE, source="offline_kb".
    - recommend_stat surfaces only stat_choice rules; flag_robustness only robustness rules; matches are severity-ranked (error first).
    - testthat::test_file("tests/testthat/test_advise_offline.R") exits 0 with 0 failures; git diff DESCRIPTION empty.
  </acceptance_criteria>
  <reversibility rating="reversible">New additive exports; no existing pipeline function modified (CRAN-05).</reversibility>
  <done>recommend_stat/flag_robustness return a grounded, severity-ranked es_advice object from either input, never error without a provider, and tests are green.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Grounded-steering assertions + degenerate-input safety + full-suite / check gate</name>
  <files>tests/testthat/test_advise_offline.R, R/advise_offline.R</files>
  <read_first>
    - tests/testthat/helper-mock-data.R:130-134 (create_fitted_mock_task), :164-201 (degenerate factories to build a task with an unfitted / NA event for a robustness-firing integration test)
    - R/knowledge_base.R (which rule ids carry the Shapiro→non-parametric and overlap→Kolari-Pynnonen steering)
    - R/advise_offline.R (the engine + methods from Task 1)
    - 05-RESEARCH.md "Validation Architecture" (per-task / per-wave / phase-gate sampling: devtools::test filter, full devtools::test, devtools::check)
  </read_first>
  <behavior>
    - Test (steering, integration): build/craft diagnostics where estimation-window residuals are non-normal (shapiro_p mostly < 0.05); recommend_stat returns an es_advice whose rules_matched includes the non-parametric-steering rule and whose recommendation text names a non-parametric alternative.
    - Test (steering, integration): craft diagnostics with n_overlap_pairs > 0; recommend_stat's matched rules include the Kolari-Pynnonen rule with its citation key.
    - Test (degenerate safety): recommend_stat and flag_robustness on a task containing a degenerate/unfitted event and with no API key present return without error and produce a valid es_advice (flag_robustness surfaces the degenerate-events rule).
    - Test (serializable): rules_matched carries only plain scalars/strings/lists (no distributional/environment objects); skip_if_not_installed("jsonlite") then jsonlite::toJSON(advice, null="null") does not error.
  </behavior>
  <action>
    Extend tests/testthat/test_advise_offline.R with the grounded-steering integration tests (Shapiro rejection → non-parametric rule present; overlap → Kolari-Pynnonen rule present), the degenerate/no-API-key safety test (build a task including a degenerate event via the helper factories and assert no error + valid es_advice + robustness rule fires), and the serializability test (jsonlite guarded, Suggests-only). Fix any genuine bug these surface in R/advise_offline.R only. Then run the full suite and check gate to confirm CRAN-05 (1378 existing tests green, valid-input behavior byte-identical) and CRAN-01 (zero new hard deps, no new NOTEs/WARNINGs).
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise_offline.R")' && Rscript -e 'devtools::test()'</automated>
    <fails_when>testthat reports FAIL > 0 on the new file OR the full devtools::test() run shows any FAIL (a regression in the existing 1378 tests), or Rscript exits non-zero.</fails_when>
  </verify>
  <acceptance_criteria>
    - Non-normality diagnostics steer recommend_stat toward a non-parametric test (rule present, recommendation names Sign/Rank/Corrado); overlap diagnostics steer toward Kolari-Pynnonen (ADV-08 named cases).
    - On a degenerate/NA task with no API key, both functions return a valid es_advice without error.
    - advice$rules_matched is JSON-serializable (jsonlite::toJSON does not error under skip_if_not_installed guard).
    - devtools::test() shows all existing 1378 tests still passing (CRAN-05).
    - git diff DESCRIPTION is empty (CRAN-01).
  </acceptance_criteria>
  <done>Grounded steering and degenerate-input safety are proven by test, the full existing suite stays green, and the offline advice loop is complete.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| task/es_diagnostics → advice functions | In-memory package objects; predicates evaluated over a local list. No provider, no network, no key read in the offline path. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-05-07 | Information Disclosure | es_advice object | low | mitigate | The advice object is built only from KB rules + diagnostics; it never reads API keys or environment secrets and carries none — verified: no Sys.getenv/file reads in R/advise_offline.R (offline path). The provider arg is accepted but unused here. |
| T-05-08 | Denial of Service | malformed rule predicate | low | mitigate | Each rule$condition runs inside tryCatch → FALSE, so a bad predicate degrades to "no fire" rather than crashing the advice call (ADV-08 never-error guarantee). |
| T-05-09 | Tampering | new package deps | high | mitigate | Offline advice is pure base R; acceptance criteria assert git diff DESCRIPTION empty. jsonlite used only in a Suggests-guarded test. No install → no legitimacy audit. |

Phase 5 advice layer opens no network surface and processes only in-memory objects at ASVS L1; no applicable high-severity threat beyond dependency integrity (T-05-09). The offline path is guaranteed key-free by construction.
</threat_model>

<verification>
- Per task: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise_offline.R")'` → 0 failures.
- Phase gate: `Rscript -e 'devtools::test()'` → all 1378 existing tests green (CRAN-05); `Rscript -e 'devtools::check(document=TRUE)'` → no new NOTEs/WARNINGs, zero new hard deps (CRAN-01).
- `git diff DESCRIPTION` empty.
</verification>

<success_criteria>
- recommend_stat / flag_robustness with no provider return grounded, KB-driven, severity-ranked advice and never error [ADV-08].
- Both accept a fitted task or an es_diagnostics object and return the Phase 7-compatible es_advice contract [ADV-08].
- Zero new hard dependencies; existing valid-input behavior byte-identical [CRAN-01, CRAN-05].
</success_criteria>

<output>
Create `.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-03-SUMMARY.md` when done.
</output>
