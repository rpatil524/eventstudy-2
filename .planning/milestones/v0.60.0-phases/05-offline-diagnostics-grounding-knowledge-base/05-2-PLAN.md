---
phase: 05-offline-diagnostics-grounding-knowledge-base
plan: 02
type: execute
wave: 2
depends_on: ["05-01"]
files_modified:
  - R/knowledge_base.R
  - tests/testthat/test_knowledge_base.R
  - NAMESPACE
autonomous: true
requirements: [KB-01, KB-02, KB-03, KB-04]
estimate:
  tokens: 60000
  raw_tokens: 32000
  tasks: 2
  confidence: med
must_haves:
  truths:
    - "Each KB decision-table rule is a pure-R data structure carrying its academic citation (MacKinlay, Brown & Warner, Patell, BMP, Kolari-Pynnonen) and has a unit test asserting it fires on the correct diagnostic condition (e.g. Shapiro-Wilk rejection steers toward non-parametric tests, event-window overlap steers toward Kolari-Pynnonen) [KB-01, KB-02, KB-03]"
    - "The KB data structure is exported and serializable, ready for Phase 7 system-prompt injection — KB-04's actual prompt-injection behavior is a Phase 7 deliverable and is explicitly NOT implemented here [KB-04, scoped]"
  artifacts:
    - "R/knowledge_base.R — EVENTSTUDY_KB list of rule records + es_kb() accessor + .kb_rule() constructor/validator"
    - "tests/testthat/test_knowledge_base.R — per-rule firing tests + citation-field integrity tests"
    - "NAMESPACE — exports es_kb accessor"
  key_links:
    - "Each rule$condition is a function(diag) evaluated against the es_diagnostics list shape from Plan 05-1 — the field names it reads MUST match that list's documented @return"
    - "condition predicates must treat NA stat values as 'insufficient data' and NOT fire, per STATS-04 (n_valid_events<=1 yields NA by design)"
---

<objective>
Deliver the pure-R grounding knowledge base: `EVENTSTUDY_KB`, an in-package list of rule records mapping diagnostic conditions (read from the `es_diagnostics` list of Plan 05-1) to grounded methodological recommendations, each carrying a structured academic citation and a severity. Provide an exported accessor `es_kb()` and a unit test per rule asserting it fires on the correct diagnostic condition.

Purpose: The KB is the load-bearing correctness layer — it encodes the assumption→test-statistic methodology (Shapiro-Wilk → Patell/non-parametric; variance increase → BMP; overlap → Kolari-Pynnonen) that the offline advice functions (Plan 05-3) and the Phase 7 LLM layer both ground against. Correctness of every citation and firing condition is verified by test.
Output: `R/knowledge_base.R`, `tests/testthat/test_knowledge_base.R`, regenerated NAMESPACE.

Scope note (KB-04): Phase 5 delivers ONLY the KB data structure — exported, serializable, and ready for Phase 7 to inject into a system prompt. The actual prompt-injection behavior is a Phase 7 deliverable and is deliberately out of scope here. State this in the roxygen so verification does not expect injection code in Phase 5.
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
</context>

<artifacts_this_phase_produces>
This plan (05-2) produces:
- `EVENTSTUDY_KB` — package-level pure-R list of rule records, each with fields: `id`, `category` ("stat_choice" | "robustness"), `condition` (function(diag) -> logical), `recommendation` (character), `citation` (list of author/year/key/venue), `severity` ("info"|"warning"|"error")
- `es_kb()` — exported accessor returning the KB list (so external code / Phase 7 can read it without touching an internal object)
- `.kb_rule(...)` — `@noRd` constructor that validates a rule record has all required fields
- New file `R/knowledge_base.R`
- New test file `tests/testthat/test_knowledge_base.R`

