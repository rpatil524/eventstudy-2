---
phase: 07-grounded-advise-layer-grounding-guard
plan: 1
subsystem: grounded-advise-engine
tags: [advisor, llm, grounding-guard, s3, cran-safe]
requires:
  - "Phase 5 es_diagnostics() six-section object (R/es_diagnostics.R) as the sole ground-truth the guard validates against"
  - "Phase 5 es_advice + recommend_stat/flag_robustness offline path (R/advise_offline.R)"
  - "Phase 5 es_kb() decision table (R/knowledge_base.R) for KB-grounded evidence"
  - "Phase 6 provider()/ProviderBase$complete(prompt, schema) + es_provider_response (R/provider.R)"
provides:
  - "es_advise(diagnostics, task_type, provider=NULL, model=NULL, ...) @export — routes all six task types"
  - "Advice S3 object + print.Advice @export (shares source/is_deterministic field names with es_advice/es_provider_response)"
  - ".validate_grounding() runtime grounding guard (drop-and-keep, single warning point)"
  - ".resolve_diag_key() section.key / section.key[i] path resolver"
  - ".kb_to_evidence()/.kb_for_prompt() KB-grounded evidence for recommend_stat/flag_robustness"
  - ".advice_schema()/.parse_advice_json()/.build_advice_from_parsed()/.build_prompt()/.empty_advice() helpers"
affects:
  - "07-2 generate_report(advice=) consumes an Advice object from es_advise(task_type='report_writing')"
  - "Phase 8 Agent Skill orchestrates es_diagnostics -> es_advise"
tech-stack:
  added: []
  patterns:
    - "runtime R grounding guard independent of the prompt (ADV-04)"
    - "drop-and-keep degrade with exactly ONE warning, mirroring .handle_degenerate()"
    - "KB-grounds/LLM-interprets: KB produces evidence[], LLM fills prose only"
    - "provider schema -> JSON structured output, jsonlite-guarded (Suggests)"
key-files:
  created:
    - R/advise.R
    - tests/testthat/test_advise.R
    - tests/testthat/helper-advice-fixtures.R
    - man/es_advise.Rd
    - man/print.Advice.Rd
  modified:
    - NAMESPACE
decisions:
  - "Guard failure = drop-and-keep: drop only the ungrounded recommendation, keep the rest, append one caveat recording N drops, emit exactly ONE warning, never stop()"
  - "recommend_stat/flag_robustness WITH provider = KB grounds evidence[] first (.kb_to_evidence), LLM adds prose; no provider = unchanged Phase 5 es_advice"
  - "interpret/recommend_model/design_discussion/report_writing = LLM-required: stop() clearly when provider=NULL (ADV-06)"
  - "Guard scope = structured evidence[] only; no prose numeric-token scanning"
  - "Provider-already-failed responses (resp$error set) degrade SILENTLY in .parse_advice_json — the provider layer already emitted its one warning; a second would break the exactly-one-warning contract"
  - "Tolerance abs(reported-actual) <= max(abs_tol, rel_tol*abs(actual)); abs_tol 1e-6, rel_tol 1e-4 via getOption seam; NA-vs-present is a mismatch"
metrics:
  duration: "~18 min (executor) + recovery"
  completed: "2026-09-04"
actuals:
  tasks: 3
  commits: 1
recovery:
  note: "Executor afb5d33 crashed on a mid-response connection error before its atomic commits/SUMMARY. Work verified and committed in recovery (e477988) with three fixes."
status: complete
---

# Phase 7 Plan 1: Grounded Advise Engine + Grounding Guard Summary

Delivered `es_advise()` — the grounded interpretation layer that turns deterministic `es_diagnostics()` output into human-facing `Advice` via an optional LLM provider, with a runtime R grounding guard that guarantees every returned recommendation is provably tied to a diagnostic the package actually computed. The tracer slice (recommend_stat + CustomProvider canned JSON → parse → guard → Advice) was proven end-to-end before expansion to all six task types and the failure matrix.

## What Was Built

