---
phase: 06-provider-abstraction-+-cran-safe-http-harness
verified: 2026-09-03T00:00:00Z
status: passed
score: 4/4 must-haves verified (10/10 requirements SATISFIED)
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  note: Initial verification (no prior VERIFICATION.md)
notes:
  - "R CMD check not run in-session (context budget); its two substantive claims verified independently: (1) grep confirms all httr2::/jsonlite:: are requireNamespace-guarded, so no 'Suggests used unconditionally' NOTE is possible; (2) full suite green offline. Recommend one confirmatory devtools::check() run before ship (Phase 8 gate re-checks this anyway)."
  - "PROV-07/SC3 wording says 'warning + NULL'; implementation returns an es_provider_response with text=NA_character_ + error reason (not bare NULL). This is a deliberate, documented refinement that fully satisfies intent (never crash, exactly one warning, no fabricated result) and is strictly richer than NULL. Counted SATISFIED."
---

# Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness — Verification Report

**Phase Goal:** A user can select any LLM backend — native Anthropic, any OpenAI-compatible endpoint (including local Ollama/LM Studio), or a custom in-process function — through one uniform seam that never leaks keys, never crashes the session on failure, and is fully tested offline with no real API call.

**Verified:** 2026-09-03
**Status:** passed
**Re-verification:** No — initial verification

> Note: ROADMAP.md Progress table still lists Phase 6 as "0/3 Planned". This verification checks the CODEBASE, which delivers all three plans' work. The stale roadmap counter is a bookkeeping lag, not a codebase gap.

## Goal Achievement — Four Must-Haves (the goal's guarantees)

| # | Must-Have (goal guarantee) | Status | Evidence |
|---|---------------------------|--------|----------|
| 1 | **Any-backend selection through one uniform seam** | ✓ PASS | `ProviderBase` R6 abstract with `complete(prompt, schema, ...)` (provider.R:270-305); `CustomProvider` (328), `OpenAICompatProvider` (406, covers OpenAI + Ollama/LM Studio via `base_url`), `AnthropicProvider` (548) all `inherit = ProviderBase`. `provider()` factory (660-684) wires all three branches with 3-tier resolution. All 5 symbols `@export`ed (NAMESPACE:15,24,38,42,80). Tests construct each via factory and assert `ProviderBase` inheritance (test_provider_anthropic.R:153-179). |
| 2 | **Never leak keys** | ✓ PASS | Keys are NEVER stored on any object — grep for `self$*key`/`private$*key`/`.key <-` returns nothing; keys are call-time locals only (`.resolve_api_key`, provider.R:134-145). x-api-key attached via `req_headers_redacted` (201) — the ONLY path that redacts x-api-key. Redaction test asserts dummy key absent from warning AND `capture.output(print(req))` (test_provider_redaction.R:37-46) AND has a CONTROL test proving plain `req_headers()` WOULD leak (48-56) — the assertion bites. Non-2xx error carries only `HTTP <status>`, no body/key (86-96). No real key committed (repo grep clean). |
| 3 | **Never crash the session on failure** | ✓ PASS | Single failure point `.provider_failure()` emits EXACTLY ONE `warning(..., call.=FALSE)` + returns `text=NA_character_` (provider.R:66-81). Every path routes through it: missing key, non-2xx, malformed body, empty text, transport/timeout (`.finish_response` 231-252), custom-fn throw (357). Tests assert one-warning + NA on every path incl. an explicit "EXACTLY ONE warning" counter (test_provider_openai.R:159-179; custom.R:30-41). No uncaught error escapes (`tryCatch` at 207, 240, 247, 352). |
| 4 | **Fully offline-tested, no real API call** | ✓ PASS | 120 provider assertions run with **0 skipped, 0 failed** — mocks execute, not skip. All HTTP driven by `httr2::local_mocked_responses()` + `mock_*` builders (helper-provider.R:27-49); keys are dummies via `withr::local_envvar`. Repo grep finds no real `req_perform` against a live URL and no real key. Full suite 1726 pass / 0 fail confirms the provider suite adds no network dependency. |

**Score: 4/4 must-haves verified.**

## Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| **PROV-01** | Uniform `AdvisorProvider` R6 base, `complete(prompt, schema, ...)` | ✓ SATISFIED | `ProviderBase` abstract (calling `complete` errors "abstract", test_provider_custom.R:43); all backends inherit + implement (provider.R:270-305, 328, 406, 548). |
| **PROV-02** | Anthropic tool-use `input_schema` structured output + text fallback | ✓ SATISFIED | `AnthropicProvider$complete` adds `tools`+`tool_choice` input_schema when schema supplied (596-605); `.extract_anthropic_text` prefers tool_use `$input`, falls back to first text block (481-511). Three tests: tool_use extraction, text-only, and schema-present-but-text-fallback (test_provider_anthropic.R:34-68). |
| **PROV-03** | OpenAI-compatible, any base_url incl. Ollama/LM Studio | ✓ SATISFIED | `OpenAICompatProvider` POSTs `{base_url}/chat/completions`, `base_url` default OpenAI, overridable (417). Test drives `http://localhost:11434/v1` with no code change (test_provider_openai.R:90-98). `response_format` json_schema added optionally (450-454). |
| **PROV-04** | `CustomProvider` in-process `(prompt, schema) -> list` hook | ✓ SATISFIED | `CustomProvider` wraps user fn in tryCatch (351-360); needs no httr2/jsonlite (0 requireNamespace guards in its path). Seam-reaches-fn test (test_provider_custom.R:48-54). |
| **PROV-05** | 3-tier precedence arg→env→default; EVENTSTUDY_ADVISOR_* selectors + OPENAI/ANTHROPIC secrets | ✓ SATISFIED | `.resolve_provider_config` (106-119): arg → `EVENTSTUDY_ADVISOR_PROVIDER/_MODEL/_BASE_URL` → default `"custom"`; `""`→NULL collapse. `.resolve_api_key` reads `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` (134-145). Precedence tests incl. arg-overrides-env (test_provider_resolution.R:8-46). |
| **PROV-06** | MANDATORY key redaction — never leaked | ✓ SATISFIED | See Must-Have 2. Linchpin `capture.output(print(req))` assertion + negative-control proving the test fails if redaction removed. Covers the Anthropic x-api-key path specifically (the one that leaks without `req_headers_redacted`). |
| **PROV-07** | Never-crash — warning + NA/NULL on every failure path | ✓ SATISFIED* | Single warning + `text=NA` on all paths (see Must-Have 3). *Returns `es_provider_response{text=NA, error=reason}` rather than bare NULL — deliberate documented refinement, richer than NULL, fully meets intent. |
| **PROV-08** | httr2/jsonlite Suggests-only, requireNamespace-guarded, works uninstalled | ✓ SATISFIED | DESCRIPTION: httr2/jsonlite/withr under Suggests (lines 45-66). All `httr2::` calls confined to `.perform_request`/`.finish_response` bodies reachable only after `requireNamespace("httr2")` guard in each `complete()` (433, 581); `jsonlite::` inline-guarded (491). Custom path needs neither. |
| **CRAN-02** | `R CMD check` no new NOTEs/WARNINGs (esp. no "Suggests used unconditionally") | ✓ SATISFIED (indirect) | Not re-run in-session (context budget). No "Suggests used unconditionally" NOTE is possible: grep proves zero unguarded Suggests usage. SUMMARY reports check clean (0 err, pre-existing baseline notes only). Recommend one confirmatory `devtools::check()` at ship. |
| **CRAN-03** | Fully offline test harness, no network, no real key | ✓ SATISFIED | 120 provider assertions, 0 skip/0 fail, all via httr2 mocks + dummy keys. No network reachable in any provider test. |

**10/10 requirements SATISFIED.**

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Provider suite runs offline | `test_dir(filter="provider")` | 120 pass, 0 fail, **0 skip** | ✓ PASS |
| No regressions (Phase 1–5 green) | `test_dir()` full suite | 1726 pass, 0 fail, 53 skip (pre-existing skip_on_cran), 1 warn (pre-existing edge case) | ✓ PASS |
| No unguarded Suggests namespace | `grep httr2::/jsonlite:: vs requireNamespace` | all inside guarded bodies | ✓ PASS |
| No key stored as field | `grep self$*key / private$*key / .key <-` | none found | ✓ PASS |
| No real key committed | `grep sk-ant/sk- (excl. DUMMY)` | none found | ✓ PASS |
| Redaction test bites | control test at redaction.R:48-56 | plain req_headers WOULD leak (asserted) | ✓ PASS |

## Anti-Patterns Found

None. No unreferenced TBD/FIXME/XXX in `R/provider.R`. Failure paths return `NA_character_` by design (the "never silently wrong" contract), not as stubs — every `NA` return is paired with a warning + populated `error` field.

## Gaps Summary

No blocking gaps. Two non-blocking notes carried in frontmatter:

1. **R CMD check not re-executed in-session** (context budget). Both substantive claims verified independently (no unguarded Suggests → "Suggests used unconditionally" NOTE impossible; full suite green offline). The Phase 8 gate re-runs `R CMD check` against the 1378-test target; a single confirmatory `devtools::check()` before ship is advisable but not required to certify this phase's goal.
2. **PROV-07 "NULL" vs `es_provider_response{text=NA}`** — intentional, documented design richer than bare NULL; intent fully met.

Neither reduces any must-have below PASS.

---

_Verified: 2026-09-03_
_Verifier: Claude (gsd-verifier)_