Plan 05-3 (recommend_stat / flag_robustness) consumes `EVENTSTUDY_KB`, filtering by the `category` field. The `category` field is introduced here per 05-RESEARCH open-question 2 (Claude's discretion).
</artifacts_this_phase_produces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: EVENTSTUDY_KB rule records + .kb_rule() validator + es_kb() accessor</name>
  <files>R/knowledge_base.R, tests/testthat/test_knowledge_base.R, NAMESPACE</files>
  <read_first>
    - 05-RESEARCH.md "Literature-Grounded KB Decision Table" (the 8 rules: KB-NORM-PATELL, KB-NONNORM-NONPAR, KB-VAR-INCREASE-BMP, KB-OVERLAP-KP, KB-AC-WARN, KB-LOWFIT-WARN, KB-DEGEN-EVENTS, KB-PRETREND, KB-SMALL-N — with conditions, steering, citations, and [ASSUMED] threshold flags)
    - 05-RESEARCH.md "Pattern 2: KB Rule Record Structure" and "Example: KB rule record structure" (field layout: id, condition, recommendation, citation list, severity)
    - 05-RESEARCH.md "Citation provenance notes" (which citations are [VERIFIED] vs [ASSUMED])
    - R/multi_event_test_statistics.R:569-572 (KolariPynnonenTest roxygen citing Kolari & Pynnonen 2010 — canonical citation string to reuse), :412-418 (BMPTest citation)
    - R/es_diagnostics.R (the es_diagnostics list @return — the exact field paths conditions must read: estimation_window$shapiro_p, $dw_stat, $r2; cross_sectional$n_overlap_pairs, $n_valid_events; meta$n_events_total)
    - 05-RESEARCH.md "Common Pitfalls" 6 (NA stat values must NOT fire robustness rules)
  </read_first>
  <behavior>
    - Test: es_kb() returns a list of length >= 8; every element passes .kb_rule field validation (has id, category, condition, recommendation, citation, severity).
    - Test: every rule$citation has non-empty author (character), integer-ish year, and non-empty key; the five required authorities (MacKinlay, Brown & Warner, Patell, BMP/Boehmer, Kolari & Pynnonen) each appear in at least one rule's citation.
    - Test: every rule$condition is a function of one argument and returns a length-1 logical (or NA) when applied to a minimal diagnostics fixture; no condition errors on a fixture with NA-filled signals.
    - Test: rule ids are unique; every severity is one of info/warning/error; every category is one of stat_choice/robustness.
  </behavior>
  <action>
    Create R/knowledge_base.R. Define .kb_rule(id, category, condition, recommendation, citation, severity) @noRd that validates presence/type of every field and stop()s with a clear message on a malformed rule. Build EVENTSTUDY_KB as a package-level list assembled by calling .kb_rule() for each of the rules in 05-RESEARCH's decision table (minimum: KB-NORM-PATELL, KB-NONNORM-NONPAR, KB-VAR-INCREASE-BMP, KB-OVERLAP-KP, KB-AC-WARN, KB-LOWFIT-WARN, KB-DEGEN-EVENTS, KB-SMALL-N; include KB-PRETREND if pretrend signal is available in the diagnostics, else omit and note why). Each condition reads only fields documented in R/es_diagnostics.R's @return and guards NA with na.rm/isTRUE so NA signals never fire a rule (pitfall 6). Assign category: stat_choice for rules that steer WHICH test to use (KB-NORM-PATELL, KB-NONNORM-NONPAR, KB-VAR-INCREASE-BMP, KB-OVERLAP-KP), robustness for data-quality rules (KB-AC-WARN, KB-LOWFIT-WARN, KB-DEGEN-EVENTS, KB-SMALL-N). Citations use the structured list(author, year, key, venue) shape, reusing the verified Kolari-Pynnonen and BMP citation strings from the package roxygen. Add exported es_kb() returning EVENTSTUDY_KB with @export and @return roxygen, and a roxygen note that KB-04 (system-prompt injection) is delivered as "structure exported and serializable, ready for Phase 7" only. Document each [ASSUMED] threshold in the recommendation or roxygen as adjustable. Regenerate NAMESPACE. Add NO package to Imports/Suggests. Create tests/testthat/test_knowledge_base.R with the four behavior tests.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_knowledge_base.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. a rule missing a citation field, a duplicate id, a condition that errors on an NA fixture, or a missing required authority.</fails_when>
  </verify>
  <acceptance_criteria>
    - R/knowledge_base.R defines a list EVENTSTUDY_KB of rule records each with fields id/category/condition/recommendation/citation/severity.
    - es_kb() is exported (NAMESPACE contains export(es_kb)).
    - The five required academic authorities each appear in at least one rule citation.
    - Every condition is NA-safe (returns a scalar logical, never errors, never fires on NA input).
    - testthat::test_file("tests/testthat/test_knowledge_base.R") exits 0 with 0 failures.
    - git diff DESCRIPTION is empty (KB is pure base R).
  </acceptance_criteria>
  <reversibility rating="reversible">New additive data structure + accessor; no existing behavior changed.</reversibility>
  <done>EVENTSTUDY_KB exists with >= 8 validated, cited rule records, es_kb() is exported, and structural tests are green.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Per-rule firing tests — each rule fires on the correct diagnostic condition and stays silent otherwise</name>
  <files>tests/testthat/test_knowledge_base.R, R/knowledge_base.R</files>
  <read_first>
    - R/es_diagnostics.R (es_diagnostics @return — to build minimal hand-crafted diagnostics fixtures that set exactly the fields each rule reads)
    - tests/testthat/helper-mock-data.R:130-134 (create_fitted_mock_task), :164-201 (degenerate factories, for an integration-style firing test through a real es_diagnostics object)
    - 05-RESEARCH.md "Literature-Grounded KB Decision Table" (each rule's exact firing condition and threshold — the assertions to encode)
    - R/knowledge_base.R (the rules as implemented in Task 1)
  </read_first>
  <behavior>
    - Test (per rule, positive): a hand-crafted diagnostics fixture that satisfies the rule's condition makes that rule's condition(diag) return TRUE. E.g. KB-NONNORM-NONPAR: estimation_window$shapiro_p mostly < 0.05 → TRUE; KB-OVERLAP-KP: cross_sectional$n_overlap_pairs > 0 → TRUE; KB-DEGEN-EVENTS: n_valid_events/n_events_total < 0.8 → TRUE.
    - Test (per rule, negative): a fixture that does NOT satisfy the condition (e.g. all shapiro_p > 0.05 for the non-normality rule, n_overlap_pairs == 0 for the overlap rule) makes that rule's condition(diag) return FALSE.
    - Test (NA guard): a fixture with the relevant signal all-NA makes each robustness condition return FALSE (does not fire on missing data).
    - Test (integration): es_diagnostics(create_fitted_mock_task()) fed through each condition never errors.
  </behavior>
  <action>
    Extend tests/testthat/test_knowledge_base.R with a positive and a negative firing test for every rule in EVENTSTUDY_KB, building minimal named-list diagnostics fixtures (a small helper inside the test file that constructs an es_diagnostics-shaped list with only the fields a rule reads). Assert the specific literature-grounded steering in the recommendation text for the two named success-criterion cases: Shapiro-Wilk rejection → recommendation mentions a non-parametric alternative (Sign/Rank/Corrado); n_overlap_pairs>0 → recommendation mentions Kolari-Pynnonen. Add the NA-guard test (all-NA signal → FALSE) and one integration test that runs every rule's condition over a real es_diagnostics(create_fitted_mock_task()) object catching any error. Do not modify R/knowledge_base.R except to fix any genuine rule bug surfaced by these tests.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_knowledge_base.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. a rule fires on its negative fixture, fails to fire on its positive fixture, fires on all-NA input, or the Shapiro/overlap steering assertion does not match the recommendation text.</fails_when>
  </verify>
  <acceptance_criteria>
    - Every rule in EVENTSTUDY_KB has both a positive-firing and a negative-non-firing test (KB-03).
    - The Shapiro-Wilk-rejection rule's recommendation names a non-parametric alternative; the overlap rule's recommendation names Kolari-Pynnonen (the two named success-criterion mappings).
    - All-NA fixtures fire no rule.
    - Running every rule condition over a real es_diagnostics object raises no error.
    - testthat::test_file("tests/testthat/test_knowledge_base.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <done>Each KB rule has a passing test asserting it fires on its correct diagnostic condition and stays silent otherwise, including the two named literature mappings.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| es_diagnostics list → KB condition predicates | Predicates read a plain in-memory list produced by the package; no external input, no eval of user strings, no network. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-05-04 | Tampering | KB citation correctness | medium | mitigate | KB correctness is load-bearing: every rule carries a structured citation verified against the primary literature, and per-rule firing tests lock the assumption→test mapping so a future edit that breaks a mapping fails CI. |
| T-05-05 | Tampering | new package deps | high | mitigate | KB is pure base R; acceptance criteria assert git diff DESCRIPTION empty. No package install → no legitimacy audit required. |
| T-05-06 | Information Disclosure | KB / es_kb output | low | mitigate | The KB is static literature/methodology text and predicates; it reads no environment variables, keys, or secrets — verified: no Sys.getenv/file reads in R/knowledge_base.R. |

Phase 5 KB layer opens no network surface and processes only in-memory diagnostics at ASVS L1; the one genuine concern is citation/mapping correctness (T-05-04), mitigated by the per-rule test net.
</threat_model>

<verification>
- Per task: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_knowledge_base.R")'` → 0 failures.
- Phase gate: `Rscript -e 'devtools::test()'` (1378 existing tests green) and `Rscript -e 'devtools::check(document=TRUE)'` (no new NOTEs/WARNINGs).
- `git diff DESCRIPTION` empty.
</verification>

<success_criteria>
- Each KB rule is a pure-R record with a structured academic citation and a unit test asserting correct firing [KB-01, KB-02, KB-03].
- The KB structure is exported and serializable, ready for Phase 7 injection; injection itself is out of scope [KB-04, scoped].
</success_criteria>

<output>
Create `.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-02-SUMMARY.md` when done.
</output>
