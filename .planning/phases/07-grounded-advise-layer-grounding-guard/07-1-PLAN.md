---
phase: 07-grounded-advise-layer-grounding-guard
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - R/advise.R
  - tests/testthat/test_advise.R
  - tests/testthat/helper-advice-fixtures.R
  - NAMESPACE
  - man/es_advise.Rd
autonomous: true
requirements: [ADV-01, ADV-02, ADV-03, ADV-04, ADV-05, ADV-06]
estimate:
  tokens: 78000
  raw_tokens: 42000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "es_advise(diagnostics, task_type, provider) returns an Advice S3 object with a print method (ADV-01)"
    - "A recommendation citing a diagnostic key absent from the es_diagnostics is dropped; the rest are kept; exactly ONE warning fires; a caveat records N drops (ADV-04, drop-and-keep)"
    - "A recommendation whose evidence value mismatches the diagnostics value beyond tolerance is dropped identically (ADV-04)"
    - "es_advise(task_type='interpret', provider=NULL) errors clearly with 'requires a provider' — never NA/silent (ADV-06)"
    - "es_advise(task_type='recommend_stat', provider=NULL) returns the unchanged Phase 5 es_advice object (offline path preserved)"
    - "Malformed/empty/NA provider JSON degrades to one warning + empty Advice, never crashes (never-crash contract)"
    - "Existing 1793-test suite stays green; package loads with jsonlite/httr2 UNINSTALLED"
  artifacts:
    - R/advise.R
    - tests/testthat/test_advise.R
    - tests/testthat/helper-advice-fixtures.R
  key_links:
    - ".resolve_diag_key() dotted-path resolver into the six es_diagnostics sections is the sole ground-truth lookup the guard trusts"
    - ".validate_grounding() is the SINGLE warning-emitting point for guard drops (mirrors .provider_failure single-warning discipline)"
    - "provider$complete(prompt, schema) es_provider_response.text -> jsonlite::fromJSON(simplifyVector=FALSE) -> Advice list"
---

<objective>
Build the grounded advise engine: the `Advice` S3 object, the runtime grounding guard, per-task-type routing, and the KB→evidence bridge — proven end-to-end by a tracer slice through the full `es_advise()` pipeline (CustomProvider canned JSON → parse → guard → Advice) before expanding to all six task types and the KB-grounds/LLM-interprets path.

Purpose: Deliver the grounding guarantee — every claim `es_advise()` returns is provably tied to a diagnostic the package actually computed, enforced in R independent of the prompt (ADV-01..06).
Output: `R/advise.R` (es_advise, print.Advice, all @noRd guard/prompt/evidence helpers), deterministic guard regression tests, NAMESPACE exports.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/07-grounded-advise-layer-grounding-guard/07-CONTEXT.md
@.planning/phases/07-grounded-advise-layer-grounding-guard/07-RESEARCH.md
@R/advise_offline.R
@R/es_diagnostics.R
@R/provider.R
@R/knowledge_base.R
@R/contract.R
@./.claude/CLAUDE.md
</context>

<tasks>

