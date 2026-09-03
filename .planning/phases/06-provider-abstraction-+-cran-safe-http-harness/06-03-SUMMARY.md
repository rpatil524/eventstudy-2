---
phase: 06-provider-abstraction-+-cran-safe-http-harness
plan: 03
subsystem: grounded-ai-advisor
tags: [provider, anthropic, http, security, redaction, cran, r6]
status: complete
requires: ["06-1 (ProviderBase, es_provider_response, factory, resolvers)", "06-2 (.perform_request/.finish_response helpers, httr2 mock builders)"]
provides:
  - "AnthropicProvider (native Anthropic Messages API, tool-use structured output + text fallback)"
  - "finalized provider() factory — all three backends (custom/openai/anthropic) live"
  - "mandatory key-redaction regression test locking req_headers_redacted for x-api-key"
affects: ["R/provider.R", "NAMESPACE", "tests/testthat/*"]
tech-stack:
  added: []
  patterns:
    - "tool-use input_schema structured output with a never-crash plain text-block fallback"
    - "x-api-key attached via req_headers_redacted (req_auth_bearer_token does NOT redact it)"
    - "requireNamespace-guarded httr2/jsonlite so R CMD check stays clean with Suggests uninstalled"
key-files:
  created:
    - tests/testthat/test_provider_anthropic.R
    - tests/testthat/test_provider_redaction.R
    - man/AnthropicProvider.Rd
  modified:
    - R/provider.R
    - NAMESPACE
    - man/provider.Rd
    - tests/testthat/test_provider_resolution.R
decisions:
  - "Tool-use extraction serialized to character via jsonlite::toJSON (guarded), key=value paste fallback when jsonlite absent — keeps es_provider_response$text a single string"
  - "Removed the 06-1 exists() placeholder guard for anthropic; factory now constructs all three branches directly"
metrics:
  duration_min: 9
  completed: 2026-09-03
actuals:
  tokens: 7906
  tasks: 3
  commits: 6
---

# Phase 6 Plan 3: AnthropicProvider + Phase Gate Summary

Native `AnthropicProvider` (`POST /v1/messages`, tool-use `input_schema` structured output with a plain-text fallback), the MANDATORY key-redaction test proving the `x-api-key` never leaks into any warning/print/error path, the finalized `provider()` factory across all three backends, and the phase gate — full offline suite green (1726 pass / 0 fail) and `R CMD check` clean with no new NOTEs/WARNINGs and no Suggests-used-unconditionally NOTE. Phase 6 closes: three providers, one uniform `es_provider_response` contract, key-safe, never-crash, fully offline-tested.

## What Was Built

- **`AnthropicProvider`** (`inherit = ProviderBase`, `@export`): `initialize(model, base_url = "https://api.anthropic.com", max_tokens = 1024L)` — stores non-secret config only, never a key. `complete(prompt, schema = NULL, ...)` guards `requireNamespace("httr2")` first, resolves the key at call time via `.resolve_api_key("anthropic")` (missing/empty → one warning + NA), builds the Anthropic body (`model`, `max_tokens` REQUIRED, `messages=[{role:user,content:prompt}]`), attaches a `tools` + `tool_choice` `input_schema` block ONLY when `schema` supplied, calls the shared `.perform_request(..., auth = "x-api-key", extra_headers = list("anthropic-version" = "2023-06-01"))`, and finishes via `.finish_response()`.
- **`.extract_anthropic_text()`** (`@noRd`): prefers the first `content` block with `type == "tool_use"` and renders its `$input` to a character string (`jsonlite::toJSON` guarded, else key=value paste); falls back to the first block's `$text` when no tool_use block is present — the never-crash path when the model answers with plain text despite a schema. Wrapped by `.finish_response`'s tryCatch, so any unexpected shape degrades to one warning + NA.
- **Finalized `provider()` factory**: removed the 06-1 `exists()` "delivered in a later plan" guard; the `anthropic` branch now constructs `AnthropicProvider$new(...)` directly. All three branches (`custom`/`openai`/`anthropic`) live; `EVENTSTUDY_ADVISOR_PROVIDER` selects the default, an explicit `type` overrides it, `match.arg` rejects unknowns. Roxygen updated; `@examples` non-live (`\dontrun{}`).

## Reused Unchanged (from 06-1/06-2)

`.perform_request` (already supports `auth="x-api-key"` via `req_headers_redacted` + `extra_headers`), `.finish_response`, `.resolve_api_key`, `.resolve_provider_config`, `.provider_failure`/`.provider_success`, and the `mock_200/mock_status/mock_malformed/mock_timeout` builders in `helper-provider.R`. The Anthropic provider is thin, as designed.

## Security — Key Redaction (PROV-06, T-06-10 critical)