- **`es_advise(diagnostics, task_type, provider=NULL, model=NULL, ...)`** (`@export`): six-task-type dispatch. `recommend_stat`/`flag_robustness` degrade to the unchanged Phase 5 `es_advice` when `provider=NULL`, and use KB-grounded evidence + LLM prose when a provider is supplied. `interpret`/`recommend_model`/`design_discussion`/`report_writing` `stop()` clearly without a provider (ADV-06). Unknown task types `stop()` naming the six valid ones.
- **`Advice` S3 + `print.Advice`** (`@export`): plain classed list `{source, is_deterministic, task_type, interpretation, recommendations[], caveats, n_dropped}`; each recommendation carries `action/kind/rationale/expected_effect/evidence[]`; each evidence entry is `{diagnostic_key, value, threshold, direction}`. Field names shared with `es_advice`/`es_provider_response` for shape-compatibility.
- **`.validate_grounding()`** (`@noRd`): the SINGLE guard/warning point. For each recommendation, resolves every `evidence$diagnostic_key` against the diagnostics; drops the whole recommendation on any absent key, out-of-tolerance value, or NA-vs-present mismatch; keeps the rest; appends one caveat recording N drops; emits exactly ONE `warning(call.=FALSE)` when `n_drop>0`; sets `n_dropped`. Never `stop()` (ADV-04).
- **`.resolve_diag_key()`** (`@noRd`): resolves `section.key` and `section.key[i]` paths against the six `es_diagnostics` sections; vector-valued keys reduced via mean where appropriate.
- **`.kb_for_prompt()` / `.kb_to_evidence()`** (`@noRd`): filter `es_kb()` by category and map each fired rule to grounded `evidence[]` whose values are resolved FROM the diagnostics (grounded by construction → passes the guard).
- **`.advice_schema()` / `.parse_advice_json()` / `.build_advice_from_parsed()` / `.build_prompt()` / `.empty_advice()`** (`@noRd`): JSON structured-output schema; jsonlite-guarded parse that degrades to one warning + empty Advice on malformed/partial/empty JSON; Advice assembly + guard invocation; per-task-type prompt builder (with the explicit "do NOT invent keys or add recommendations — prose only" instruction for KB-grounded types); empty-Advice constructor.

## New Exports

`es_advise`, `print.Advice` (NAMESPACE via roxygen2).

## Verification

- `test_advise.R`: **61 pass, 0 fail, 0 warn.** Covers the deterministic three-recommendation guard regression (one valid rec survives, two dropped — a missing key and an out-of-tolerance value — one warning, caveat records 2 drops), all six task-type routes, no-provider `stop()` for LLM-only types, no-provider offline-`es_advice` preservation for KB types, and the full failure matrix (NA/empty/malformed JSON degrade to one warning + empty Advice).
- **Full suite: 1803 pass, 0 fail, 53 skip, 1 warn.** The 53 skips (CRAN optional-dep) and 1 warning (`test_edge_cases.R:817` rank-deficient design) are pre-existing and unrelated. Valid-input behavior of Phase 1–6 code unchanged.

## Recovery Fixes (executor crashed before commit)

The `gsd-executor` (afb5d33) wrote all of `R/advise.R`, the tests, and the man pages but died on a mid-response connection error before its atomic commits and SUMMARY. The work was verified and committed in recovery (`e477988`) with three fixes on top of its code:

1. **Contract fix (double-warning):** on the provider-already-failed path the code warned twice — once in the Phase 6 provider layer (`.provider_failure`) and again in `.parse_advice_json` ("returned no text"). This violated the milestone's exactly-one-warning core value. Fix: `.parse_advice_json` now returns an empty Advice **silently** when `resp$error` is set (the provider already warned); it only warns itself when the provider *succeeded* but returned unusable text/JSON.
2. **Test fix (empty-recs print):** the `print.Advice` "No recommendations" test used `recommend_stat`, which back-fills KB-grounded recs and never hits the empty branch; switched to `interpret` (LLM-only, no back-fill).
3. **Test fix (degrade capture):** the NA-provider degrade test used `result <- expect_warning(...)`, which captures the warning condition, not the value; switched to the executor's own `.advise_expect_warning` helper.

## Deviations from Plan

None in scope — all three plan tasks (tracer, six-type expansion, failure-matrix hardening) delivered. The double-warning was a latent contract bug exposed during recovery verification, not a plan deviation; fixed to honor the locked drop-and-keep single-warning discipline.

## Self-Check: PASSED

- FOUND: R/advise.R, tests/testthat/test_advise.R, tests/testthat/helper-advice-fixtures.R, man/es_advise.Rd, man/print.Advice.Rd
- FOUND commit: e477988
- NAMESPACE contains export(es_advise), S3method(print, Advice)
- Full suite green (1803 pass / 0 fail); exactly-one-warning contract verified on the provider-failure path