<task type="tracer">
  <name>Task 1: End-to-end tracer — es_advise(recommend_stat) through CustomProvider canned JSON, parsed, guarded, returned as Advice</name>
  <files>R/advise.R, tests/testthat/helper-advice-fixtures.R, tests/testthat/test_advise.R</files>
  <read_first>
    - R/advise_offline.R:221-229 (es_advice structure — share source/is_deterministic field names; Advice is a DIFFERENT class "Advice")
    - R/advise_offline.R:145-169 (print.es_advice — the cat()-based invisible(x) pattern print.Advice mirrors)
    - R/es_diagnostics.R:83-98 (the six sections: meta, estimation_window, event_window, cross_sectional, contract_state, aggregate_summary and their exact key names)
    - R/provider.R:336-380 (CustomProvider$new(fn) — the offline test seam; complete(prompt,schema) returns es_provider_response with $text)
    - R/provider.R:27-81 (es_provider_response builders + .provider_failure single-warning point — the discipline .validate_grounding mirrors)
    - R/contract.R:74-97 (.handle_degenerate: one warning(msg, call.=FALSE) + invisible(FALSE), never stop())
    - 07-RESEARCH.md Findings 1, 3, 6 (Advice shape, guard algorithm verbatim, test fixture verbatim)
  </read_first>
  <action>
    Create R/advise.R with the thinnest complete path for ONE task type (recommend_stat with a provider). Wire every layer end-to-end; no other task types yet.

    1. `.empty_advice(source_label, task_type)` (@noRd): returns `structure(list(source=source_label, is_deterministic=FALSE, task_type=task_type, interpretation="", recommendations=list(), caveats=character(), n_dropped=0L), class="Advice")`.

    2. `.resolve_diag_key(diag, key_path)` (@noRd): parse `"section.key"` and `"section.key[i]"` (1-based index). Navigate `diag[[section]][[key]]`; apply `[[idx]]` when an index suffix is present. Return `NA_real_` when the section is NULL, the key is NULL, or the index is out of range. Implement per 07-RESEARCH.md Finding 3 verbatim (the perl-regex path parser).

    3. `.parse_advice_json(resp, source_label, task_type)` (@noRd): guard `requireNamespace("jsonlite", quietly=TRUE)` — absent -> one warning + `.empty_advice`. NA/empty `resp$text` -> one warning + `.empty_advice`. `tryCatch(jsonlite::fromJSON(resp$text, simplifyVector = FALSE), error=function(e) NULL)`; NULL or non-list -> one warning + `.empty_advice`. Return the parsed list otherwise. simplifyVector=FALSE is mandatory (07-RESEARCH.md Pitfall 3) — keeps recommendations/evidence as list-of-lists.

    4. `.validate_grounding(advice_list, diagnostics, abs_tol=getOption("EventStudy.guard_abs_tol",1e-6), rel_tol=getOption("EventStudy.guard_rel_tol",1e-4))` (@noRd): iterate recommendations; for each evidence entry resolve `actual <- .resolve_diag_key(diagnostics, ev$diagnostic_key)`; NA-vs-present is a mismatch (both directions); numeric compare via `abs(reported-actual) <= max(abs_tol, rel_tol*abs(actual))`; non-numeric via `identical()`. Drop the whole recommendation on any bad evidence. Emit exactly ONE `warning(sprintf("Grounding guard: %d recommendation(s) dropped ...", n_drop), call.=FALSE)` when n_drop>0, append a caveat recording N drops, set `advice_list$n_dropped <- n_drop`. Implement per 07-RESEARCH.md Finding 3 verbatim. This is the SINGLE warning point.

    5. `.build_advice_from_parsed(parsed, diagnostics, source_label, task_type)` (@noRd): assemble a `class="Advice"` list from the parsed JSON fields (interpretation, recommendations, caveats), set source/is_deterministic=FALSE/task_type/n_dropped=0L, then run `.validate_grounding()` and return the guarded list.

    6. `print.Advice(x, ...)` (@export): cat-based per 07-RESEARCH.md Finding 1 sketch (source, task_type, is_deterministic, n recommendations, `[GUARD] N dropped` line when n_dropped>0, interpretation, each recommendation's action/kind/expected_effect/evidence lines, caveats). Explicit `(No recommendations.)` branch when the list is empty (Pitfall 5). `invisible(x)`.

    7. `es_advise(diagnostics, task_type, provider=NULL, model=NULL, ...)` (@export) — MINIMAL tracer body: only handle `task_type=="recommend_stat"` WITH a provider for now. Build a fixed prompt string + `.advice_schema()` (the JSON-schema R list from 07-RESEARCH.md Finding 2), call `provider$complete(prompt, schema)`, parse via `.parse_advice_json`, build+guard via `.build_advice_from_parsed`, return the Advice. Leave a `# EXPAND (Task 2): other task types + KB grounding + no-provider routing` marker where routing will grow — this is a functionality gap, not an architectural one.

    8. Add `.advice_schema()` (@noRd) exactly per 07-RESEARCH.md Finding 2.

    Roxygen every @export; run `devtools::document()` to regenerate NAMESPACE + man/. All jsonlite touches stay inside requireNamespace guards (CRAN Suggests discipline). No dplyr/NSE — plain lists only, so no globalVariables() additions.

    Create tests/testthat/helper-advice-fixtures.R with `.make_test_diag()` and `CANNED_JSON_THREE_RECS` verbatim from 07-RESEARCH.md Finding 6 (valid rec A on cross_sectional.car_iqr; invalid rec B on absent key cross_sectional.kurtosis; invalid rec C on estimation_window.r2 value 0.99 vs actual ~0.45). Create tests/testthat/test_advise.R with the tracer test: feed CANNED_JSON_THREE_RECS via CustomProvider, assert Advice class, exactly rec A survives, n_dropped==2, caveat mentions "2 recommendation", and exactly one "Grounding guard" warning.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise.R")'</automated>
    <fails_when>non-zero exit, any FAIL line, or the guard-drop test does not observe exactly one "Grounding guard" warning with n_dropped==2</fails_when>
  </verify>
  <done>es_advise() runs one path end-to-end: CustomProvider canned JSON -> parse -> guard -> Advice S3; the three-rec regression proves only the grounded recommendation survives, a caveat records 2 drops, exactly one warning fires; committed.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Expand routing — all six task types, KB-grounds/LLM-interprets, no-provider stop() (ADV-05, ADV-06)</name>
  <files>R/advise.R, tests/testthat/test_advise.R</files>
  <read_first>
    - R/advise.R (Task 1 output — the routing marker and existing helpers)
    - R/advise_offline.R:43-129 (recommend_stat/flag_robustness .es_diagnostics dispatch — the offline path to return unchanged when provider=NULL)
    - R/knowledge_base.R:146-393 (es_kb() rule records: id/category/condition/recommendation/citation/severity; condition bodies define the KB_KEY_MAP)
    - R/knowledge_base.R:420-421 (KB note: drop the condition closure before JSON serialization)
    - 07-RESEARCH.md Finding 4 (per-task-type routing, LLM_ONLY_TYPES stop(), .kb_for_prompt, .kb_to_evidence KB_KEY_MAP verbatim)
  </read_first>
  <behavior>
    - task_type in c("interpret","recommend_model","design_discussion","report_writing") AND provider is NULL -> stop("es_advise(): task_type '...' requires a provider ...", call.=FALSE) (ADV-06). This is a stop(), not a warning.
    - task_type in c("recommend_stat","flag_robustness") AND provider is NULL -> returns the Phase 5 es_advice object (class "es_advice", is_deterministic TRUE) unchanged.
    - task_type in c("recommend_stat","flag_robustness") WITH provider -> KB rules produce grounded evidence[] first (.kb_to_evidence), LLM adds prose; result is class "Advice", is_deterministic FALSE; guard still runs.
    - Unknown task_type -> stop() with a clear message listing the six valid types.
  </behavior>
  <action>
    Replace the tracer routing marker with full dispatch.

    1. Define `LLM_ONLY_TYPES <- c("interpret","recommend_model","design_discussion","report_writing")` and the full valid-type set. `match.arg`-style validation: unknown task_type -> stop() naming the six types.

    2. No-provider branch: LLM-only type -> stop("es_advise(): task_type '%s' requires a provider. Supply provider= or use recommend_stat()/flag_robustness() for the offline path.", call.=FALSE) per 07-RESEARCH.md Finding 4. KB type (recommend_stat/flag_robustness) with provider=NULL -> delegate to `recommend_stat(diagnostics)` / `flag_robustness(diagnostics)` (the es_diagnostics methods) and return that es_advice unchanged.

    3. `.kb_for_prompt(category=NULL)` (@noRd): `es_kb()` filtered by category, each rule mapped to list(id,category,recommendation,citation,severity) — OMIT condition (not serializable) per knowledge_base.R:420-421.

    4. `.kb_to_evidence(kb_rule, diagnostics)` (@noRd): the KB_KEY_MAP from 07-RESEARCH.md Finding 4 verbatim (KB-NORM-PATELL/KB-NONNORM-NONPAR -> estimation_window.shapiro_p; KB-VAR-INCREASE-BMP -> cross_sectional.car_iqr + car_sd; KB-OVERLAP-KP -> cross_sectional.n_overlap_pairs; KB-AC-WARN -> estimation_window.dw_stat; KB-LOWFIT-WARN -> estimation_window.r2; KB-DEGEN-EVENTS/KB-SMALL-N -> cross_sectional.n_valid_events). For each key spec resolve actual via .resolve_diag_key; vector-valued -> mean(na.rm=TRUE); build evidence list(diagnostic_key,value,threshold,direction). Because value is resolved FROM the diagnostics, this evidence is grounded by construction and the guard passes it.

    5. `.build_prompt(task_type, diagnostics, kb_context=NULL, kb_recs=NULL)` (@noRd): assemble the prompt per 07-RESEARCH.md Finding 4 structure (system context "cite only provided diagnostics, do not invent numbers"; diagnostics block via jsonlite::toJSON(unclass(diagnostics), auto_unbox=TRUE, null="null") guarded by requireNamespace; KB context for the two KB types; task instruction; schema reminder). jsonlite guarded — absent falls back to a minimal textual diagnostics block, no crash.

    6. KB-with-provider branch: run the offline KB match to get fired rules, convert via .kb_to_evidence into pre-grounded recommendations, pass as kb_recs into .build_prompt, call provider$complete(prompt, .advice_schema()), parse, and in .build_advice_from_parsed seed recommendations from the KB-grounded set (LLM fills rationale/expected_effect/interpretation prose only). Guard still runs. is_deterministic=FALSE (Pitfall 6 — any provider call is non-deterministic).

    7. LLM-only-with-provider branch: .build_prompt(task_type, diagnostics), provider$complete, parse, guard, return Advice.

    Add tests to test_advise.R: (a) `es_advise(diag,"interpret",provider=NULL)` errors with "requires a provider"; (b) `es_advise(diag,"recommend_stat",provider=NULL)` returns an "es_advice" (NOT "Advice") — offline path unchanged; (c) each of the six task types WITH a CustomProvider returning valid canned JSON returns class "Advice" with is_deterministic FALSE; (d) an unknown task_type stops.
  </behavior>
  <action>
    Implement the behavior above in R/advise.R and extend tests/testthat/test_advise.R. Regenerate NAMESPACE/man via devtools::document() if any @export changed (es_advise signature only).
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise.R")'</automated>
    <fails_when>non-zero exit, any FAIL line, the no-provider interpret case does not stop(), or the no-provider recommend_stat case does not return class "es_advice"</fails_when>
  </verify>
  <done>All six task types route correctly; LLM-only types stop() without a provider; KB types degrade to the unchanged Phase 5 es_advice path without a provider and use KB-grounded evidence + LLM prose with a provider (ADV-05, ADV-06); committed.</done>
</task>

<task type="auto">
  <name>Task 3: Failure-matrix hardening + full-suite + CRAN-absent gate</name>
  <files>R/advise.R, tests/testthat/test_advise.R</files>
  <read_first>
    - R/advise.R (Tasks 1-2 output)
    - R/provider.R:27-81 (es_provider_response with text=NA_character_ on failure — the degrade signal es_advise must absorb)
    - 07-RESEARCH.md Finding 2 (JSON round-trip traps: null->NULL, single-element arrays, integer-vs-double) and Finding 7 (Pitfalls 1,4,5)
  </read_first>
  <action>
    Harden every degrade path and lock the phase gate.

    1. Failure-matrix tests in test_advise.R via CustomProvider returning: (a) a provider failure es_provider_response (text=NA_character_) — assert es_advise returns empty Advice + exactly one warning, no crash; (b) an empty string ""; (c) malformed JSON "{not json"; (d) valid JSON but empty recommendations []; (e) a rec whose evidence value is `null` (JSON) -> resolves to NA-vs-present mismatch -> dropped; (f) an integer-vs-double value (JSON 5 vs diagnostics 5L on cross_sectional.n_overlap_pairs) -> within tolerance -> kept (Pitfall 4). Each degrade path asserts exactly ONE warning and never an error.

    2. Confirm `.resolve_diag_key` handles the indexed form: add a test citing `estimation_window.shapiro_p[3]` against the fixture and assert the guard keeps a rec whose reported value matches element 3.

    3. Assert the never-crash contract with jsonlite absent: wrap a `.parse_advice_json` call under a mocked `requireNamespace` returning FALSE (or document the guard path is covered) — assert one warning + empty Advice, no error.

    4. Run the FULL suite and confirm baseline stays green (1793 pass / 0 fail) — Advice is purely additive, existing behavior byte-identical.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise.R")' && Rscript -e 'devtools::test()'</automated>
    <fails_when>non-zero exit, any FAIL line, any degrade path raises an error instead of one warning, or the full-suite pass count regresses below 1793</fails_when>
  </verify>
  <done>Every provider/JSON failure mode degrades to one warning + empty Advice (never crash); indexed key-paths resolve; the full 1793-test suite stays green; committed.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| LLM provider -> es_advise | LLM-generated JSON is untrusted; may fabricate diagnostic values or cite absent keys |
| diagnostics -> prompt | diagnostic values serialized into the prompt (JSON, not string interpolation) |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-07-01 | Spoofing | LLM fabricated evidence values in recommendations | high | mitigate | `.validate_grounding()` rejects any evidence whose key is absent from es_diagnostics or whose value mismatches beyond tolerance; drop-and-keep + one warning + caveat |
| T-07-02 | Tampering | Prompt injection via diagnostic values | medium | mitigate | diagnostics serialized as JSON via jsonlite::toJSON, not string-interpolated into the prompt; structural injection is harder |
| T-07-03 | Denial of Service | Malformed/huge JSON from provider | medium | mitigate | `tryCatch(jsonlite::fromJSON(...))` -> NULL -> `.empty_advice()` + one warning; never crashes the session |
| T-07-04 | Information Disclosure | API key leakage on failure path | low | accept | keys never reach es_advise; redaction is enforced in Phase 6 provider layer (`.provider_failure`/redacted headers); no key handling added here |
</threat_model>

<verification>
- `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_advise.R")'` passes with zero FAIL.
- `Rscript -e 'devtools::test()'` stays at 1793 pass / 0 fail (Advice is additive).
- Guard regression: three-rec canned JSON keeps only the grounded rec, records 2 drops in a caveat, emits exactly one "Grounding guard" warning.
- No-provider LLM-only task -> stop("requires a provider"); no-provider KB task -> unchanged es_advice.
</verification>

<success_criteria>
- es_advise() returns an Advice S3 with print method carrying interpretation/recommendations[]/caveats; each recommendation has action/kind/rationale/expected_effect/evidence[]; each evidence entry is {diagnostic_key,value,threshold,direction} (ADV-01/02/03).
- Runtime guard drops ungrounded recommendations in R independent of the prompt (ADV-04).
- Six task types route correctly; LLM-only types error clearly with no provider (ADV-05/06).
- Package loads and the offline path works with jsonlite/httr2 uninstalled; full suite green.
</success_criteria>

<output>
Create `.planning/phases/07-grounded-advise-layer-grounding-guard/07-01-SUMMARY.md` when done.
</output>