`tests/testthat/test_provider_redaction.R` (9 assertions, all green):
- Anthropic dummy key `sk-SECRET-DUMMY-abc123` is provably ABSENT from the emitted warning `conditionMessage`.
- **Linchpin:** the dummy `x-api-key` is absent from `capture.output(print(req))` — proving `req_headers_redacted` redacts it. A companion CONTROL test uses the unsafe plain `req_headers()` and asserts it WOULD leak, so the redaction assertion demonstrably bites (a regression to plain headers fails CI).
- OpenAI dummy bearer token absent from both the warning and the printed request (`req_auth_bearer_token` redacts `Authorization`).
- A non-2xx error reason carries neither the key nor any response body — only `"HTTP <status>"`.

**Redaction-test outcome: PASS.** No leak found; no provider fix required (the `req_headers_redacted` code from 06-2 already satisfies the guarantee; this test locks it permanently).

## Tests

- `test_provider_anthropic.R`: 15 tests (text path, tool-use structured path, text fallback despite schema, no-key, empty-key, 401, 500, malformed, timeout, empty-content, + 5 factory branch/precedence/rejection tests) — 33 assertions, 0 fail.
- `test_provider_redaction.R`: 6 tests / 9 assertions, 0 fail.
- **Full suite (`devtools::test_dir`): 1726 pass, 0 fail, 53 skip, 1 warn.** The single warning is the pre-existing rank-deficient-design warning in `test_edge_cases.R` (cross_sectional) — unrelated to this plan and out of scope. Existing Phase 1–5 tests byte-identical; valid-input behavior unchanged.

## R CMD check Gate (CRAN-02, PROV-08)

`devtools::check(document = TRUE, args = c("--no-manual"))` → **0 errors, 1 warning, 3 notes — all PRE-EXISTING baseline, none introduced by 06-3.** Ran with `_R_CHECK_FORCE_SUGGESTS_ : FALSE` (Suggests treated as absent):
- WARNING `non-ASCII characters`: em-dashes in comments/roxygen prose, present across the entire codebase (`contract.R`, `models_time_varying.R`, etc.) before 06-3 — `provider.R`'s only non-ASCII is likewise in comments, consistent with the baseline style; the warning count is unchanged.
- NOTE `hidden files and directories`: triggered by the session artifact `.gsd/dispatch-isolation-sentinel.json` (untracked, not package code).
- NOTE `portable file names`, NOTE `R code possible problems`: pre-existing baseline.
- **No "Suggests used unconditionally" NOTE** — every `httr2::`/`jsonlite::` symbol sits inside a function whose caller `requireNamespace`-guards, and `.extract_anthropic_text` guards `jsonlite` inline. This is the CRAN gate the plan requires (CRAN-02, PROV-08 closed).

`git diff DESCRIPTION` shows no change in 06-3 (deps were added in 06-1).

## New Exports

`AnthropicProvider` (added to NAMESPACE). Provider layer now exports: `ProviderBase`, `CustomProvider`, `OpenAICompatProvider`, `AnthropicProvider`, `provider`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Stale assertion] Updated the not-yet-delivered anthropic factory test**
- **Found during:** Task 3 (full suite run)
- **Issue:** `test_provider_resolution.R` carried a 06-1 assertion `expect_error(provider("anthropic"), "later plan")`. Task 3 finalizes the factory so `provider("anthropic")` now CONSTRUCTS the provider — the stale assertion contradicted the plan's explicit "remove the placeholder guard" directive and failed.
- **Fix:** Rewrote the test to `expect_true(inherits(provider("anthropic", model=...), "AnthropicProvider"))`.
- **Files modified:** tests/testthat/test_provider_resolution.R
- **Commit:** aeeaafb

## Commits

- `4d4124f` test(06-3): add failing tests for AnthropicProvider + factory (RED)
- `63e6653` feat(06-3): implement AnthropicProvider + finalize provider() factory (GREEN)
- `3a242d5` test(06-3): mandatory key-redaction guarantee (PROV-06)
- `aeeaafb` test(06-3): update factory test for now-live anthropic branch

(The redaction guarantee was already satisfied by existing 06-2 code, so Task 2 added only the locking test — no GREEN implementation commit needed.)

## Known Stubs

None. No hardcoded empty values, placeholders, or unwired data paths introduced.

## Self-Check: PASSED

All created files exist on disk (`R/provider.R`, `test_provider_anthropic.R`, `test_provider_redaction.R`, `man/AnthropicProvider.Rd`, this SUMMARY); all four task commits (`4d4124f`, `63e6653`, `3a242d5`, `aeeaafb`) exist in git; `export(AnthropicProvider)` present in NAMESPACE.
